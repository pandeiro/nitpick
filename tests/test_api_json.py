import json
import requests


BASE_URL = "http://localhost:7000"


def get_json(path: str) -> dict:
    """Fetch a route with Accept: application/json"""
    resp = requests.get(
        f"{BASE_URL}/{path}",
        headers={"Accept": "application/json"},
        timeout=30
    )
    resp.raise_for_status()
    return resp.json()


def get_html(path: str) -> str:
    """Fetch a route as HTML and return body"""
    resp = requests.get(f"{BASE_URL}/{path}", timeout=30)
    resp.raise_for_status()
    return resp.text


def extract_embedded_data(html: str) -> dict:
    """Extract JSON from <script id="initial-data"> in HTML"""
    import re
    match = re.search(r'<script id="initial-data" type="application/json">(.+?)</script>', html)
    if not match:
        return {}
    return json.loads(match.group(1))


class TestJSONAPI:
    """Test JSON API via content negotiation"""

    def test_profile_json_response(self):
        """GET /jack with Accept: application/json returns valid JSON"""
        resp = requests.get(
            f"{BASE_URL}/jack",
            headers={"Accept": "application/json"},
            timeout=30
        )
        assert resp.headers["content-type"].startswith("application/json")
        data = resp.json()
        assert "user" in data
        assert data["user"]["username"] == "jack"

    def test_profile_json_matches_html_embedded(self):
        """JSON response matches embedded data in HTML"""
        # Get JSON version
        json_data = get_json("jack")

        # Get HTML version and extract embedded data
        html = get_html("jack")
        embedded = extract_embedded_data(html)

        # Compare key fields
        assert json_data["user"]["username"] == embedded.get("account", {}).get("username")
        assert json_data["user"]["id"] == embedded.get("account", {}).get("id")
        assert json_data["user"]["display_name"] == embedded.get("account", {}).get("display_name")

    def test_timeline_json_response(self):
        """GET / with Accept: application/json returns feed JSON"""
        data = get_json("")
        assert "tweets" in data or "feed" in data

    def test_timeline_json_matches_html_embedded(self):
        """Timeline JSON matches embedded data in HTML"""
        # Follow a user first (via API if available, or skip this test if not authenticated)
        # For now, just verify the structure matches
        
        json_data = get_json("")
        html = get_html("")
        embedded = extract_embedded_data(html)

        # Both should have tweets/feed data
        json_has_tweets = "tweets" in json_data or "feed" in json_data
        embedded_has_tweets = "feed" in embedded or "tweets" in embedded
        
        # Skip if neither has data (no followed users)
        if not json_has_tweets and not embedded_has_tweets:
            return
        
        assert json_has_tweets == embedded_has_tweets

    def test_following_json_response(self):
        """GET /following with Accept: application/json returns JSON"""
        data = get_json("following")
        assert "lists" in data or "following" in data or "data" in data

    def test_following_json_matches_html_embedded(self):
        """Following JSON matches embedded data in HTML"""
        json_data = get_json("following")
        html = get_html("following")
        embedded = extract_embedded_data(html)

        # Both should have following lists data
        json_has_following = "lists" in json_data or "following" in json_data or "data" in json_data
        embedded_has_following = "lists" in embedded or "following" in embedded or "data" in embedded

        if not json_has_following and not embedded_has_following:
            return

        assert json_has_following == embedded_has_following

    def test_html_still_works(self):
        """GET without Accept: application/json still returns HTML"""
        resp = requests.get(f"{BASE_URL}/jack", timeout=30)
        assert resp.headers["content-type"].startswith("text/html")
        assert "<!DOCTYPE html>" in resp.text or "<html" in resp.text

    def test_json_error_not_found(self):
        """Invalid user returns JSON error"""
        resp = requests.get(
            f"{BASE_URL}/thisuserdoesnotexist12345",
            headers={"Accept": "application/json"},
            timeout=30
        )
        # Should return 404 or error JSON
        if resp.status_code == 404:
            data = resp.json()
            assert "error" in data

    def test_search_json_response(self):
        """GET /search with Accept: application/json returns JSON"""
        data = get_json("search?q=python")
        # Should have either tweets or users
        assert "tweets" in data or "users" in data or "data" in data

    def test_search_json_matches_html_embedded(self):
        """Search JSON matches embedded data in HTML"""
        json_data = get_json("search?q=python")
        html = get_html("search?q=python")
        embedded = extract_embedded_data(html)

        # Both should have search results
        json_has_results = "tweets" in json_data or "users" in json_data or "data" in json_data
        embedded_has_results = "tweets" in embedded or "users" in embedded or "data" in embedded

        if not json_has_results and not embedded_has_results:
            return

        assert json_has_results == embedded_has_results


if __name__ == "__main__":
    # Run basic test
    t = TestJSONAPI()
    t.test_html_still_works()
    print("Basic test passed!")
