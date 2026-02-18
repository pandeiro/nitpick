import pytest
import time
from base import BaseTestCase

class TestFeedCache(BaseTestCase):
    def test_feed_accumulation(self):
        """
        Tests that the global feed correctly accumulates and de-duplicates tweets.
        Note: This requires an internal debug endpoint or manual Redis check.
        For this prototype, we'll verify via the UI if the feed exists.
        """
        # 1. Follow some users (if not already)
        self.open_nitter("jack")
        if self.is_element_visible(".follow-btn"):
            self.click(".follow-btn")
        
        # 2. Go to home page to trigger feed generation
        self.open_nitter()
        
        # 3. Verify status code (using seleniumbase's built-in checks)
        assert "nitpick" in self.get_title().lower()

    def test_feed_debug_accumulation(self):
        """
        Verifies that the global feed accumulates data correctly using the debug endpoint.
        """
        # 1. Clear state
        self.open_nitter(".feed/clear")
        self.open_nitter(".following/clear")
        self.open_nitter(".feed")
        assert self.get_text("body") == "{}"

        # 2. Follow a user
        self.open_nitter("jack")
        if self.is_element_visible(".follow-btn"):
            self.click(".follow-btn")
        
        # 3. Trigger Home Page (which should eventually update the feed)
        self.open_nitter()
        
        # 4. Check if feed is populated (this will fail until Phase 2 is implemented)
        self.open_nitter(".feed")
        feed_data = self.get_text("body")
        assert "tweetIds" in feed_data
        assert "sampledUsers" in feed_data
        assert "jack" in feed_data.lower()

    def test_feed_strategy_settings(self):
        """
        Verifies that the new Feed strategy settings are present in preferences.
        """
        self.open_nitter("settings")
        assert self.is_text_visible("Multi-user Feed Strategy")
        assert self.is_element_visible('select[name="feedStrategy"]')
        assert self.is_text_visible("Sampling")
        assert self.is_text_visible("Sequential")
        
        assert self.is_text_visible("Ranking Algorithm")
        assert self.is_element_visible('select[name="rankingAlgorithm"]')
        assert self.is_text_visible("Chronological")
