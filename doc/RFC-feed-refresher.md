# RFC: Feed Background Refresher (v2)

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
│    ├─ searchPool[]     (cleared)     │
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
| Search pool | `SearchPoolEntry[]` with cursors | Cleared on first worker write; removed entirely in cleanup |
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

## Decisions (Closed Questions from v1)

### Q1: Refresh interval — configurable, single value for v1

A single `feedRefreshMinutes` config key (default 15). Per-list intervals
are deferred. The config key is introduced in Phase 1 (not deferred to a
later phase) and wired into `Config` and `nitter.conf`.

### Q2: Error handling — concrete skip policy

| Condition | Action | Recovery |
|-----------|--------|----------|
| User suspended (`userId == "suspended"`) | Skip silently, no retry this cycle | Re-checked next cycle |
| Timeline fetch returns empty/error | Log warning, skip this user for this batch | Retried next cycle |
| 3 consecutive fetch failures for same user | Skip for 10 cycles (~150 min with 15 min interval), log warning | Retried after 10 cycles |
| Rate-limited mid-cycle | Abort remaining fetches, log error, resume next cycle | Normal retry next cycle |

Skip counters are not persisted to Redis for v1 — they're in-memory state
on the worker. This means a worker restart resets all counters. Acceptable
for v1; persistence can be added if needed.

### Q3: Batch size and concurrency

Batch size = 5 users per batch. With `maxConcurrentReqs = 2` per session
and (assumed) 4+ sessions in the pool, 5 parallel timeline fetches run
safely — the session pool internally queues excess requests when all
sessions are busy.

### Q4: Initial seed — immediate refresh on startup

The background loop fires one full refresh immediately on startup, then
enters the interval loop. This ensures the feed is populated within 1–2
minutes of startup, not 15.

### Q5: Partial feed reads during batch processing — accepted

The worker accumulates after each batch of 5 users. Between batches, the
HTTP handler may see an incomplete feed. This is acceptable:

- Any tweets are better than no tweets (the current state).
- The feed fills in over ~2 minutes on first run.
- Future work could add an `updating` flag, but not needed for v1.

### Q6: `searchPool` handling during migration

The worker calls `updateListFeed` with an empty searchPool. To prevent
the worker from clearing the searchPool that the search-based path is still
using during Phase 1+2 migration, `updateListFeed` is modified **not to
overwrite `searchPool` when the incoming value is empty**. Only when the
incoming `searchPool` is non-empty (or the search-based path is fully
removed in Phase 4) is the field updated.

Alternatively, in Phase 4 the `searchPool` field is removed from
`GlobalFeed` entirely. For v1, an empty incoming seq means "don't touch."

### Q7: Per-user pagination depth

Each user timeline fetch retrieves the **first page only** (~20 most
recent tweets via `getGraphUserTweets(id, TimelineKind.tweets)` with no
cursor). This is sufficient: each refresh cycle picks up whatever new
tweets the user has posted since the last cycle. Deeper pagination per
user is unnecessary for a feed that refreshes every 15 minutes.

## Implementation Plan

### Phase 1: `feedRefreshMinutes` config + optional searchPool guard

**Files:** `src/config.nim`, `src/types.nim` (Config), `nitter.conf`

Add `feedRefreshMinutes` to the `Config` object and config parser:

```nim
# In types.nim, Config object — add field:
feedRefreshMinutes*: int

# In config.nim — add parser line:
feedRefreshMinutes: cfg.get("Config", "feedRefreshMinutes", 15),
```

Update `updateListFeed` in `src/redis_cache.nim` to only overwrite
`searchPool` when the incoming value is non-empty:

```nim
proc updateListFeed*(name: string; newTweets: seq[Tweet];
                     searchPool: seq[SearchPoolEntry] = @[]) {.async.} =
  let existing = await getListFeed(name)
  var feed: GlobalFeed

  if existing.isSome:
    feed = existing.get()

  for t in newTweets:
    if t.id notin feed.tweetIds:
      feed.tweetIds.add t.id

  if feed.tweetIds.len > 0:
    feed.tweetIds.sort(SortOrder.Descending)
    if feed.tweetIds.len > 1000:
      feed.tweetIds.setLen(1000)

  # Guard: don't clear searchPool during migration — worker passes @[]
  if searchPool.len > 0:
    feed.searchPool = searchPool

  feed.lastUpdated = getTime().toUnix()
  await setEx(listFeedKey(name), 3600, compress(toFlatty(feed)))
```

**Verification checkpoint A:** `nim check src/nitter.nim` passes. Config
parses with default 15. `updateListFeed` still compiles with both old
callers (which pass a searchPool) and new callers (which omit it).

---

### Phase 2: Background Loop Proc

**File:** `src/feed.nim`

Add imports and the `startFeedRefresher` proc. Key design choices:

- Batch size = 5 (constant)
- Uses manual chunking via `countup` (not `distribute`) so each batch is
  at most 5 users, not N chunks of variable size.
- Uses the existing `extractTweets` helper for consistent Timeline→Tweet
  extraction.
- Each batch accumulates to Redis immediately (not after all batches) so
  progress is visible incrementally.
- Error handling per the policy above.

```nim
import sequtils  # already? if not, add

const refreshBatchSize = 5

proc chunked*[T](s: openArray[T]; chunkSize: int): seq[seq[T]] =
  ## Splits a sequence into fixed-size chunks. The last chunk may be smaller.
  result = @[]
  var i = 0
  while i < s.len:
    let endIdx = min(i + chunkSize, s.len)
    result.add @(s[i ..< endIdx])
    i += chunkSize

proc refreshListFeed*(listName: string) {.async.} =
  ## Fetch latest tweets for all members of a single list, accumulate to Redis.
  let members = await getListMembers(listName)
  if members.len == 0:
    info "[feed-refresher] List '", listName, "' has no members, skipping."
    return

  info "[feed-refresher] Refreshing list '", listName, "' (", members.len, " members)"

  for batch in members.chunked(refreshBatchSize):
    var futures: seq[Future[Profile]]

    for user in batch:
      let userId = await getUserId(user)  # cached after first resolve
      if userId.len == 0:
        warn "[feed-refresher] Empty userId for '", user, "', skipping."
        continue
      if userId == "suspended":
        debug "[feed-refresher] User '", user, "' is suspended, skipping."
        continue
      futures.add getGraphUserTweets(userId, TimelineKind.tweets)

    if futures.len == 0:
      continue

    var batchTweets: seq[Tweet]
    for fut in futures:
      try:
        let profile = await fut
        batchTweets.add profile.tweets.content.extractTweets()
      except CatchableError as e:
        warn "[feed-refresher] Failed to fetch timeline: ", e.msg

    if batchTweets.len > 0:
      await cache(batchTweets)
      await updateListFeed(listName, batchTweets)  # no searchPool param
      info "[feed-refresher] Accumulated ", batchTweets.len, " tweets for '", listName, "'"

proc startFeedRefresher*(intervalSeconds: int) {.async.} =
  ## Background loop: immediately refresh all lists, then repeat on a timer.
  ## Call from nitter.nim after Redis init.

  # Immediate seed — populate feed cache within seconds of startup
  info "[feed-refresher] Starting initial feed refresh..."
  let lists = await getListNames()
  for listName in lists:
    await refreshListFeed(listName)
  info "[feed-refresher] Initial refresh complete."

  # Periodic refreshes
  while true:
    await sleepAsync(intervalSeconds * 1000)
    info "[feed-refresher] Starting periodic refresh cycle..."
    let lists = await getListNames()
    for listName in lists:
      await refreshListFeed(listName)
    info "[feed-refresher] Periodic refresh complete."
```

**Verification checkpoint B:** `nim check src/feed.nim` passes. The
`chunked` helper is correct (test edge: empty array, array smaller than
chunk, exact multiple, non-multiple).

---

### Phase 3: Wire into Startup

**File:** `src/nitter.nim`

Add one line after `initRedisPool(cfg)`:

```nim
asyncCheck startFeedRefresher(cfg.feedRefreshMinutes * 60)
```

This runs the background loop on the same asyncdispatch event loop as
Jester. The immediate seed fires, then the timer takes over.

**Verification checkpoint C:** `nim check src/nitter.nim` passes. Start
the server and observe log output:

```
[feed-refresher] Starting initial feed refresh...
[feed-refresher] Refreshing list 'default' (N members)
[feed-refresher] Accumulated M tweets for 'default'
[feed-refresher] Initial refresh complete.
```

Confirm that `GET /` returns tweets (served from the search-based path)
while the worker is also writing to Redis. No crashes, no rate-limit
spikes.

---

### Phase 4: Simplify HTTP Handler — Pure Redis Reads

**File:** `src/nitter.nim` (the `before` filter and `get "/"` route)

Replace the `fetchFeed(...)` call with a pure Redis read:

```nim
  let feedData = await getListFeed(listName)
  if feedData.isSome:
    let f = feedData.get()
    let latestIds = if f.tweetIds.len > 50: f.tweetIds[0..<50] else: f.tweetIds
    let tweets = await getCachedTweets(latestIds)
    # Build Timeline from cached tweets
    var threads: seq[Tweets]
    for t in tweets:
      threads.add @[t]
    let timeline = Timeline(
      content: threads,
      beginning: true,
      bottom: "",
      sampledCount: f.tweetIds.len,
      followingCount: following.len,
      lastUpdated: f.lastUpdated
    )
    if acceptJson:
      respJson toJson(timeline)
    # ... render HTML as before, using `timeline`
  else:
    # Feed cache is empty (first deploy before worker runs)
    if acceptJson:
      respJson emptyTimelineJson()
    else:
      # Show empty state with a "Feed is being built" message
      resp renderMain(renderEmptyFeed(), request, cfg, prefs,
                      listName = listName, lists = lists)
```

Key details:

- The `fetchFeed` and `fetchGlobalFeed` procs become dead code but remain
  in the file until Phase 5 cleanup.
- No Twitter API calls happen during request handling.
- If the worker hasn't completed its first cycle yet, the user sees an
  empty feed state with a note (friendlier than a spinner that never
  resolves).

**Verification checkpoint D:** `nim check src/nitter.nim` passes. Start
server, wait for initial worker seed to finish, then load `GET /`:
- Tweets appear without any API calls being made during the request.
- `/.health` and `/.sessions` show zero active requests during page load.
- Response time drops from seconds to milliseconds (pure Redis read).

---

### Phase 5: Cleanup — Remove Search Pool

**Files:** `src/types.nim`, `src/redis_cache.nim`, `src/feed.nim`

1. **`src/types.nim`**: Remove `SearchPoolEntry` type. Remove `searchPool`
   field from `GlobalFeed`.
2. **`src/redis_cache.nim`**: Remove `searchPool` from `updateListFeed`
   signature entirely (no longer optional — just tweets). Remove
   `getGlobalFeedDebug`'s pool rendering.
3. **`src/feed.nim`**: Remove `fetchFeed` and `fetchGlobalFeed` (dead
   code). Remove `buildSearchQuery`. Remove `ChunkSize` and
   `TotalSampleSize` constants.

Also remove `globalFeedKey()` template and `getGlobalFeed` / `updateGlobalFeed`
if they are unused outside of the old search path (they may still be referenced
in other routes — check with `rg` before deleting).

**Verification checkpoint E:** `nim check src/nitter.nim` passes with
zero warnings about unused imports or types. Full end-to-end test:
- `GET /` returns feed.
- `GET /?list=LLM` returns per-list feed.
- `POST /follow` / `/unfollow` still work.
- `POST /lists/create` / `/lists/delete` still work.
- No references to `SearchPoolEntry` remain anywhere in `src/`.

---

## Migration Strategy

| Step | What | Risk |
|------|------|------|
| 1. Phase 1 (config + searchPool guard) | Deploy first. Zero behavioral change. | None |
| 2. Phase 2+3 (worker runs alongside old path) | Worker writes to Redis, old path also writes. HTTP handler still reads old path. | Low — both write same keys via `updateListFeed` |
| 3. Monitor for N cycles | Check logs for errors, rate limits, feed freshness. | — |
| 4. Phase 4 (HTTP handler reads Redis) | Flip the switch. Old path becomes dead code. | Medium — if worker fails, feed goes stale. Rollback = revert Phase 4. |
| 5. Monitor for N cycles | Confirm no regression. | — |
| 6. Phase 5 (cleanup) | Remove dead code and types. | Low |

## Rollback Plan

If the background worker causes issues:

1. **Phase 4 revert:** Restore the HTTP handler to call `fetchFeed()`.
   The old search-based path is still present (dead code in Phase 4,
   but not deleted until Phase 5).
2. **Disable worker:** Remove or comment out the `asyncCheck
   startFeedRefresher(...)` line in `nitter.nim`.
3. **Data preservation:** Redis keys written by the worker are still valid
   — they supplement the search-based feed on next page load.

## Error Handling Detail

The in-memory skip counter is managed via a closure inside
`startFeedRefresher`:

```nim
proc startFeedRefresher*(intervalSeconds: int) {.async.} =
  var skipCounters: Table[string, int]  # username → consecutive failures

  proc refreshListFeed(listName: string) {.async.} =
    let members = await getListMembers(listName)
    ...
    for user in batch:
      if skipCounters.getOrDefault(user, 0) >= 3:
        debug "[feed-refresher] Skipping '", user, "' (", skipCounters[user], " consecutive failures)"
        continue
      ...
      try:
        let profile = await fut
        batchTweets.add profile.tweets.content.extractTweets()
        skipCounters.del(user)  # success → reset counter
      except CatchableError as e:
        skipCounters[user] = skipCounters.getOrDefault(user, 0) + 1
        if skipCounters[user] >= 3:
          warn "[feed-refresher] Skipping '", user, "' for 10 cycles (", skipCounters[user], " failures)"
        else:
          warn "[feed-refresher] Fetch failed for '", user, "' (", skipCounters[user], "/3): ", e.msg
    ...

  # Immediate seed
  ...
  # Periodic loop
  while true:
    await sleepAsync(intervalSeconds * 1000)
    ...
    # Decay skip counters after each full cycle
    if skipCounters.len > 0:
      for user, count in skipCounters.mpairs:
        if count >= 3:
          skipCounters[user] = count - 1  # gradual decay toward re-check
```

After 10 cycles (150 minutes), a skipped user's counter decays to 0 and
they are re-checked. This is approximate but avoids persistent Redis keys.

## References

| # | File | Purpose |
|---|------|---------|
| 1 | `src/feed.nim` | Target for background worker proc |
| 2 | `src/nitter.nim` | Entry point; wire up startup and HTTP handler |
| 3 | `src/redis_cache.nim` | `updateListFeed` — searchPool guard |
| 4 | `src/types.nim` | Config type and GlobalFeed (to remove searchPool in Phase 5) |
| 5 | `src/config.nim` | `feedRefreshMinutes` parser |
| 6 | `nitter.conf` | Sample config with new key |

### Key Existing Functions (no changes needed)

- `getListMembers(name)` — returns followed usernames for a list
- `getUserId(username)` — resolves username→ID (cached in Redis)
- `getGraphUserTweets(id, kind, cursor)` — fetches individual timeline
- `cache(tweets)` — caches tweets in Redis with 60-min TTL
- `getListFeed(name)` — reads accumulated feed metadata
- `getCachedTweets(ids)` — batch reads tweets from cache
- `extractTweets(timeline)` — extracts `seq[Tweet]` from `Timeline.content`
