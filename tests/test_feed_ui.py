from base import BaseTestCase

class TestFeedUI(BaseTestCase):
    def test_following_link_in_navbar(self):
        """
        Verifies that the 'Following' link is present in the global navbar.
        """
        self.open_nitter()
        # Find by title because we have two search icons for now
        self.assert_element('a[title="Following"]')
        self.click('a[title="Following"]')
        self.assert_text("Following", "h2")

    def test_feed_header_statistics(self):
        """
        Verifies that the feed header shows statistics (X/Y followed users).
        """
        # Follow jack
        self.open_nitter("jack")
        if self.is_element_visible(".follow-btn"):
            self.click(".follow-btn")
        
        # Open home page
        self.open_nitter()
        
        # Verify header is present and contains "followed users"
        # We expect this to fail initially
        self.assert_element(".feed-header")
        self.assert_text("followed users", ".feed-header")
