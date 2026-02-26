import unittest
import requests
import os

BASE_URL = os.environ.get("NITTER_URL", "http://localhost:8080")

class TestJsonApi(unittest.TestCase):
    def test_home_feed_json(self):
        """Verify GET / with Accept: application/json returns expected JSON structure."""
        headers = {"Accept": "application/json"}
        try:
            response = requests.get(f"{BASE_URL}/", headers=headers, timeout=5)
        except requests.exceptions.ConnectionError:
            self.fail(f"Could not connect to Nitter at {BASE_URL}. Is it running?")
            
        self.assertEqual(response.status_code, 200)
        self.assertIn("application/json", response.headers.get("Content-Type", ""))
        
        data = response.json()
        self.assertIn("tweets", data, "JSON response should contain 'tweets' key")
        self.assertIsInstance(data["tweets"], list)
        
        if len(data["tweets"]) > 0:
            tweet = data["tweets"][0]
            expected_keys = ["id", "text", "author", "created_at"]
            for key in expected_keys:
                self.assertIn(key, tweet, f"Tweet object should contain '{key}' key")

        self.assertIn("pagination", data, "JSON response should contain 'pagination' key")
        self.assertIn("meta", data, "JSON response should contain 'meta' key")

    def test_home_feed_html_by_default(self):
        """Verify GET / returns HTML by default (no Accept header)."""
        response = requests.get(f"{BASE_URL}/", timeout=5)
        self.assertEqual(response.status_code, 200)
        self.assertIn("text/html", response.headers.get("Content-Type", ""))
        self.assertIn("<html", response.text.lower())

if __name__ == "__main__":
    unittest.main()
