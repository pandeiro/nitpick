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
        # 1. Clear state
        self.open_nitter(".following/clear")
        self.open_nitter(".feed/clear")

        # 2. Follow jack
        self.open_nitter("jack")
        self.click(".follow-btn")
        
        # 3. Open home page
        self.open_nitter()
        
        # 4. Verify header is present and contains "followed users"
        self.assert_element(".feed-header")
        self.assert_text("followed users", ".feed-header")

    def test_feed_infinite_scroll(self):
        """
        Verifies that infinite scroll is working if enabled in preferences.
        """
        # 1. Clear state
        self.open_nitter(".following/clear")
        self.open_nitter(".feed/clear")

        # 2. Enable infinite scroll
        self.open_nitter("settings")
        if not self.is_checked('input[name="infiniteScroll"]'):
            self.click('label[title="infiniteScroll"]')
        self.click('button[type="submit"]')
        
        # 3. Follow multiple users
        users = ["jack", "elonmusk", "nim_lang"]
        for user in users:
            self.open_nitter(user)
            self.click(".follow-btn")

        # 4. Go to home page
        self.open_nitter()
        
        # 5. Verify script is loaded
        self.assert_element_present('script[src="/js/infiniteScroll.js"]')
        
        # 6. Scroll to bottom
        self.scroll_to_bottom()
        self.assert_element(".timeline")

    def test_feed_visibility_on_home(self):
        """
        Verifies that the feed is visible on the Home Page if users are followed.
        """
        # 1. Unfollow everyone (clear state)
        self.open_nitter(".feed/clear")
        self.open_nitter(".following/clear")
        
        # 2. Go to home page - should see search bar
        self.open_nitter()
        self.assert_element(".search-bar")
        self.assert_element_absent(".timeline")
        
        # 3. Follow a user
        self.open_nitter("jack")
        if self.is_element_visible(".follow-btn"):
            self.click(".follow-btn")
            
        # 4. Go to home page - should see feed
        self.open_nitter()
        self.assert_element(".timeline")
        self.assert_element(".feed-header")
        self.assert_element_absent(".panel-container .search-bar")
