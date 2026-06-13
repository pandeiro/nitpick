# RFC: Feed Refresher v3 — Visibility, Control, and Smarter Scheduling

**Status:** Draft  
**Date:** 2026-06-12  
**Authors:** Murph McMahon (conversation with coding agent)

---

## Motivation

The v2 feed refresher (PR #2) replaced the broken search-based feed with a background worker that fetches individual user timelines and serves them from Redis. This eliminated Twitter API calls from page loads and achieved full coverage of followed users.

However, the v2 implementation is a blind black box:

- **No cycle metrics** — we don't know how long a refresh takes, how many tweets are new, or how many errors occurred
- **No rate limit visibility** — we can't see remaining budget per session or predict when we'll hit a wall
- **No user control** — the refresh interval is a static config knob; there's no way to trigger a refresh on demand
- **No scheduling intelligence** — all users are fetched in a burst at the start of each interval, then the feed goes stale
- **No per-list tuning** — different following lists with different sizes and activity levels all share the same cadence

This RFC scopes the next iteration: adding visibility, user control, and the foundation for adaptive scheduling.

---

## Design Goals

1. **Visibility**: Expose worker health, cycle metrics, and rate limit status via a debug endpoint
2. **Control**: Allow users to force a refresh on demand
3. **Freshness**: Transition from burst refresh to rolling/staggered refresh
4. **Safety**: Stay within rate limits; make limits visible rather than mysterious
5. **Foundation**: Record enough data to later enable activity-based prioritization and per-list tuning

---

## Proposed Changes

### Phase 1: Worker Metrics & Status Endpoint

Record per-cycle metrics and expose them via a `GET /feed/status` endpoint.

**In-memory metrics** (reset on restart, no Redis writes for hot path):

```nim
type
  CycleMetrics* = object
    startTime: float        # epoch seconds
    duration: float         # seconds
    usersFetched: int
    tweetsFetched: int
    tweetsNew: int          # after dedup against current feed
    errors: int
    rateLimitsHit: int
    listsRefreshed: seq[string]

var
  currentCycle*: Option[CycleMetrics]    # in-progress cycle
  lastCycle*: Option[CycleMetrics]       # most recently completed
  cycleHistory*: seq[CycleMetrics]       # rolling window, capped at 20
```

**Status endpoint** (`GET /feed/status`):

```json
{
  "worker": "running",
  "cycle": {
    "current": {
      "elapsed_seconds": 12.4,
      "users_fetched": 40,
      "tweets_fetched": 312,
      "errors": 1,
      "lists": ["default"]
    },
    "last": {
      "duration_seconds": 47.2,
      "users_fetched": 106,
      "tweets_fetched": 891,
      "tweets_new": 312,
      "errors": 3,
      "rate_limits_hit": 0,
      "completed_at": "2026-06-13T04:50:34Z"
    }
  },
  "sessions": [
    {
      "remaining": 412,
      "limit": 500,
      "reset_in_seconds": 342,
      "status": "active"
    }
  ],
  "lists": [
    {
      "name": "default",
      "feed_age_seconds": 184,
      "tweet_ids_cached": 273,
      "members": 24
    }
  ]
}
```

**Redis-backed persistence** (optional, for historical analysis):
- `nitpick:feed:metrics:latest` — flatty-serialized `CycleMetrics` for last completed cycle
- `nitpick:feed:metrics:history` — capped list of recent cycles

### Phase 2: Force Refresh via API + UI

A mechanism to trigger an immediate worker cycle, bypassing the timer wait.

**API** (`POST /feed/refresh`):
- Sets a flag (`forceRefresh` in-memory, or `nitpick:feed:force-refresh` with 60s TTL in Redis)
- Worker checks flag at end of each cycle; if set, starts next cycle immediately instead of waiting
- Returns `{"status": "refresh_triggered"}`

**UI**:
- Add a "Refresh Now" button to the feed header (next to the list selector)
- Visible only when the user is on their home feed
- Show a spinner or "Refreshing..." state while the cycle runs
- Auto-reload the feed after the cycle completes (poll JSON endpoint or prompt user to reload)

**Jester route**:

```nim
post "/feed/refresh":
  let acceptJson = acceptJson()
  if acceptJson:
    triggerFeedRefresh()
    respJson %*{"status": "refresh_triggered"}
  else:
    resp Http405, "Only JSON supported"
```

**Worker integration** (`feed.nim`):

```nim
var forceRefresh* {.threadvar.}: bool

proc triggerFeedRefresh*() =
  forceRefresh = true

# In the main loop:
while true:
  await refreshAllLists(cfg)
  # Check for force-refresh flag
  if forceRefresh:
    forceRefresh = false
    # Don't wait, start next cycle immediately
    continue
  await sleepAsync(cfg.feedRefreshMinutes * 60 * 1000)
```

### Phase 3: Staggered / Rolling Refresh

Instead of fetching all users in a burst and then sleeping for the full interval, spread fetches across the interval. This keeps the feed continuously fresh.

**Current burst model:**

```
[fetch all 106 users (~45s)] [sleep 15 min] [fetch all 106 users] ...
```

**Proposed rolling model:**

```
[fetch 5 users] [wait 40s] [fetch 5 users] [wait 40s] ... (repeat for 15 min)
```

**Implementation sketch** (`feed.nim`):

```nim
proc refreshListFeedRolling*(listName: string; cfg: Config) {.async.} =
  let members = await getListMembers(listName)
  if members.len == 0:
    return

  # Pre-fetch user IDs (cached by cacheUserId)
  var userIds: seq[string]
  for username in members:
    let id = await cacheUserId(username)
    if id.len > 0:
      userIds.add(id)

  # Calculate stagger timing
  let intervalPerBatch = (cfg.feedRefreshMinutes * 60 * 1000) div ((userIds.len + 4) div 5)
    # Divide the full interval evenly across all batches

  for batch in userIds.chunked(5):
    # Fetch batch
    var tweets: seq[Tweet]
    for userId in batch:
      try:
        let futureTweets = await fetchUserTimeline(userId)
        tweets.add futureTweets
      except:
        # handle error (skip counter, etc.)
        continue

    # Accumulate into Redis
    await updateListFeed(listName, tweets, cfg)

    # Wait for the staggered interval before next batch
    await sleepAsync(intervalPerBatch)
```

However, this is a significant change in behavior and has edge cases:
- **Server restart**: Mid-cycle state is lost (in-memory). Need to decide: start fresh or persist cursor in Redis.
- **List changes**: If a user is added mid-cycle, should they be picked up immediately or wait for next full cycle?
- **Force refresh**: A force refresh should reset the rolling cycle, not layer on top.

For these reasons, rolling refresh may be deferred to a later phase once the metrics and control surface are in place.

### Phase 4: Rate Limit Tracking (Foundation)

Track per-session rate limit consumption to inform scheduling and alerting.

**Current state**: `auth.nim` already parses `x-rate-limit-remaining` and `x-rate-limit-reset` headers from Twitter API responses. We can surface these values.

**Session-level tracking** (in-memory):

```nim
type
  SessionRateLimit* = object
    remaining: int
    limit: int
    resetAt: float  # epoch seconds
    lastUpdated: float

var sessionLimits*: seq[SessionRateLimit]
```

Updated after each API call. Exposed via `/feed/status`.

**Application**: Once we have per-session limits visible, we can:
- Warn when remaining drops below a threshold (e.g., 20%)
- Slow down / increase stagger interval when limits are tight
- Pause refreshes if all sessions are exhausted
- Resume when reset time arrives

### Phase 5: Activity-Based Prioritization (Future)

Track per-user tweet output per cycle to prioritize active users.

```nim
type
  UserActivity* = object
    username: string
    tweetsPerCycle: int
    lastFetched: float
    skipCount: int
```

Higher-tweeting users get fetched more frequently (e.g., every cycle); low-activity users get fetched every Nth cycle. This optimizes headroom usage.

---

## Rate Limit Budget

Current constraints (single session, `UserWithProfileTweetsV2`):

| Resource | Limit per 15 min |
|---|---|
| Timeline fetches | ~500 |
| User ID lookups | ~150 (first-time only, cached after) |

With 106 users and burst refresh:
- 106 timeline calls per cycle = 21% utilization
- 0 user ID lookups (cached after first cycle)

With 24 users (production):
- 24 timeline calls per cycle = 5% utilization
- Plenty of headroom for more aggressive refreshes

With rolling refresh, utilization is the same but spread evenly across the interval, avoiding a burst of calls.

**Hard limits to enforce:**
- Never exceed `remaining - 10` per session (safety margin)
- If all sessions have `remaining == 0`, skip cycle entirely
- Log a warning when remaining < 20%

---

## Open Questions

1. **In-memory vs Redis for metrics**: In-memory is simpler and avoids Redis write amplification on the hot path. But metrics are lost on restart. Should we persist the last completed cycle to Redis for continuity?

2. **Rolling refresh on restart**: If the server restarts mid-cycle, we lose in-progress state. Options: (a) start a fresh full cycle, (b) persist per-user cursor in Redis. (a) is simpler.

3. **Force refresh concurrency**: What if a force refresh is requested while a cycle is already running? Should it interrupt the current cycle or queue a second run? I'd recommend: if a cycle is running, the flag causes an immediate second cycle after the current one finishes (no extra wait). If no cycle is running, it starts one immediately.

4. **UI for Refresh Now**: Where should the button live? In the feed header next to the list selector? In a settings/status page? Both?

5. **Rate limit reset sync**: Twitter's rate limit window is per-endpoint with a specific reset time. Should we track this as a wall-clock target (e.g., "don't fetch until 14:32:00") or as a countdown ("wait 342 seconds")? Countdown is simpler but drifts if clocks are off.

---

## Implementation Plan

| Phase | Changes | Effort |
|-------|---------|--------|
| P1 | `CycleMetrics` type, in-memory tracking, `/feed/status` endpoint | Small |
| P2 | Force refresh flag, `POST /feed/refresh` route, UI button | Small |
| P3 | Rolling refresh logic, stagger timing | Medium |
| P4 | Rate limit surface in status, threshold warnings | Small |
| P5 | Activity tracking, per-user priority | Medium |

**Recommended start**: P1 + P2 together — they share the metrics infrastructure and give us immediate visibility and control. P3 (rolling refresh) can then be tuned based on real cycle timing data.

---

## Migration / Rollback

- All changes are additive — no existing behavior changes until P3 (rolling refresh)
- P3 can be toggled via a config flag (`staggeredRefresh: bool`)
- `GET /feed/status` and `POST /feed/refresh` are new endpoints with no backward compat concerns
- Force refresh works with both burst and rolling modes
