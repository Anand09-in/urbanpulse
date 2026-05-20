import pytest
from unittest.mock import patch, MagicMock
import urllib.error
import sys
sys.path.insert(0, "ingestion")
from handler import get_target_period, handler


def test_get_target_period_from_event():
    year, month = get_target_period({"year": "2026", "month": "03"})
    assert year == "2026"
    assert month == "03"


def test_get_target_period_defaults_to_previous_month():
    year, month = get_target_period({})
    assert len(year) == 4
    assert len(month) == 2
    assert month.isdigit()
    assert 1 <= int(month) <= 12


@patch("handler.s3")
@patch("handler.urllib.request.urlopen")
def test_handler_success(mock_urlopen, mock_s3):
    mock_response = MagicMock()
    mock_response.__enter__ = lambda s: s
    mock_response.__exit__ = MagicMock(return_value=False)
    mock_urlopen.return_value = mock_response
    mock_s3.upload_fileobj.return_value = {}

    result = handler({"year": "2026", "month": "01"}, {})

    assert result["statusCode"] == 200
    assert result["period"] == "2026-01"
    assert result["summary"]["success"] == 3   # yellow + green + fhv
    assert mock_s3.upload_fileobj.call_count == 3


@patch("handler.urllib.request.urlopen")
def test_handler_file_not_found(mock_urlopen):
    mock_urlopen.side_effect = urllib.error.HTTPError(
        url=None, code=404, msg="Not Found", hdrs=None, fp=None
    )

    result = handler({"year": "2026", "month": "01"}, {})

    assert result["summary"]["not_found"] == 3
    assert result["summary"]["success"] == 0
