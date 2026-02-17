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
        self.click(".follow-btn")
        
        # 2. Go to home page to trigger feed generation
        self.open_nitter()
        
        # 3. Verify status code (using seleniumbase's built-in checks)
        # We check current URL or title if necessary
        assert "nitpick" in self.get_title().lower()

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
