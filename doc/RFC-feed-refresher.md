# RFC: Feed Background Refresher

**Status:** Draft  
**Date:** 2026-06-12  
**Author:** Feed Study Team  
**Drivers:** 2.5% search coverage, 40x gap vs individual timelines (see `docs/feed-study.md`)

---

## Problem

The current chronological feed (`src/feed.nim`) uses Twitter's GraphQL
SearchTimeline endpoint to collect tweets from followed users. This approach
is fundamentally broken for feed consumption:

1. **2.5% coverage** — of the 1,969 tweets available across 103 users'
   individual timelines, the search endpoint returned only 50.
2. **Different result sets** — search returns different tweets than the
   timeline endpoint. Tweet ID overlap averages just 11%.
3. **Severely rate-limited** — SearchTimeline has an observed limit of ~50
   requests per 15 minutes per session, and each feed request consumes 2
   (one per 15-user chunk).
4. **20-result cap** — each search query returns at most 20 tweets,
   regardless of how many users are in the query.

The existing Redis accumulation layer (`updateListFeed`, `getListFeed`,
`getListMembers`) is already built for incremental feed building. The gap
is in the data source: we're using the wrong endpoint.

## Proposed Solution

Replace the search-based fetches with a **background worker** that
periodically fetches individual user timelines via
`UserWithProfileTweetsV2` and accumulates results into Redis.

### Architecture

```
┌─────────────────────────────────────┐
│          Background Loop             │
│  (ticks every REFRESH_INTERVAL)      │
│                                      │
│  for each follow list:               │
│    members = getListMembers(name)    │
│    for batch in chunks(members, 5):  │
│      par f in batch:                 │
│        id = getUserId(f)  [cached]   │
│        tl = getGraphUserTweets(id)   │
│      updateListFeed(name, tl_tweets) │
└──────────────────┬──────────────────┘
                   │ tweets accumulated
                   ▼
┌──────────────────────────────────────┐
│         Redis (accumulation layer)    │
│                                      │
│  nitpick:feed:list:<name>            │
│    ├─ tweetIds[]       (capped 1000) │
│    ├─ searchPool[]     (not needed)  │
│    └─ lastUpdated      (timestamp)   │
│                                      │
│  t:<id>  (individual tweet cache)    │
│  p:<user>  (user profile cache)      │
└──────────────────┬───────────────────┘
                   │ pure Redis read
                   ▼
┌──────────────────────────────────────┐
│       HTTP Handler (GET /)           │
│                                      │
│  getListFeed(listName) → Timeline    │
│  getCachedTweets(tweetIds) → tweets  │
│  renderMain(...) → HTML              │
│                                      │
│  No Twitter API calls during request │
└──────────────────────────────────────┘
```

### Key Changes

| Component | Current | Proposed |
|-----------|---------|----------|
| Feed data source | SearchTimeline (2 queries × 15 users) | UserWithProfileTweetsV2 (N queries × 1 user each) |
| Fetch timing | On page load (synchronous) | Background loop (asynchronous, periodic) |
| HTTP handler | Makes Twitter API calls + accumulates | Pure Redis read |
| Search pool | `SearchPoolEntry[]` with cursors | Not needed; replace with iteration state |
| Cursor pagination | Multi-cursor per chunk | Not needed; each user timeline is self-contained |
| `updateListFeed()` | Called after search accumulation | Called after each batch of timeline fetches |
| Rate limit impact | Spikes on page load | Smooth, predictable consumption |

### Rate Limit Analysis

Measured per session per 15-minute window (`docs/feed-study.md`):

| Endpoint | Limit | Cost per full refresh | Headroom |
|---|---|---|---|
| `UserByScreenName` | ~150 | ~106 (first time; cached after) | ~44 |
| `UserWithProfileTweetsV2` | ~500 | ~106 | ~394 |

**With 1 session:** Full refresh of 106 users every 15 minutes consumes
~106 of 500 available timeline requests — 21% utilization. The remaining
394 requests provide headroom for shorter intervals or additional lists.

**With N sessions:** Capacity scales linearly. Each additional session adds
~500 timeline requests per 15 minutes. 3 sessions could refresh 106 users
in parallel within 1-2 minutes.

**First refresh is the most expensive:** UserByScreenName resolves
username→ID, consuming ~106 of 150 requests. After caching in Redis
(`cacheUserId`), subsequent refreshes skip this entirely and only hit
UserWithProfileTweetsV2.

## Implementation Plan

### Phase 1: Core Background Loop (in `src/feed.nim`)

Add a `startFeedRefresher` proc that runs on a timer:

```nim
proc startFeedRefresher*(interval: int) {.async.} =
  ## Background loop: periodically refetch all follow lists' feeds.
  ## Runs forever; call from nitter.nim after Redis init.
  while true:
    await sleepAsync(interval * 1000)
    let lists = await getListNames()
    for listName in lists:
      let members = await getListMembers(listName)
      if members.len == 0: continue
      var allTweets: seq[Tweet]
      # Process in small batches to avoid overwhelming the session pool
      for batch in members.distribute(5):
        var futures: seq[Future[Profile]]
        for user in batch:
          let userId = await getUserId(user)  # cached after first resolve
          if userId.len > 0 and userId != "suspended":
            futures.add getGraphUserTweets(userId, TimelineKind.tweets)
        for fut in futures:
          let profile = await fut
          for thread in profile.tweets.content:
            for t in thread:
              allTweets.add t
        # Accumulate after each batch to make progress incrementally
        if allTweets.len > 0:
          await cache(allTweets)
          let pool = @[]  # searchPool no longer needed
          await updateListFeed(listName, allTweets, pool)
          allTweets.setLen(0)
```

**File:** `src/feed.nim` [1](#ref-feed)

### Phase 2: Wire into Startup (in `src/nitter.nim`)

After Redis is initialized, start the background loop:

```nim
# In nitter.nim, after initRedisPool(cfg):
const feedRefreshInterval = 15 * 60  # 15 minutes
asyncCheck startFeedRefresher(feedRefreshInterval)
```

This runs as a background async task alongside the HTTP server. Jester's
asyncdispatch loop handles both.

**File:** `src/nitter.nim` [2](#ref-nitter)

### Phase 3: Simplify HTTP Handler (in `src/nitter.nim`)

The `before` filter's `/` handler currently calls `fetchFeed()` which
makes Twitter API calls. Replace it with a Redis read:

```nim
# In the before filter (and the GET / route):
let feedData = await getListFeed(listName)
if feedData.isSome:
  let f = feedData.get()
  let latestIds = if f.tweetIds.len > 50: f.tweetIds[0..<50] else: f.tweetIds
  let tweets = await getCachedTweets(latestIds)
  # ... render timeline from cached tweets
else:
  # Feed not yet populated; show empty state or trigger immediate refresh
```

**File:** `src/nitter.nim` [3](#ref-nitter)

### Phase 4: Remove Search Pool (in `src/types.nim` and `src/feed.nim`)

The `SearchPoolEntry` type and `searchPool` field on `GlobalFeed` become
unused. Remove them after the background worker is stable.

**Files:** `src/types.nim` [4](#ref-types), `src/redis_cache.nim` [5](#ref-cache)

### Phase 5: Configurable Refresh Interval (in `nitter.conf`)

Add a `feedRefreshMinutes` config option:

```ini
[Config]
feedRefreshMinutes = 15
```

**File:** `src/config.nim` [6](#ref-config)

## Migration Strategy

1. **Deploy Phase 1+2** — background worker starts alongside existing
   search-based feed. Both write to the same Redis keys via
   `updateListFeed()`. The HTTP handler still reads from Redis, so it gets
   accumulated results from whichever producer runs first.

2. **Deploy Phase 3** — HTTP handler stops making API calls. Feed becomes
   purely Redis-backed. The search-based code path (`fetchFeed()`) becomes
   dead code but can remain until Phase 4 cleanup.

3. **Monitor** — Watch session health (`/.health`), rate limit headroom
   (`/.sessions`), and feed freshness (tweet ages in responses).

4. **Deploy Phase 4+5** — cleanup and configuration.

## Rollback Plan

If the background worker causes issues:

1. **Restore the search-based path:** Revert Phase 3 changes to the HTTP
   handler. The `before` filter goes back to calling `fetchFeed()`.
2. **Keep the worker running or disable it:** Remove the `asyncCheck` call
   in nitter.nim.
3. The Redis keys are shared, so data accumulated by the worker is not lost
   — it supplements the search-based feed.

## Open Questions

1. **Refresh interval:** 15 minutes is conservative based on rate limit
   data. Should this be configurable per-list (active lists refresh more
   often)?

2. **Error handling:** If a user's timeline fetch fails repeatedly (e.g.,
   account suspended), how many consecutive failures before we skip them
   for N cycles?

3. **Session pool exhaustion:** With 1 session, batches of 5 parallel
   fetches are safe (`maxConcurrentReqs = 2` means 2 concurrent requests
   per session). With more sessions, can we increase batch size?

4. **Initial seed:** On first deploy, the feed cache is empty. Should we
   trigger an immediate refresh on startup, or wait for the first timer
   tick?

5. **Cache-before-accumulate race:** The worker fetches batches in
   sequence. If the HTTP handler reads Redis between batches, it gets a
   partial feed. Is this acceptable, or do we need an "updating" flag?

6. **Per-list scheduling:** Some lists (e.g., "LLM" with 28 users) may
   need more frequent refreshes than others. Should refresh interval be
   per-list?

## References

| # | File | Purpose |
|---|------|---------|
| 1 | `src/feed.nim` | Current search-based feed logic; target for worker |
| 2 | `src/nitter.nim` | Main entry point; wires up routes and startup |
| 3 | `src/nitter.nim` (before filter, GET / route) | HTTP handler that currently calls API |
| 4 | `src/types.nim` (`SearchPoolEntry`, `GlobalFeed`) | Types to eventually remove |
| 5 | `src/redis_cache.nim` (`getListFeed`, `updateListFeed`, `getListMembers`) | Accumulation layer — already built |
| 6 | `src/config.nim` | Configuration parsing |

### Key Existing Functions (no changes needed)

- `getListMembers(name)` — returns followed usernames for a list
- `getUserId(username)` — resolves username→ID (cached in Redis)
- `getGraphUserTweets(id, kind, cursor)` — fetches individual timeline
- `cache(tweets)` — caches tweets in Redis with 60-min TTL
- `updateListFeed(name, tweets, searchPool)` — accumulates into list feed
- `getListFeed(name)` — reads accumulated feed metadata
- `getCachedTweets(ids)` — batch reads tweets from cache
