# Feed Design v1

First pass on showing a timeline feed on the main screen.

(MVP can have just chronological. In the future we may want to add scoring and ranking.)

# Data Fetching

## 1. **Data Fetching Strategy**

The current implementation already has follow list management [1](#0-0)  and individual timeline fetching [2](#0-1) , but there's an important pattern to leverage: the RSS multi-user feed implementation.

The `timelineRss` function shows how to fetch tweets from multiple users [3](#0-2) . This uses `getGraphTweetSearch` with multiple usernames in `query.fromUser`, which lets Twitter's API handle the merging server-side. This is **significantly more efficient** than fetching each user's timeline individually and merging client-side.

**Key Decision:** Use Twitter's search API with multiple usernames (like the RSS route does) rather than fetching individual timelines. This reduces API calls from N (one per followed user) to 1, and Twitter handles the chronological sorting.

## 2. **Feed Generation & Caching**

For intermediate storage, you'll want a multi-tier caching strategy:

**Level 1: Feed Cache** - Cache the computed feed itself with a key like `feed:global:{cursor}` in Redis. The existing caching infrastructure [4](#0-3)  shows the pattern for RSS feeds, which would apply similarly to a main feed.

**Level 2: Individual Tweet Cache** - Already exists [5](#0-4) . Tweets are cached with a 60-minute TTL, so you'll get cache hits when the same tweets appear in multiple contexts.

**Critical consideration:** The feed cache TTL should be shorter than individual components (maybe 5-15 minutes) since the feed becomes stale faster than individual tweets. The RSS implementation uses configurable cache times [6](#0-5) .

## 3. **Pagination/Cursor Handling**

Twitter's API returns cursor-based pagination [7](#0-6) . When caching feeds, you must:
- Store the cursor with the cached feed
- Include the cursor in the cache key
- Handle the "load more" functionality [8](#0-7) 

## 4. **Algorithmic Ranking Considerations**

If you want algorithmic ranking on top of chronological:

- **Do it post-fetch, pre-cache:** Fetch chronologically from Twitter, apply your ranking algorithm, then cache the ranked result
- **Cache both versions:** Consider caching both `feed:global:chrono:{cursor}` and `feed:global:ranked:{cursor}` so users can toggle between views
- **Keep ranking lightweight:** Since you'd re-rank on every cache miss, complex ML models would hurt performance. Simple heuristics (boost tweets with engagement, penalize old tweets) work better.

## 5. **Scalability Notes**

**Watch out for API rate limits:** Currently, the codebase uses session-based rate limiting [9](#0-8) . A global feed hitting the search API frequently could exhaust limits. The cache is essential here.

**Consider incremental updates:** Instead of refetching the entire feed, you could fetch only new tweets since the last update (using the `since` parameter in the query [10](#0-9) ) and prepend them to the cached feed.

## Implementation Priority

1. **Start with pure chronological** using the multi-user search pattern from RSS
2. **Add feed-level caching** with appropriate TTLs
3. **Handle pagination** with cursors
4. **Then add ranking** if desired (keep it simple initially)

## Notes

The existing multi-user timeline support in the RSS router is your blueprint. The main difference is that RSS generates XML output, but you'd generate HTML timeline views using the existing `renderTimelineTweets` function [11](#0-10) . The data fetching and caching patterns should be nearly identical.

### Citations

**File:** src/redis_cache.nim (L28-30)
```text
proc setCacheTimes*(cfg: Config) =
  rssCacheTime = cfg.rssCacheTime * 60
  listCacheTime = cfg.listCacheTime * 60
```

**File:** src/redis_cache.nim (L98-101)
```text
proc cache*(data: Tweet) {.async.} =
  if data.isNil or data.id == 0: return
  pool.withAcquire(r):
    dawait r.setEx(data.id.tweetKey, baseCacheTime, compress(toFlatty(data)))
```

**File:** src/redis_cache.nim (L103-109)
```text
proc cacheRss*(query: string; rss: Rss) {.async.} =
  let key = "rss:" & query
  pool.withAcquire(r):
    dawait r.hSet(key, "min", rss.cursor)
    if rss.cursor != "suspended":
      dawait r.hSet(key, "rss", compress(rss.feed))
    dawait r.expire(key, rssCacheTime)
```

**File:** src/redis_cache.nim (L196-222)
```text
template followingKey(): string = "following:global"

proc isFollowing*(username: string): Future[bool] {.async.} =
  if username.len == 0: return false
  let name = toLower(username)
  pool.withAcquire(r):
    result = await r.sIsMember(followingKey(), name)

proc followUser*(username: string): Future[bool] {.async.} =
  if username.len == 0: return false
  let name = toLower(username)
  pool.withAcquire(r):
    result = (await r.sAdd(followingKey(), name)) == 1

proc unfollowUser*(username: string): Future[bool] {.async.} =
  if username.len == 0: return false
  let name = toLower(username)
  pool.withAcquire(r):
    result = (await r.sRem(followingKey(), name)) == 1

proc getFollowingList*(): Future[seq[string]] {.async.} =
  pool.withAcquire(r):
    let members = await r.sMembers(followingKey())
    result = @[]
    for m in members:
      if m.len > 0:
        result.add(m)
```

**File:** src/api.nim (L69-78)
```text
proc getGraphUserTweets*(id: string; kind: TimelineKind; after=""): Future[Profile] {.async.} =
  if id.len == 0: return
  let
    cursor = if after.len > 0: "\"cursor\":\"$1\"," % after else: ""
    url = case kind
      of TimelineKind.tweets: userTweetsUrl(id, cursor)
      of TimelineKind.replies: userTweetsAndRepliesUrl(id, cursor)
      of TimelineKind.media: mediaUrl(id, cursor)
    js = await fetch(url)
  result = parseGraphTimeline(js, after)
```

**File:** src/routes/rss.nim (L18-43)
```text
proc timelineRss*(req: Request; cfg: Config; query: Query; prefs: Prefs): Future[Rss] {.async.} =
  var profile: Profile
  let
    name = req.params.getOrDefault("name")
    after = getCursor(req)
    names = getNames(name)

  if names.len == 1:
    profile = await fetchProfile(after, query, skipRail=true)
  else:
    var q = query
    q.fromUser = names
    profile.tweets = await getGraphTweetSearch(q, after)
    # this is kinda dumb
    profile.user = User(
      username: name,
      fullname: names.join(" | "),
      userpic: "https://abs.twimg.com/sticky/default_profile_images/default_profile.png"
    )

  if profile.user.suspended:
    return Rss(feed: profile.user.username, cursor: "suspended")

  if profile.user.fullname.len > 0:
    let rss = renderTimelineRss(profile, cfg, prefs, multi=(names.len > 1))
    return Rss(feed: rss, cursor: profile.tweets.bottom)
```

**File:** src/types.nim (L33-46)
```text
  Session* = ref object
    id*: int64
    username*: string
    pending*: int
    limited*: bool
    limitedAt*: int
    apis*: Table[string, RateLimit]
    case kind*: SessionKind
    of oauth:
      oauthToken*: string
      oauthSecret*: string
    of cookie:
      authToken*: string
      ct0*: string
```

**File:** src/types.nim (L131-132)
```text
    since*: string
    until*: string
```

**File:** src/types.nim (L229-233)
```text
  Result*[T] = object
    content*: seq[T]
    top*, bottom*: string
    beginning*: bool
    query*: Query
```

**File:** src/views/timeline.nim (L27-30)
```text
proc renderMore*(query: Query; cursor: string; focus=""): VNode =
  buildHtml(tdiv(class="show-more")):
    a(href=(&"?{getQuery(query)}cursor={encodeUrl(cursor, usePlus=false)}{focus}")):
      text "Load more"
```

**File:** src/views/timeline.nim (L91-100)
```text
proc renderTimelineTweets*(results: Timeline; prefs: Prefs; path: string;
                           pinned=none(Tweet)): VNode =
  buildHtml(tdiv(class="timeline")):
    if not results.beginning:
      renderNewer(results.query, parseUri(path).path)

    if not prefs.hidePins and pinned.isSome:
      let tweet = get pinned
      renderTweet(tweet, prefs, path)

```

# How `timelineRss` Handles Multiple Usernames

The `timelineRss` function handles multiple usernames by first parsing the comma-separated name parameter using the `getNames` function, which splits the input by commas and filters out empty strings. [1](#1-0) 

The function then checks if there's only one username or multiple:

- **Single username**: Uses `fetchProfile` to get the user's timeline directly [2](#1-1) 

- **Multiple usernames**: Creates a search query with `fromUser` set to the list of usernames and calls `getGraphTweetSearch` instead [3](#1-2) 

When constructing the search query for multiple users, the `genQueryParam` function creates a Twitter search query using "OR" operators: it loops through each username and builds a query string like `from:user1 OR from:user2 OR from:user3 ...` [4](#1-3) 

The search request is then sent to Twitter's GraphQL SearchTimeline endpoint with the constructed query as the `rawQuery` parameter. [5](#1-4) 

# Twitter API Constraints

Based on the codebase, here are the constraints that affect how many users can be queried:

## 1. Query Length Limit

The RSS route enforces a **200 character limit** on search queries: [6](#1-5) 

Since each username adds approximately 10-20 characters to the query (e.g., `from:username OR `), this limits the number of users that can be queried simultaneously to roughly **10-15 users** depending on username lengths.

## 2. Rate Limits

The codebase implements comprehensive rate limit tracking:

- Rate limits are tracked per session and per API endpoint using the `RateLimit` type with `limit`, `remaining`, and `reset` fields [7](#1-6) 

- When a session's remaining requests drop to 10 or fewer, it's considered rate-limited [8](#1-7) 

- Rate-limited sessions recover after 1 hour for general limits, or 24 hours for certain errors [9](#1-8) 

- The system uses `maxConcurrentReqs` (default: 2) to prevent race conditions when updating rate limit counters [10](#1-9) 

## 3. Results Per Request

Each search request fetches **20 tweets** at a time, as specified in the GraphQL variables: [11](#1-10) 

## Notes

- **No explicit URL length limit** is documented in the codebase beyond the 200 character query limit for RSS searches. The actual Twitter API may have additional undocumented constraints.

- **No explicit parameter limit** for the number of users in a search query is mentioned in the code, but the 200 character query length effectively limits this to 10-15 users.

- The retry mechanism automatically retries failed requests once with a different session when rate limits are hit. [12](#1-11) 

- For multi-user queries, the function creates a synthetic user profile with usernames joined by " | " for display purposes. [13](#1-12)

### Citations

**File:** src/routes/router_utils.nim (L35-36)
```text
proc getNames*(name: string): seq[string] =
  name.strip(chars={'/'}).split(",").filterIt(it.len > 0)
```

**File:** src/routes/rss.nim (L25-26)
```text
  if names.len == 1:
    profile = await fetchProfile(after, query, skipRail=true)
```

**File:** src/routes/rss.nim (L27-30)
```text
  else:
    var q = query
    q.fromUser = names
    profile.tweets = await getGraphTweetSearch(q, after)
```

**File:** src/routes/rss.nim (L32-36)
```text
    profile.user = User(
      username: name,
      fullname: names.join(" | "),
      userpic: "https://abs.twimg.com/sticky/default_profile_images/default_profile.png"
    )
```

**File:** src/routes/rss.nim (L65-66)
```text
      if @"q".len > 200:
        resp Http400, showError("Search input too long.", cfg)
```

**File:** src/query.nim (L61-64)
```text
  for i, user in query.fromUser:
    param &= &"from:{user} "
    if i < query.fromUser.high:
      param &= "OR "
```

**File:** src/api.nim (L148-169)
```text
proc getGraphTweetSearch*(query: Query; after=""): Future[Timeline] {.async.} =
  let q = genQueryParam(query)
  if q.len == 0 or q == emptyQuery:
    return Timeline(query: query, beginning: true)

  var
    variables = %*{
      "rawQuery": q,
      "query_source": "typedQuery",
      "count": 20,
      "product": "Latest",
      "withDownvotePerspective": false,
      "withReactionsMetadata": false,
      "withReactionsPerspective": false
    }
  if after.len > 0:
    variables["cursor"] = % after
  let 
    url = apiReq(graphSearchTimeline, $variables)
    js = await fetch(url)
  result = parseGraphSearch[Tweets](js, after)
  result.query = query
```

**File:** src/apiutils.nim (L122-127)
```text
    if resp.headers.hasKey(rlRemaining):
      let
        remaining = parseInt(resp.headers[rlRemaining])
        reset = parseInt(resp.headers[rlReset])
        limit = parseInt(resp.headers[rlLimit])
      session.setRateLimit(req, remaining, reset, limit)
```

**File:** src/apiutils.nim (L166-171)
```text
template retry(bod) =
  try:
    bod
  except RateLimitError:
    echo "[sessions] Rate limited, retrying ", req.cookie.endpoint, " request..."
    bod
```

**File:** src/auth.nim (L11-12)
```text
  # max requests at a time per session to avoid race conditions
  maxConcurrentReqs = 2
```

**File:** src/auth.nim (L138-144)
```text
  if session.limited and api != graphUserTweetsV2:
    if (epochTime().int - session.limitedAt) > hourInSeconds:
      session.limited = false
      log "resetting limit: ", session.pretty
      return false
    else:
      return true
```

**File:** src/auth.nim (L146-150)
```text
  if api in session.apis:
    let limit = session.apis[api]
    return limit.remaining <= 10 and limit.reset > epochTime().int
  else:
    return false
```
