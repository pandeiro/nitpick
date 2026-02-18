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

    def test_feed_infinite_scroll(self):
        """
        Verifies that infinite scroll is working if enabled in preferences.
        """
        # 1. Enable infinite scroll
        self.open_nitter("settings")
        if not self.is_checked('input[name="infiniteScroll"]'):
            self.click('label[title="infiniteScroll"]')
        self.click('button[type="submit"]')
        
        # 2. Follow multiple users
        users = ["jack", "elonmusk", "nim_lang"]
        for user in users:
            self.open_nitter(user)
            if self.is_element_visible(".follow-btn"):
                self.click(".follow-btn")

        # 3. Go to home page
        self.open_nitter()
        
        # 4. Verify script is loaded
        self.assert_element_present('script[src="/js/infiniteScroll.js"]')
        
        # 5. Scroll to bottom
        self.scroll_to_bottom()
        # The test passes if no error occurs during scrolling
        # and the page still has tweets
        self.assert_element(".timeline")
