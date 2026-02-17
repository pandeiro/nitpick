from base import BaseTestCase, Tweet, get_timeline_tweet

class PinnedTweetTest(BaseTestCase):
    def test_pin_unpin_flow(self):
        # 1. Open a user profile and find a tweet
        username = 'jack'
        tweet_id = '20'
        self.open_nitter(f'{username}/status/{tweet_id}')
        
        # Verify it's the right tweet
        tweet = Tweet('.main-tweet ')
        self.assert_text('just setting up my twttr', tweet.text)
        
        # 2. Pin the tweet
        # The pin button has class 'pin-btn'
        self.click('.pin-btn')
        
        # 3. Go to /pinned and verify it's there
        self.open_nitter('pinned')
        self.assert_text('Pinned Tweets', 'h2')
        # In /pinned, it should be in the timeline
        pinned_tweet = get_timeline_tweet(1)
        self.assert_text('just setting up my twttr', pinned_tweet.text)
        
        # 4. Unpin it
        # The button in /pinned should now be 'pinned' class and title 'Unpin'
        self.click('.pin-btn.pinned')
        
        # 5. Verify it's gone from /pinned
        self.assert_text('No pinned tweets yet.', '.timeline-header p')
