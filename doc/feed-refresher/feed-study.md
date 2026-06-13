# Feed Freshness Study

Study undertaken 2026-06-12 to diagnose why the chronological feed returns
stale/sparse content and determine the best path forward.

**Status:** Complete. Decision documented in `doc/RFC-feed-refresher.md`.

---

## Problem

The chronological feed uses Twitter's GraphQL SearchTimeline endpoint with
queries like `(from:user1 OR from:user2 ...)`. This has three known issues:

1. **Search is cached/stale** — returns old results, not real-time content
2. **20-result cap per query** — 15 users share at most 20 results
3. **Query complexity limits** — multi-user OR queries may silently degrade

## Study Design

### Tool

`tools/feed_study.py` — Python script with 5 subcommands:

| Command | Purpose |
|---------|---------|
| `harvest` | Scrape users/lists from a remote Nitpick instance |
| `import` | POST harvested users into local instance |
| `measure` | Compare search feed vs individual timelines; record rate limits |
| `cache-test` | Ping search feed at N-second intervals to detect cache TTL |
| `report` | Generate summary from collected JSONL data |

### Data Collected Per `measure` Run

- **Search feed**: tweet IDs, ages, user distribution, rate limit headers
- **Following list**: current state
- **Feed debug**: search pool structure (chunks, cursors)
- **Session health**: pool size, limited sessions, per-endpoint request counts
- **Per-user timeline**: for each followed user, their individual timeline
  tweets, ages, success/failure, rate limit consumption

### Key Metrics

- **Coverage %**: search feed tweets / individual timeline tweets
- **User coverage %**: distinct users in search / total followed
- **Freshness gap**: age difference between search results and timelines
- **Rate limit budget**: remaining capacity per endpoint per session

## Results

### Setup

- Harvested 105 users across 6 lists from twitter.ottertime.com
- 1 session (cookie auth, user `_pandeiro`)
- Local instance on port 8888 with `enableDebug: true`

### Baseline: Rate Limit Headroom

| Endpoint | Observed Limit | Headroom after full refresh |
|---|---|---|
| `UserByScreenName` | ~150/15min | ~44 (first time only; cached after) |
| `SearchTimeline` | ~50/15min | 0 (exhausted by 2 search queries) |
| `UserWithProfileTweetsV2` | ~500/15min | ~394 |
| `UserMedia` | ~500/15min | ~479 |

### Clean Measurement: Search vs Individual Timelines

**106 followed users, 30 sampled in search pool**

| Metric | Search Feed | Individual Timelines |
|--------|-------------|---------------------|
| Tweets returned | 50 | 1,969 |
| Users represented | 20 / 30 sampled | 103 / 106 total |
| Avg tweets per user | ~1.6 | ~19 |
| Tweet ID overlap | — | avg 11% |
| Rate limited | 0 | 0 |
| Errors | 0 | 3 (not found) |

**Overall coverage: 2.5%** — search captures 50 of 1,969 available tweets.

### Per-User Coverage

| User | Search tweets | Timeline tweets | Overlap | Coverage |
|------|--------------|-----------------|---------|----------|
| @ap | 1 | 20 | 1 | 5% |
| @espn | 1 | 18 | 1 | 6% |
| @latimes | 1 | 20 | 1 | 5% |
| @nytimes | 1 | 20 | 1 | 5% |
| @ryangrim | 1 | 20 | 1 | 5% |
| @geglobo | 8 | 19 | 7 | **37%** (best) |
| @nypost | 7 | 20 | 7 | **35%** |
| @ajenglish | 5 | 22 | 5 | 23% |

### Key Insight

The search endpoint and timeline endpoint return **fundamentally different
content**. For most users, only 1 tweet appears in search, but their
timeline has 17-22 fresh tweets. The search is not just "limited" — it's
fetching a different, stale result set.

Individual timeline fetches succeeded at **103/106 attempts with zero rate
limit errors**. The `UserWithProfileTweetsV2` endpoint has ample capacity
(~500 req/15min). The `UserByScreenName` endpoint (~150 req/15min) is the
tighter bottleneck, but only needed for first-time username→ID resolution;
once cached in Redis, subsequent fetches skip it.

## Decision

**Individual timeline fetches via a background worker.** The data is
decisive: search coverage is 2.5%, timeline fetches work flawlessly, and
rate limits leave ~400 requests of headroom per 15-minute window. See
`doc/RFC-feed-refresher.md` for the full design.
