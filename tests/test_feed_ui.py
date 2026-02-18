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
