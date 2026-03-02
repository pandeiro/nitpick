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

        self.assertIn(
            "pagination", data, "JSON response should contain 'pagination' key"
        )
        self.assertIn("meta", data, "JSON response should contain 'meta' key")

    def test_home_feed_html_by_default(self):
        """Verify GET / returns HTML by default (no Accept header)."""
        response = requests.get(f"{BASE_URL}/", timeout=5)
        self.assertEqual(response.status_code, 200)
        self.assertIn("text/html", response.headers.get("Content-Type", ""))
        self.assertIn("<html", response.text.lower())

    def test_user_profile_json(self):
        """Verify GET /<username> with Accept: application/json returns expected JSON structure."""
        headers = {"Accept": "application/json"}
        response = requests.get(f"{BASE_URL}/jack", headers=headers, timeout=5)

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            "Content-Type should be application/json",
        )
        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data, "Error response should contain 'error' key")
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn("user", data, "Profile JSON should contain 'user' key")
        self.assertIn("username", data["user"], "User object should contain 'username'")
        self.assertEqual(data["user"]["username"], "test")

        self.assertIn("tweets", data, "Profile JSON should contain 'tweets' key")
        self.assertIn(
            "preferences", data, "Profile JSON should contain 'preferences' key"
        )

    def test_user_replies_json(self):
        """Verify GET /<username>/with_replies returns JSON."""
        headers = {"Accept": "application/json"}
        response = requests.get(
            f"{BASE_URL}/jack/with_replies", headers=headers, timeout=5
        )

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )
        data = response.json()
        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
        else:
            self.assertEqual(response.status_code, 200)
            self.assertIn("tweets", data)

    def test_search_json(self):
        """Verify GET /search returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.get(f"{BASE_URL}/search?q=test", headers=headers, timeout=5)

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn("tweets", data, "Search JSON should contain 'tweets' key")
        self.assertIn("users", data, "Search JSON should contain 'users' key")
        self.assertIn("pagination", data, "Search JSON should contain 'pagination' key")

    def test_following_lists_json(self):
        """Verify GET /following returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.get(f"{BASE_URL}/following", headers=headers, timeout=5)

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn("lists", data, "Following JSON should contain 'lists' key")

    def test_list_profile_json(self):
        """Verify GET /i/lists/<id> returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.get(
            f"{BASE_URL}/i/lists/123456", headers=headers, timeout=5
        )

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        if response.status_code == 404:
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn("list", data, "List profile JSON should contain 'list' key")

    def test_single_tweet_json(self):
        """Verify GET /<username>/status/<id> returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.get(
            f"{BASE_URL}/jack/status/1234567890", headers=headers, timeout=5
        )

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        if response.status_code == 404:
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn("tweet", data, "Single tweet JSON should contain 'tweet' key")

    def test_pinned_tweets_json(self):
        """Verify GET /pinned returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.get(f"{BASE_URL}/pinned", headers=headers, timeout=5)

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn(
            "pinned_tweets",
            data,
            "Pinned tweets JSON should contain 'pinned_tweets' key",
        )

    def test_user_lists_json(self):
        """Verify GET /<username>/lists returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.get(f"{BASE_URL}/jack/lists", headers=headers, timeout=5)

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn("lists", data, "User lists JSON should contain 'lists' key")
        self.assertIn("username", data, "User lists JSON should contain 'username' key")

    def test_follow_action_json(self):
        """Verify POST /follow returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.post(
            f"{BASE_URL}/follow",
            headers=headers,
            data={"username": "testuser"},
            timeout=5,
        )

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn(
            "success", data, "Follow action JSON should contain 'success' key"
        )

    def test_unfollow_action_json(self):
        """Verify POST /unfollow returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.post(
            f"{BASE_URL}/unfollow",
            headers=headers,
            data={"username": "testuser"},
            timeout=5,
        )

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn(
            "success", data, "Unfollow action JSON should contain 'success' key"
        )

    def test_pin_action_json(self):
        """Verify POST /pin returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.post(
            f"{BASE_URL}/pin",
            headers=headers,
            data={"tweetId": "1234567890"},
            timeout=5,
        )

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn("success", data, "Pin action JSON should contain 'success' key")

    def test_unpin_action_json(self):
        """Verify POST /unpin returns JSON when Accept: application/json is sent."""
        headers = {"Accept": "application/json"}
        response = requests.post(
            f"{BASE_URL}/unpin",
            headers=headers,
            data={"tweetId": "1234567890"},
            timeout=5,
        )

        self.assertIn(
            "application/json",
            response.headers.get("Content-Type", ""),
            f"Expected application/json but got {response.headers.get('Content-Type')}",
        )

        data = response.json()

        if response.status_code == 429:
            self.assertIn("error", data)
            self.assertEqual(data["error"]["code"], "RATE_LIMITED")
            return

        self.assertEqual(response.status_code, 200)
        self.assertIn("success", data, "Unpin action JSON should contain 'success' key")


if __name__ == "__main__":
    unittest.main()
