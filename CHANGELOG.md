# Changelog

## [2026-06-13] — Single-session feed refresher resilience

### Problem

Production deployment at `https://twitter.ottertime.com` appeared to stop updating. The home feed showed tweets that were 2–3 hours old, and the `lastUpdated` timestamp in the feed cache was stale.

### Investigation

1. **Confirmed deployment was current**: Container was 2 hours old, running the latest `main` commit (`ea1f4a7`). GitHub Actions showed build and deploy completed successfully at `05:04 UTC`.

2. **Checked Redis cache state**: The `nitpick:feed:global` key existed with TTL ~3500s, but `nitpick:feed:global:tweetIds` (a separate list key) had length 0. The feed was stored as a compressed `GlobalFeed` blob, but the per-list tweet ID lists were empty. This was a red herring — the actual tweet IDs were inside the blob.

3. **Inspected session pool health**: `/.health` endpoint revealed only **1 session** in the pool (`_pandeiro`). The `limited` count was 0, but the `requests` counter showed 251 requests on `UserWithProfileTweetsQueryV2` over 2 hours.

4. **Read Docker logs**: The logs were filled with two repeating patterns:
   - `[sessions] no sessions available for API: ...UserWithProfileTweetsQueryV2`
   - `[feed-refresher] Fetch failed for '<user>' (1/3): no sessions available`
   - `[feed-refresher] Skipping '<user>' for ~10 cycles (3 failures)`

5. **Identified the root cause**: The `getSession` proc in `src/auth.nim` does **not queue**. When a batch of 5 futures tries to acquire a session, the first 3 succeed (`pending` becomes 0→1→2→3, and `maxConcurrentReqs = 2` means `pending > 2` is the cutoff). The 4th and 5th futures see `pending = 3 > 2` and immediately raise `NoSessionsError`. The `skipCounters` in `src/feed.nim` then marks these users as "failed." After 3 consecutive cycles, they are skipped for 10 cycles. The skip counters were **misdiagnosing a concurrency bottleneck as a user failure**.

6. **Verified rate limit was not exhausted**: Only 251 requests on `UserWithProfileTweetsQueryV2` over 2 hours. The endpoint limit is ~500 per 15-minute window. The problem was not rate limits — it was the batch size (5) exceeding the single session's concurrency capacity (3).

### Root cause

- **RFC assumption violated**: The RFC assumed 4+ sessions in the pool. With 1 session, batch size 5 creates a 40% failure rate.
- **No queueing**: `getSession` raises immediately instead of waiting for the session to become available.
- **15-minute interval too conservative**: With 1 session, a full cycle takes ~1–2 minutes. Waiting 15 minutes between cycles leaves the feed stale for no reason.

### Fix

| File | Change | Rationale |
|---|---|---|
| `src/feed.nim` | `refreshBatchSize` 5 → 3 | Matches single-session concurrency capacity (`maxConcurrentReqs = 2` allows 3 concurrent requests) |
| `src/auth.nim` | `getSession` now retries with `500ms` sleep up to `60s` timeout | Requests serialize into a queue instead of failing with `NoSessionsError` |
| `src/config.nim` | `feedRefreshMinutes` default 15 → 5 | 318 requests per 15-minute window is 64% of the 500 limit, leaving 36% headroom for user-facing traffic |
| `nitter.example.conf` | Documented `feedRefreshMinutes = 5` | Makes the default visible in the example config |

### Verification

- `nim check src/nitter.nim` ✅ SuccessX
- `nimble build -d:release` ✅ Binary built successfully
