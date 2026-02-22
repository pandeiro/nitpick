# JSON API via Content Negotiation

## Overview

Expose Nitter's data as JSON via content negotiation on existing routes. No new endpoints, no frontend changes. Clients that want JSON send `Accept: application/json`, everyone else gets HTML.

## Goals

1. **Zero client changes** - Existing HTML frontend works unchanged
2. **Content negotiation** - Same routes serve HTML or JSON based on `Accept` header
3. **Consistency** - JSON structure mirrors embedded data in HTML
4. **Minimal overhead** - Reuse existing view logic

## How It Works

Client requests with:
```
Accept: application/json
```

Server responds with JSON instead of HTML.

```
Accept: text/html  (or omitted)
```

Server responds with HTML (existing behavior).

## Endpoints

All existing routes gain JSON support:

### Data Endpoints (High Priority)

| Route | Method | Description | Priority |
|-------|--------|-------------|----------|
| `GET /` | GET | Home feed (global) | P0 |
| `GET /?list=<name>` | GET | List feed | P0 |
| `GET /<username>` | GET | User profile + timeline | P0 |
| `GET /<username>/with_replies` | GET | User tweets with replies | P0 |
| `GET /<username>/media` | GET | User media tweets | P0 |
| `GET /<username>/status/<id>` | GET | Single tweet | P0 |
| `GET /search` | GET | Search results | P1 |
| `GET /following` | GET | Following lists | P1 |

### List Management Endpoints

| Route | Method | Description | Priority |
|-------|--------|-------------|----------|
| `GET /i/lists/<id>` | GET | List profile | P1 |
| `GET /<username>/lists` | GET | User's lists | P2 |
| `GET /pinned` | GET | Pinned tweets | P2 |

### Action Endpoints (Write operations)

| Route | Method | Description | Priority |
|-------|--------|-------------|----------|
| `POST /pin` | POST | Pin a tweet | P2 |
| `POST /unpin` | POST | Unpin a tweet | P2 |
| `POST /follow` | POST | Follow a user | P2 |
| `POST /unfollow` | POST | Unfollow a user | P2 |
| `POST /lists/create` | POST | Create a list | P2 |
| `POST /lists/delete` | POST | Delete a list | P2 |
| `POST /lists/rename` | POST | Rename a list | P2 |
| `POST /lists/<name>/add` | POST | Add user to list | P2 |
| `POST /lists/<name>/remove` | POST | Remove user from list | P2 |

### No JSON Support Needed

| Route | Reason |
|-------|--------|
| `GET /settings` | HTML form, user preferences |
| `GET /about` | Static HTML page |
| `GET /rss/*` | Already XML, different use case |
| `GET /embed/*` | iframe content, not data |
| `GET /.*` (debug) | Already JSON when enabled |

## Response Formats

### Profile (`GET /<username>`)

```json
{
  "user": {
    "id": "12345",
    "username": "jack",
    "display_name": "Jack",
    "bio": "bio text",
    "location": "San Francisco",
    "website": "https://jack.com",
    "verified": false,
    "verified_type": "none",
    "protected": false,
    "followers_count": 5000,
    "following_count": 1000,
    "tweets_count": 10000,
    "likes_count": 5000,
    "media_count": 100,
    "avatar_url": "https://pbs.twimg.com/profile_images/...",
    "banner_url": "https://pbs.twimg.com/profile_banners/...",
    "join_date": "2006-03-21T00:00:00Z"
  },
  "preferences": {
    "theme": "Nitter",
    "replace_twitter": "nitter.net",
    "replace_youtube": "piped.video"
  }
}
```

### Timeline (`GET /<username>` or `GET /`)

```json
{
  "tweets": [
    {
      "id": "1234567890",
      "text": "Tweet content",
      "html": "<p>Tweet content</p>",
      "author": {
        "id": "12345",
        "username": "jack",
        "display_name": "Jack",
        "avatar_url": "https://..."
      },
      "created_at": "2024-01-01T00:00:00Z",
      "reply_count": 10,
      "retweet_count": 5,
      "like_count": 20,
      "quote_count": 2,
      "view_count": 1000,
      "media": [
        {
          "type": "photo",
          "url": "https://..."
        }
      ],
      "pinned": false,
      "retweeted": false,
      "liked": false
    }
  ],
  "pagination": {
    "next_cursor": "abc123",
    "previous_cursor": ""
  },
  "meta": {
    "sampled_count": 30,
    "following_count": 150,
    "result_count": 50,
    "last_updated": 1704067200
  }
}
```

### Following Lists (`GET /following`)

```json
{
  "lists": [
    {
      "name": "default",
      "members": ["user1", "user2", "user3"]
    },
    {
      "name": "tech",
      "members": ["user1", "user4"]
    }
  ],
  "all_members": ["user1", "user2", "user3", "user4"]
}
```

### Search (`GET /search`)

```json
{
  "tweets": [...],
  "users": [
    {
      "id": "12345",
      "username": "jack",
      "display_name": "Jack",
      "bio": "...",
      "avatar_url": "https://..."
    }
  ],
  "pagination": {
    "next_cursor": "abc123"
  }
}
```

### Single Tweet (`GET /<username>/status/<id>`)

```json
{
  "tweet": { ... },
  "replies": [...],
  "conversation": {
    "before": [...],
    "after": [...]
  }
}
```

## Implementation

### Pattern: Add JSON variant to existing route handlers

In each route file, add a conditional:

```nim
# Example pattern
router main:
  get "/@name":
    let acceptJson = req.headers.getOrDefault("accept") == "application/json"
    
    if acceptJson:
      # Fetch data
      let profile = await fetchProfile(...)
      let tweets = await fetchTweets(...)
      
      # Return JSON
      respJson(%*{
        "user": profile.toJson(),
        "tweets": tweets.toJson()
      })
    else:
      # Return HTML (existing)
      await renderProfile()
```

### Serialization Strategy

Existing view templates embed data in `<script id="initial-data" type="application/json">`. Reuse this serialization:

1. Use existing `toJson()` procs if available
2. Create new serialization procs for API response format
3. Ensure API JSON exactly matches embedded JSON structure

### Testing Strategy

**Goal**: Verify JSON response matches embedded data in HTML.

**Approach**:
1. Request same route with `Accept: application/json`
2. Parse JSON response
3. Extract `initial-data` from HTML version
4. Compare key fields

**Test locations**: `tests/test_api_json.py`

## Error Responses

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "User not found"
  }
}
```

Standard error codes:
- `NOT_FOUND` - User/tweet doesn't exist
- `RATE_LIMITED` - Twitter API rate limited
- `UNAUTHORIZED` - Auth required
- `INTERNAL_ERROR` - Server error

## Rate Limiting

Add headers to JSON responses:
```
X-RateLimit-Limit: 180
X-RateLimit-Remaining: 150
X-RateLimit-Reset: 1704067200
```

## Implementation Roadmap & Priority

Based on codebase analysis, here's the prioritized order:

### Phase 1: Core Read-Only Endpoints (Highest Value)

| Priority | Route | File | Complexity | Notes |
|----------|-------|------|------------|-------|
| P0 | `GET /` (home feed) | `nitter.nim:89-107` | Medium | Already uses `fetchFeed()`, just needs JSON wrapper |
| P0 | `GET /<username>` | `timeline.nim:123-168` | Medium | Profile + tweets, uses `fetchProfile()` |
| P0 | `GET /<username>/with_replies` | `timeline.nim` | Low | Same handler, different query param |
| P0 | `GET /<username>/media` | `timeline.nim` | Low | Same handler, different query param |

### Phase 2: Discovery & Search

| Priority | Route | File | Complexity | Notes |
|----------|-------|------|------------|-------|
| P1 | `GET /search` | `search.nim:16-44` | Low | Returns `Result[User]` or `Result[Tweet]` |
| P1 | `GET /following` | `follow.nim:14-22` | Low | Simple table lookup, returns lists |
| P1 | `GET /i/lists/<id>` | `list.nim:36-44` | Low | List profile + tweets |

### Phase 3: User Content & Actions

| Priority | Route | File | Complexity | Notes |
|----------|-------|------|------------|-------|
| P2 | `GET /<username>/status/<id>` | `status.nim` | Medium | Single tweet + replies + conversation |
| P2 | `GET /pinned` | `pinned.nim:53-54` | Low | Returns `seq[Tweet]` |
| P2 | `GET /<username>/lists` | `list.nim:25-34` | Low | User's lists (redirects) |
| P2 | `POST /follow` | `follow.nim:24-31` | Low | Action, returns redirect |
| P2 | `POST /unfollow` | `follow.nim:33-40` | Low | Action, returns redirect |
| P2 | `POST /pin` | `pinned.nim:56-57` | Low | Action, returns redirect |
| P2 | `POST /unpin` | `pinned.nim:59-60` | Low | Action, returns redirect |

### Phase 4: List Management

| Priority | Route | File | Complexity | Notes |
|----------|-------|------|------------|-------|
| P3 | `POST /lists/create` | `follow.nim:42-49` | Low | Action |
| P3 | `POST /lists/delete` | `follow.nim:51-58` | Low | Action |
| P3 | `POST /lists/rename` | `follow.nim:60-69` | Low | Action |
| P3 | `GET /i/lists/<id>/members` | `list.nim:46-52` | Low | List members |

## Complexity Analysis

### Low Complexity (1-2 hours each)
- Routes that return simple data structures (lists, pinned tweets)
- Actions that return redirects
- Routes that reuse existing fetch logic with minimal transformation

**Files to modify**: `follow.nim`, `pinned.nim`, `list.nim` (portions)

### Medium Complexity (2-4 hours each)
- Routes with complex data transformations
- Routes combining multiple data sources
- Routes requiring new serialization procs

**Files to modify**: `nitter.nim`, `timeline.nim`, `search.nim`, `status.nim`

## Implementation Pattern

Each route handler follows this pattern:

```nim
get "/endpoint":
  let acceptJson = req.headers.getOrDefault("accept") == "application/json"
  
  # Fetch data (existing logic)
  let data = await fetchData(...)
  
  if acceptJson:
    # Return JSON
    respJson(%*{
      "key": data.toJson()
    })
  else:
    # Return HTML (existing)
    resp renderPage(data)
```

## Estimated Total Effort

| Phase | Endpoints | Hours |
|-------|-----------|-------|
| P0 | 4 | 8-12 |
| P1 | 3 | 4-6 |
| P2 | 6 | 6-10 |
| P3 | 4 | 4-6 |
| **Total** | **17** | **22-34** |

## Open Questions

1. Should we add an API version header? (`Accept-Version: v1`)
2. Should JSON routes have separate rate limits from HTML?
3. How to handle streaming/Server-Sent Events for real-time?
4. Should we add `?format=json` query param as fallback for clients that can't set headers?
