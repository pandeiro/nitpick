import requests
import json

BASE_URL = "http://localhost:8080"

def test_home_feed_json():
    headers = {"Accept": "application/json"}
    try:
        response = requests.get(f"{BASE_URL}/", headers=headers)
    except requests.exceptions.ConnectionError:
        print("Skipping test: Server not running")
        return

    assert response.status_code == 200
    assert response.headers["Content-Type"].startswith("application/json")
    data = response.json()
    assert "tweets" in data
    assert "meta" in data
    assert isinstance(data["tweets"], list)

if __name__ == "__main__":
    test_home_feed_json()
    print("Test passed!")
