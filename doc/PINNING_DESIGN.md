# Pinned Tweets Design Document

## Overview

This document describes the design and implementation of the `/pinned` feature, which allows users to pin tweets to a personal collection for quick access. Pinned tweets are stored in Redis with full tweet data serialization for fast retrieval.

## Motivation

Users want to save interesting tweets for later viewing without relying on Twitter's native bookmarking system. By storing tweets locally in Redis, we can:
- Provide instant access to pinned content
- Display tweets even if they're later deleted from Twitter
- Maintain a personalized collection independent of Twitter's infrastructure

## Architecture

### Data Storage

**Redis Schema:**
- **Set:** `pinned:ids` - Stores all pinned tweet IDs (strings)
- **String keys:** `pinned:{tweetId}` - Stores serialized tweet data with expiry

**Serialization:**
- Tweets are serialized using `flatty` (Nim serialization library)
- Compressed using `supersnappy` for efficient storage
- 30-day TTL (time-to-live) on individual tweet keys to prevent unbounded growth

**Idempotency:**
- Pinning an already-pinned tweet is a no-op
- The operation always succeeds, ensuring idempotent behavior

### Route Structure

**Primary Route:** `GET /pinned`
- Displays all pinned tweets in chronological order (newest first)
- Tweet data fetched from Redis (no API calls)
- Each tweet shows a "filled" pin icon indicating pinned status

**Action Routes:**
- `POST /pin` - Pins a tweet (requires `tweetId` parameter)
- `POST /unpin` - Unpins a tweet (requires `tweetId` parameter)

Both action routes redirect back to the referring page using `refPath()`.

### UI Design

**On Tweet Cards:**
- Pin icon appears in the tweet stats bar (after views)
- Unpinned state: Grey pin icon (`class="pin-btn"`)
- Pinned state: Accent-colored pin icon (`class="pin-btn pinned"`)
- Clicking toggles the pin state via POST form submission

**On /pinned Page:**
- Timeline-style layout similar to user profiles
- Header with "Pinned Tweets" title
- Empty state message when no pins exist
- Each tweet shows filled pin icon; clicking unpins it

### Implementation Files

**New Files:**
1. `src/routes/pinned.nim` - Route handlers
2. `src/views/pinned.nim` - View rendering
3. `doc/PINNING_DESIGN.md` - This document

**Modified Files:**
1. `src/redis_cache.nim` - Add pinned tweet storage functions
2. `src/views/tweet.nim` - Add pin icon to tweet stats
3. `src/nitter.nim` - Import and register pinned router
4. `src/routes/timeline.nim` - Add "pinned" to exclusion list
5. `src/sass/tweet/_base.scss` - Add pin button styling
6. `src/routes/status.nim` - Check pin status for conversation tweets

## Technical Details

### Redis Operations

```nim
# Check if tweet is pinned
proc isPinned(tweetId: int64): Future[bool]

# Pin a tweet (idempotent)
proc pinTweet(tweet: Tweet): Future[bool]
# - Adds ID to pinned:ids set
# - Serializes and stores tweet data with 30-day TTL

# Unpin a tweet
proc unpinTweet(tweetId: int64): Future[bool]
# - Removes ID from pinned:ids set
# - Deletes tweet data key

# Get all pinned tweets (sorted newest first)
proc getPinnedTweets(): Future[seq[Tweet]]
# - Fetches all IDs from pinned:ids set
# - Retrieves each tweet from Redis
# - Deserializes and sorts by time descending
```

### Rendering Flow

**For /pinned route:**
1. Call `getPinnedTweets()` to fetch all pinned tweets from Redis
2. Sort by `tweet.time` descending (newest first)
3. Render each tweet with `showPinned=true` flag
4. Tweet cards display filled pin icon with POST form to `/unpin`

**For regular tweet display:**
1. When rendering a tweet, call `isPinned(tweet.id)`
2. Pass `isPinned` flag to `renderTweet()`
3. RenderStats shows appropriate pin icon state
4. Form POSTs to `/pin` or `/unpin` based on current state

### Styling

**Pin Button (SCSS):**
```scss
.pin-btn {
  color: var(--grey);
  background: none;
  border: none;
  cursor: pointer;
  padding: 0;
  font-size: 14px;
  
  &.pinned {
    color: var(--accent);
  }
  
  &:hover {
    color: var(--accent);
  }
}
```

The pin button uses the existing Fontello `icon-pin` icon. State is indicated by color:
- Grey: Not pinned (can pin)
- Accent color: Pinned (can unpin)

### Route Precedence

Like `/search` and `/following`, the `/pinned` route must take precedence over the user profile route (`/@name`). This is achieved by:

1. Registering the pinned router before the timeline router in `nitter.nim`
2. Adding "pinned" to the exclusion list in timeline.nim's `/@name` route:
   ```nim
   cond @"name" notin ["pic", "gif", "video", "search", "settings", "login", "intent", "i", "following", "pinned"]
   ```

## Edge Cases

1. **Pinning already-pinned tweet:** No-op, returns success
2. **Unpinning non-existent tweet:** No-op, returns success
3. **Expired tweet data:** Tweet ID remains in set but data is missing; gracefully skipped during fetch
4. **Redis unavailable:** Operations fail gracefully, user sees unpinned state
5. **Deleted tweets:** Pinned copy remains accessible via /pinned even if deleted from Twitter

## Future Enhancements

Potential improvements for future iterations:
- Per-user pinning (currently global)
- Pin notes/annotations
- Pin categories/tags
- Export pinned tweets
- Import from Twitter bookmarks
- Bulk unpin operations

## Dependencies

- `flatty` - Nim object serialization
- `supersnappy` - Compression for tweet data
- `redis` - Redis client
- `redpool` - Redis connection pooling

## Testing Considerations

1. Verify pin/unpin operations update Redis correctly
2. Verify /pinned page shows tweets in correct order
3. Verify pin icon state changes on tweet cards
4. Verify route precedence (/pinned vs user profile)
5. Verify expired tweets are handled gracefully
6. Test with large numbers of pinned tweets

## Security Considerations

- No authentication required (same as following feature)
- All users share the same pinned list (global)
- No rate limiting on pin operations (could be added)
- Tweet data stored unencrypted in Redis
