from base import BaseTestCase, Tweet, get_timeline_tweet
import requests
import subprocess

class PinnedTweetTest(BaseTestCase):
    def test_pin_unpin_flow(self):
        # 1. Open a user profile
        username = 'jack'
        self.open_nitter(username)
        self.wait_for_element('.timeline-item')
        self.sleep(2)
        
        # Get the text of the first tweet to verify later
        first_tweet = get_timeline_tweet(1)
        tweet_text = self.get_text(first_tweet.text)
        # Clean up text for easier matching (strip etc)
        tweet_text_clean = tweet_text.strip()[:50]
        
        # Extract tweetId from the form
        tweet_id = self.get_attribute('.timeline > div:nth-child(1) .pin-form input[name="tweetId"]', 'value')
        print(f"DEBUG: Found tweetId {tweet_id}")
        
        # 2. Pin the tweet using curl directly
        print(f"DEBUG: Sending POST /pin via curl for {tweet_id}")
        cmd = [
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "-X", "POST", "http://localhost:7000/pin",
            "-d", f"tweetId={tweet_id}",
            "-d", f"referer=/{username}"
        ]
        http_code = subprocess.check_output(cmd).decode().strip()
        print(f"DEBUG: POST /pin curl response: {http_code}")
        
        # 3. Verify it's now on /pinned
        self.open_nitter('pinned')
        self.assert_text('Pinned Tweets', 'h2', timeout=10)
        
        # 4. In /pinned, it should be in the gallery
        self.assert_element('.pinned-gallery')
        # Check if our tweet text is present anywhere in the gallery
        self.assert_text(tweet_text_clean, '.pinned-gallery')
        
        # 5. Unpin it
        print(f"DEBUG: Sending POST /unpin via curl for {tweet_id}")
        cmd = [
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "-X", "POST", "http://localhost:7000/unpin",
            "-d", f"tweetId={tweet_id}",
            "-d", f"referer=/pinned"
        ]
        http_code = subprocess.check_output(cmd).decode().strip()
        print(f"DEBUG: POST /unpin curl response: {http_code}")
        
        # 6. Verify it's gone from /pinned
        self.open_nitter('pinned')
        # The text shouldn't be there anymore. 
        # If there are NO tweets, we see the "No pinned tweets yet" message
        # But if there are other pinned tweets from previous failed tests, it won't show that.
        # So we just check that our specific tweet is gone.
        self.assert_text_not_visible(tweet_text_clean, '.pinned-gallery')
