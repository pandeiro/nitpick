import pytest
from base import BaseTestCase

class TestFeedLogic(BaseTestCase):
    def test_fetch_global_feed(self):
        """
        Verifies that fetchGlobalFeed correctly samples users and returns tweets.
        """
        # 1. Clear state
        self.open_nitter(".feed/clear")
        self.open_nitter(".following/clear")

        # 2. Follow multiple users
        users = ["jack", "elonmusk", "nim_lang"]
        for user in users:
            self.open_nitter(user)
            if self.is_element_visible(".follow-btn"):
                self.click(".follow-btn")
        
        # 3. Open Home Page
        self.open_nitter()
        
        # 4. Check debug endpoint
        self.open_nitter(".feed")
        feed_data = self.get_text("body").lower()
        assert "tweetids" in feed_data
        assert "sampledusers" in feed_data
        # At least one of the followed users should be in the sampled list
        assert any(user in feed_data for user in users)
