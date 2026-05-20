import sys
import logging
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import DoubleType, IntegerType, TimestampType

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Job args passed in by Glue ─────────────────────────────────────
args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "bronze_bucket",
    "silver_bucket",
    "year",
    "month",
])

sc          = SparkContext()
glueContext = GlueContext(sc)
spark       = glueContext.spark_session
job         = Job(glueContext)
job.init(args["JOB_NAME"], args)

YEAR   = args["year"]
MONTH  = args["month"]
BRONZE = f"s3://{args['bronze_bucket']}"
SILVER = f"s3://{args['silver_bucket']}"

logger.info(f"Processing period: {YEAR}-{MONTH}")


# ──────────────────────────────────────────────────────────────────
# STEP 1 — Load Zone Lookup reference table
# ──────────────────────────────────────────────────────────────────
zones = (
    spark.read
    .option("header", "true")
    .csv(f"{BRONZE}/reference/taxi_zone_lookup.csv")
    .select(
        F.col("LocationID").cast(IntegerType()).alias("location_id"),
        F.col("Borough").alias("borough"),
        F.col("Zone").alias("zone"),
        F.col("service_zone"),
    )
)


# ──────────────────────────────────────────────────────────────────
# STEP 2 — Process Yellow Taxi
# ──────────────────────────────────────────────────────────────────
def process_yellow(bronze_path: str, zones_df) -> "DataFrame":
    raw = spark.read.parquet(
        f"{bronze_path}/year={YEAR}/month={MONTH}/source=yellow/"
    )

    cleaned = (
        raw
        # Cast core columns
        .withColumn("pickup_datetime",
            F.col("tpep_pickup_datetime").cast(TimestampType()))
        .withColumn("dropoff_datetime",
            F.col("tpep_dropoff_datetime").cast(TimestampType()))
        .withColumn("fare_amount",
            F.col("fare_amount").cast(DoubleType()))
        .withColumn("tip_amount",
            F.col("tip_amount").cast(DoubleType()))
        .withColumn("total_amount",
            F.col("total_amount").cast(DoubleType()))
        .withColumn("trip_distance",
            F.col("trip_distance").cast(DoubleType()))
        .withColumn("passenger_count",
            F.col("passenger_count").cast(IntegerType()))
        .withColumn("PULocationID",
            F.col("PULocationID").cast(IntegerType()))
        .withColumn("DOLocationID",
            F.col("DOLocationID").cast(IntegerType()))
        .withColumn("payment_type",
            F.col("payment_type").cast(IntegerType()))

        # Deduplication
        .dropDuplicates([
            "tpep_pickup_datetime",
            "tpep_dropoff_datetime",
            "PULocationID",
            "DOLocationID",
        ])

        # ── Data quality filters ───────────────────────────────────
        # Drop nulls on critical columns
        .dropna(subset=["pickup_datetime", "dropoff_datetime",
                        "PULocationID", "DOLocationID"])
        # Valid fare range (NYC base fare is $3.00)
        .filter(F.col("fare_amount").between(3.0, 500.0))
        # Valid distance
        .filter(F.col("trip_distance").between(0.1, 200.0))
        # Valid location IDs
        .filter(F.col("PULocationID").between(1, 263))
        .filter(F.col("DOLocationID").between(1, 263))
        # Valid passenger count
        .filter(F.col("passenger_count").between(1, 8))
        # Trip must be in correct month
        .filter(F.month("pickup_datetime") == int(MONTH))
        .filter(F.year("pickup_datetime") == int(YEAR))

        # ── Derived columns ────────────────────────────────────────
        .withColumn("trip_duration_mins",
            (F.unix_timestamp("dropoff_datetime") -
             F.unix_timestamp("pickup_datetime")) / 60)
        .withColumn("pickup_hour",
            F.hour("pickup_datetime"))
        .withColumn("pickup_day_of_week",
            F.dayofweek("pickup_datetime"))          # 1=Sun, 7=Sat
        .withColumn("is_weekend",
            F.col("pickup_day_of_week").isin([1, 7]))
        .withColumn("is_rush_hour",
            F.col("pickup_hour").isin([7, 8, 9, 17, 18, 19]))
        .withColumn("tip_pct",
            F.when(F.col("fare_amount") > 0,
                F.round(F.col("tip_amount") /
                        F.col("fare_amount") * 100, 2))
            .otherwise(F.lit(0.0)))
        .withColumn("taxi_type", F.lit("yellow"))
        .withColumn("year",  F.lit(YEAR))
        .withColumn("month", F.lit(MONTH))

        # Valid duration check (1 min to 4 hours)
        .filter(F.col("trip_duration_mins").between(1, 240))
    )

    # ── Enrich with zone names ─────────────────────────────────────
    enriched = (
        cleaned
        .join(zones_df.alias("pu"),
              F.col("PULocationID") == F.col("pu.location_id"), "left")
        .withColumnRenamed("borough", "pickup_borough")
        .withColumnRenamed("zone",    "pickup_zone")
        .drop("pu.location_id", "service_zone")

        .join(zones_df.alias("do"),
              F.col("DOLocationID") == F.col("do.location_id"), "left")
        .withColumnRenamed("borough", "dropoff_borough")
        .withColumnRenamed("zone",    "dropoff_zone")
        .drop("do.location_id", "service_zone")

        .select(
            "taxi_type", "pickup_datetime", "dropoff_datetime",
            "trip_duration_mins", "trip_distance",
            "PULocationID", "pickup_borough", "pickup_zone",
            "DOLocationID", "dropoff_borough", "dropoff_zone",
            "passenger_count", "fare_amount", "tip_amount",
            "total_amount", "tip_pct", "payment_type",
            "pickup_hour", "pickup_day_of_week",
            "is_weekend", "is_rush_hour",
            "year", "month",
        )
    )
    return enriched


# ──────────────────────────────────────────────────────────────────
# STEP 3 — Process Green Taxi (same logic, different column names)
# ──────────────────────────────────────────────────────────────────
def process_green(bronze_path: str, zones_df) -> "DataFrame":
    raw = spark.read.parquet(
        f"{bronze_path}/year={YEAR}/month={MONTH}/source=green/"
    )

    cleaned = (
        raw
        .withColumnRenamed("lpep_pickup_datetime",  "tpep_pickup_datetime")
        .withColumnRenamed("lpep_dropoff_datetime", "tpep_dropoff_datetime")
        .withColumn("pickup_datetime",
            F.col("tpep_pickup_datetime").cast(TimestampType()))
        .withColumn("dropoff_datetime",
            F.col("tpep_dropoff_datetime").cast(TimestampType()))
        .withColumn("fare_amount",   F.col("fare_amount").cast(DoubleType()))
        .withColumn("tip_amount",    F.col("tip_amount").cast(DoubleType()))
        .withColumn("total_amount",  F.col("total_amount").cast(DoubleType()))
        .withColumn("trip_distance", F.col("trip_distance").cast(DoubleType()))
        .withColumn("passenger_count",
            F.col("passenger_count").cast(IntegerType()))
        .withColumn("PULocationID",
            F.col("PULocationID").cast(IntegerType()))
        .withColumn("DOLocationID",
            F.col("DOLocationID").cast(IntegerType()))
        .withColumn("payment_type",
            F.col("payment_type").cast(IntegerType()))

        .dropDuplicates([
            "tpep_pickup_datetime", "tpep_dropoff_datetime",
            "PULocationID", "DOLocationID",
        ])
        .dropna(subset=["pickup_datetime", "dropoff_datetime",
                        "PULocationID", "DOLocationID"])
        .filter(F.col("fare_amount").between(3.0, 500.0))
        .filter(F.col("trip_distance").between(0.1, 200.0))
        .filter(F.col("PULocationID").between(1, 263))
        .filter(F.col("DOLocationID").between(1, 263))
        .filter(F.month("pickup_datetime") == int(MONTH))
        .filter(F.year("pickup_datetime") == int(YEAR))

        .withColumn("trip_duration_mins",
            (F.unix_timestamp("dropoff_datetime") -
             F.unix_timestamp("pickup_datetime")) / 60)
        .withColumn("pickup_hour",        F.hour("pickup_datetime"))
        .withColumn("pickup_day_of_week", F.dayofweek("pickup_datetime"))
        .withColumn("is_weekend",
            F.col("pickup_day_of_week").isin([1, 7]))
        .withColumn("is_rush_hour",
            F.col("pickup_hour").isin([7, 8, 9, 17, 18, 19]))
        .withColumn("tip_pct",
            F.when(F.col("fare_amount") > 0,
                F.round(F.col("tip_amount") /
                        F.col("fare_amount") * 100, 2))
            .otherwise(F.lit(0.0)))
        .withColumn("taxi_type", F.lit("green"))
        .withColumn("year",  F.lit(YEAR))
        .withColumn("month", F.lit(MONTH))
        .filter(F.col("trip_duration_mins").between(1, 240))
    )

    enriched = (
        cleaned
        .join(zones_df.alias("pu"),
              F.col("PULocationID") == F.col("pu.location_id"), "left")
        .withColumnRenamed("borough", "pickup_borough")
        .withColumnRenamed("zone",    "pickup_zone")
        .join(zones_df.alias("do"),
              F.col("DOLocationID") == F.col("do.location_id"), "left")
        .withColumnRenamed("borough", "dropoff_borough")
        .withColumnRenamed("zone",    "dropoff_zone")
        .select(
            "taxi_type", "pickup_datetime", "dropoff_datetime",
            "trip_duration_mins", "trip_distance",
            "PULocationID", "pickup_borough", "pickup_zone",
            "DOLocationID", "dropoff_borough", "dropoff_zone",
            "passenger_count", "fare_amount", "tip_amount",
            "total_amount", "tip_pct", "payment_type",
            "pickup_hour", "pickup_day_of_week",
            "is_weekend", "is_rush_hour",
            "year", "month",
        )
    )
    return enriched


# ──────────────────────────────────────────────────────────────────
# STEP 4 — Union Yellow + Green, write Silver
# ──────────────────────────────────────────────────────────────────
yellow_df = process_yellow(BRONZE, zones)
green_df  = process_green(BRONZE, zones)

silver_df = yellow_df.unionByName(green_df)

# Row count logging — useful for monitoring
raw_count    = yellow_df.count() + green_df.count()
silver_count = silver_df.count()
logger.info(f"Silver row count: {silver_count:,}")
logger.info(f"Rows dropped (quality): {raw_count - silver_count:,}")

# Write Silver as Parquet, partitioned by year + month + taxi_type
(
    silver_df
    .write
    .mode("overwrite")
    .partitionBy("year", "month", "taxi_type")
    .parquet(f"{SILVER}/trips/")
)

logger.info(f"Silver written to {SILVER}/trips/")
job.commit()