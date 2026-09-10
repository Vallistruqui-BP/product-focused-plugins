"""Unit tests for botmaker_client.py.template -- exercises the retry/auth/
pagination/credentials logic without hitting the real Botmaker API. Loaded
by file path since the shipped file intentionally isn't named *.py (it's a
template with FILL-IN placeholders a target project fills in before use)."""
import importlib.machinery
import importlib.util
import io
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import MagicMock, patch

MODULE_PATH = Path(__file__).parent / "botmaker_client.py.template"


def load_module():
    # spec_from_file_location can't infer a loader for a non-.py suffix
    # (returns None), so build the SourceFileLoader explicitly.
    loader = importlib.machinery.SourceFileLoader("botmaker_client_template", str(MODULE_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def http_error(code, body=b"{}"):
    return urllib.error.HTTPError(
        url="https://api.botmaker.com/v2.0/x", code=code, msg="err",
        hdrs=None, fp=io.BytesIO(body),
    )


def ok_response(payload):
    response = MagicMock()
    response.read.return_value = json.dumps(payload).encode("utf-8")
    response.__enter__.return_value = response
    response.__exit__.return_value = False
    return response


class CredentialsTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    def test_save_and_load_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.module.CREDENTIALS_PATH = Path(tmp) / "creds.json"
            self.module.save_credentials("tok123", "secret456", "refresh789")

            loaded = self.module._load_credentials()
            self.assertEqual(loaded["access_token"], "tok123")
            self.assertEqual(loaded["secret_id"], "secret456")
            self.assertEqual(loaded["refresh_token"], "refresh789")
            self.assertIn("saved_at", loaded)

    def test_load_credentials_missing_file_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.module.CREDENTIALS_PATH = Path(tmp) / "does_not_exist.json"
            with self.assertRaises(RuntimeError):
                self.module._load_credentials()


class CallTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()
        self._tmp = tempfile.TemporaryDirectory()
        self.module.CREDENTIALS_PATH = Path(self._tmp.name) / "creds.json"
        self.module.save_credentials("tok123")

    def tearDown(self):
        self._tmp.cleanup()

    @patch("time.sleep", return_value=None)
    @patch("urllib.request.urlopen")
    def test_success_returns_parsed_json(self, mock_urlopen, mock_sleep):
        mock_urlopen.return_value = ok_response({"items": [1, 2]})
        result = self.module.call("GET", "/channels")
        self.assertEqual(result, {"items": [1, 2]})
        mock_urlopen.assert_called_once()

    @patch("time.sleep", return_value=None)
    @patch("urllib.request.urlopen")
    def test_401_raises_auth_error_without_retry(self, mock_urlopen, mock_sleep):
        mock_urlopen.side_effect = http_error(401)
        with self.assertRaises(self.module.BotmakerAuthError):
            self.module.call("GET", "/channels")
        mock_urlopen.assert_called_once()
        mock_sleep.assert_not_called()

    @patch("time.sleep", return_value=None)
    @patch("urllib.request.urlopen")
    def test_403_raises_auth_error_without_retry(self, mock_urlopen, mock_sleep):
        mock_urlopen.side_effect = http_error(403)
        with self.assertRaises(self.module.BotmakerAuthError):
            self.module.call("GET", "/channels")
        mock_urlopen.assert_called_once()

    @patch("time.sleep", return_value=None)
    @patch("urllib.request.urlopen")
    def test_429_retries_then_succeeds(self, mock_urlopen, mock_sleep):
        mock_urlopen.side_effect = [http_error(429), ok_response({"items": []})]
        result = self.module.call("GET", "/channels")
        self.assertEqual(result, {"items": []})
        self.assertEqual(mock_urlopen.call_count, 2)
        mock_sleep.assert_called_once()

    @patch("time.sleep", return_value=None)
    @patch("urllib.request.urlopen")
    def test_500_exhausts_retries_then_raises(self, mock_urlopen, mock_sleep):
        mock_urlopen.side_effect = http_error(500)
        with self.assertRaises(self.module.BotmakerAPIError):
            self.module.call("GET", "/channels")
        self.assertEqual(mock_urlopen.call_count, self.module.MAX_RETRIES + 1)

    @patch("time.sleep", return_value=None)
    @patch("urllib.request.urlopen")
    def test_404_raises_without_retry(self, mock_urlopen, mock_sleep):
        mock_urlopen.side_effect = http_error(404)
        with self.assertRaises(self.module.BotmakerAPIError):
            self.module.call("GET", "/channels")
        mock_urlopen.assert_called_once()

    @patch("urllib.request.urlopen")
    def test_sends_access_token_header(self, mock_urlopen):
        mock_urlopen.return_value = ok_response({"items": []})
        self.module.call("GET", "/channels")
        request = mock_urlopen.call_args[0][0]
        # Request.get_header() does no case-folding of its own (only
        # add_header() capitalizes when storing), so look up the exact
        # stored key.
        self.assertEqual(request.get_header("Access-token"), "tok123")


class PaginateTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    @patch("time.sleep", return_value=None)
    def test_follows_next_page_until_absent(self, mock_sleep):
        pages = [
            {"items": [1, 2], "nextPage": "https://api.botmaker.com/v2.0/messages?page=2"},
            {"items": [3], "nextPage": None},
        ]
        with patch.object(self.module, "call", side_effect=pages) as mock_call:
            items = list(self.module.paginate("/messages"))
        self.assertEqual(items, [1, 2, 3])
        self.assertEqual(mock_call.call_count, 2)

    def test_max_pages_guard_raises(self):
        self.module.MAX_PAGES = 1
        infinite_page = {"items": [1], "nextPage": "https://api.botmaker.com/v2.0/messages?page=999"}
        with patch.object(self.module, "call", return_value=infinite_page):
            with self.assertRaises(self.module.BotmakerAPIError):
                list(self.module.paginate("/messages"))


class WrapperTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    def test_get_channels_passes_expected_params(self):
        with patch.object(self.module, "call", return_value={"items": ["ch1"]}) as mock_call:
            result = self.module.get_channels()
        self.assertEqual(result, ["ch1"])
        mock_call.assert_called_once_with("GET", "/channels", params={"platform": "whatsapp", "active": "true"})

    def test_get_whatsapp_templates_passes_expected_params(self):
        with patch.object(self.module, "call", return_value={"items": ["tpl1"]}) as mock_call:
            result = self.module.get_whatsapp_templates()
        self.assertEqual(result, ["tpl1"])
        mock_call.assert_called_once_with("GET", "/whatsapp/templates", params={"state": "APPROVED"})

    def test_get_sessions_adds_timestamp_precision(self):
        with patch.object(self.module, "paginate", return_value=iter([])) as mock_paginate:
            list(self.module.get_sessions())
        mock_paginate.assert_called_once_with("/sessions", params={"timestamp-precision": "milliseconds"})


if __name__ == "__main__":
    unittest.main()
