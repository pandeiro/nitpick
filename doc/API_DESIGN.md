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

| Route | Description |
|-------|-------------|
| `GET /<username>` | User profile |
| `GET /<username>/with_replies` | User tweets with replies |
| `GET /<username>/media` | User media tweets |
| `GET /` | Home feed (global) |
| `GET /?list=<name>` | List feed |
| `GET /following` | Following lists |
| `GET /search?q=<query>` | Search results |
| `GET /search?q=<query>&kind=users` | User search |
| `GET /<username>/status/<id>` | Single tweet |
| `GET /i/lists/<id>` | List profile |
| `GET /pinned` | Pinned tweets |

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

## Open Questions

1. Should we add an API version header? (`Accept-Version: v1`)
2. Should JSON routes have separate rate limits from HTML?
3. How to handle streaming/Server-Sent Events for real-time?
4. Should we add `?format=json` query param as fallback for clients that can't set headers?
