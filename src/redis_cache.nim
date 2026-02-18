# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, times, strformat, strutils, tables, hashes, algorithm, options, json
import redis, redpool, flatty, supersnappy

import types, api

const
  redisNil = "\0\0"
  baseCacheTime = 60 * 60

var
  pool: RedisPool
  rssCacheTime: int
  listCacheTime*: int

template dawait(future) =
  discard await future

# flatty can't serialize DateTime, so we need to define this
proc toFlatty*(s: var string, x: DateTime) =
  s.toFlatty(x.toTime().toUnix())

proc fromFlatty*(s: string, i: var int, x: var DateTime) =
  var unix: int64
  s.fromFlatty(i, unix)
  x = fromUnix(unix).utc()

proc setCacheTimes*(cfg: Config) =
  rssCacheTime = cfg.rssCacheTime * 60
  listCacheTime = cfg.listCacheTime * 60

proc migrate*(key, match: string) {.async.} =
  pool.withAcquire(r):
    let hasKey = await r.get(key)
    if hasKey == redisNil:
      let list = await r.scan(newCursor(0), match, 100000)
      r.startPipelining()
      for item in list:
        dawait r.del(item)
      await r.setk(key, "true")
      dawait r.flushPipeline()

proc initRedisPool*(cfg: Config) {.async.} =
  try:
    pool = await newRedisPool(cfg.redisConns, cfg.redisMaxConns,
                              host=cfg.redisHost, port=cfg.redisPort,
                              password=cfg.redisPassword)

    await migrate("flatty", "*:*")
    await migrate("snappyRss", "rss:*")
    await migrate("userBuckets", "p:*")
    await migrate("profileDates", "p:*")
    await migrate("profileStats", "p:*")
    await migrate("userType", "p:*")
    await migrate("verifiedType", "p:*")

    pool.withAcquire(r):
      # optimize memory usage for user ID buckets
      await r.configSet("hash-max-ziplist-entries", "1000")

  except OSError:
    stdout.write "Failed to connect to Redis.\n"
    stdout.flushFile
    quit(1)

template uidKey(name: string): string = "pid:" & $(hash(name) div 1_000_000)
template userKey(name: string): string = "p:" & name
template listKey(l: List): string = "l:" & l.id
template tweetKey(id: int64): string = "t:" & $id
template globalFeedKey(): string = "nitpick:feed:global"

proc get(query: string): Future[string] {.async.} =
  pool.withAcquire(r):
    result = await r.get(query)

proc setEx(key: string; time: int; data: string) {.async.} =
  pool.withAcquire(r):
    dawait r.setEx(key, time, data)

proc cacheUserId*(username, id: string) {.async.} =
  if username.len == 0 or id.len == 0: return
  let name = toLower(username)
  pool.withAcquire(r):
    dawait r.hSet(name.uidKey, name, id)

proc cache*(data: List) {.async.} =
  await setEx(data.listKey, listCacheTime, compress(toFlatty(data)))

proc cache*(data: PhotoRail; name: string) {.async.} =
  await setEx("pr2:" & toLower(name), baseCacheTime * 2, compress(toFlatty(data)))

proc cache*(data: User) {.async.} =
  if data.username.len == 0: return
  let name = toLower(data.username)
  await cacheUserId(name, data.id)
  pool.withAcquire(r):
    dawait r.setEx(name.userKey, baseCacheTime, compress(toFlatty(data)))

proc cache*(data: Tweet) {.async.} =
  if data.isNil or data.id == 0: return
  await setEx(data.id.tweetKey, baseCacheTime, compress(toFlatty(data)))

proc cache*(tweets: seq[Tweet]) {.async.} =
  for tweet in tweets:
    await cache(tweet)

proc cacheThreads*(threads: seq[seq[Tweet]]) {.async.} =
  for thread in threads:
    await cache(thread)

proc cacheRss*(query: string; rss: Rss) {.async.} =
  let key = "rss:" & query
  pool.withAcquire(r):
    dawait r.hSet(key, "min", rss.cursor)
    if rss.cursor != "suspended":
      dawait r.hSet(key, "rss", compress(rss.feed))
    dawait r.expire(key, rssCacheTime)

template deserialize(data, T) =
  try:
    result = fromFlatty(uncompress(data), T)
  except:
    echo "Decompression failed($#): '$#'" % [astToStr(T), data]

proc getUserId*(username: string): Future[string] {.async.} =
  let name = toLower(username)
  pool.withAcquire(r):
    result = await r.hGet(name.uidKey, name)
    if result == redisNil:
      let user = await getGraphUser(username)
      if user.suspended:
        return "suspended"
      else:
        await all(cacheUserId(name, user.id), cache(user))
        return user.id

proc getCachedUser*(username: string; fetch=true): Future[User] {.async.} =
  let prof = await get("p:" & toLower(username))
  if prof != redisNil:
    prof.deserialize(User)
  elif fetch:
    result = await getGraphUser(username)
    await cache(result)

proc getCachedUsername*(userId: string): Future[string] {.async.} =
  let
    key = "i:" & userId
    username = await get(key)

  if username != redisNil:
    result = username
  else:
    let user = await getGraphUserById(userId)
    result = user.username
    await setEx(key, baseCacheTime, result)
    if result.len > 0 and user.id.len > 0:
      await all(cacheUserId(result, user.id), cache(user))

proc getCachedTweet*(id: int64; fetch=true): Future[Tweet] {.async.} =
  if id == 0: return
  let tweet = await get(id.tweetKey)
  if tweet != redisNil:
    tweet.deserialize(Tweet)
  elif fetch:
    result = await getGraphTweetResult($id)
    if not result.isNil:
      await cache(result)

proc getCachedPhotoRail*(id: string): Future[PhotoRail] {.async.} =
  if id.len == 0: return
  let rail = await get("pr2:" & toLower(id))
  if rail != redisNil:
    rail.deserialize(PhotoRail)
  else:
    result = await getPhotoRail(id)
    await cache(result, id)

proc getCachedList*(username=""; slug=""; id=""): Future[List] {.async.} =
  let list = if id.len == 0: redisNil
             else: await get("l:" & id)

  if list != redisNil:
    list.deserialize(List)
  else:
    if id.len > 0:
      result = await getGraphList(id)
    else:
      result = await getGraphListBySlug(username, slug)
    await cache(result)

proc getCachedRss*(key: string): Future[Rss] {.async.} =
  let k = "rss:" & key
  pool.withAcquire(r):
    result.cursor = await r.hGet(k, "min")
    if result.cursor.len > 2:
      if result.cursor != "suspended":
        let feed = await r.hGet(k, "rss")
        if feed.len > 0 and feed != redisNil:
          try: result.feed = uncompress feed
          except: echo "Decompressing RSS failed: ", feed
    else:
      result.cursor.setLen 0

template followingKey(): string = "following:global"
template pinnedIdsKey(): string = "pinned:ids"
template pinnedTweetKey(tweetId: int64): string = "pinned:" & $tweetId

proc isPinned*(tweetId: int64): Future[bool] {.async.} =
  pool.withAcquire(r):
    result = await r.sIsMember(pinnedIdsKey(), $tweetId)

proc addPinnedTweet*(tweet: Tweet): Future[bool] {.async.} =
  if tweet.isNil or tweet.id == 0: return false
  let tweetId = $tweet.id
  pool.withAcquire(r):
    # Add to pinned IDs set (idempotent)
    discard await r.sAdd(pinnedIdsKey(), tweetId)
    # Store serialized tweet data without expiry (persistent until unpinned)
    await r.setk(pinnedTweetKey(tweet.id), compress(toFlatty(tweet)))
    result = true

proc removePinnedTweet*(tweetId: int64): Future[bool] {.async.} =
  pool.withAcquire(r):
    # Remove from pinned IDs set
    discard await r.sRem(pinnedIdsKey(), $tweetId)
    # Delete tweet data key
    dawait r.del(pinnedTweetKey(tweetId))
    result = true

proc getPinnedTweets*(): Future[seq[Tweet]] {.async.} =
  pool.withAcquire(r):
    let ids = await r.sMembers(pinnedIdsKey())
    result = @[]
    for id in ids:
      if id.len == 0: continue
      let data = await r.get(pinnedTweetKey(parseBiggestInt(id)))
      if data != redisNil and data.len > 0:
        try:
          let tweet = fromFlatty(uncompress(data), Tweet)
          if not tweet.isNil:
            result.add(tweet)
        except:
          discard # Skip corrupted/missing data
    # Sort by time descending (newest first)
    result.sort(proc (a, b: Tweet): int = cmp(b.time, a.time))

proc setPinnedStatus*(tweets: seq[Tweet]) {.async.} =
  # Batch check pin status for multiple tweets
  for tweet in tweets:
    if tweet != nil and tweet.id != 0:
      tweet.pinned = await isPinned(tweet.id)

proc setPinnedStatus*(threads: seq[seq[Tweet]]) {.async.} =
  for thread in threads:
    await setPinnedStatus(thread)

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

proc getGlobalFeed*(): Future[Option[GlobalFeed]] {.async.} =
  let data = await get(globalFeedKey())
  if data != redisNil and data.len > 0:
    var feed: GlobalFeed
    try:
      feed = fromFlatty(uncompress(data), GlobalFeed)
      return some(feed)
    except:
      echo "Decompressing global feed failed"
  return none(GlobalFeed)

proc updateGlobalFeed*(newTweets: seq[Tweet]; cursor: string;
                      sampled: seq[string]) {.async.} =
  let existing = await getGlobalFeed()
  var feed: GlobalFeed
  
  if existing.isSome:
    feed = existing.get()
  
  # Accumulate sampled users
  for user in sampled:
    if user notin feed.sampledUsers:
      feed.sampledUsers.add user
  
  # Accumulate and de-duplicate tweet IDs
  var newIds: seq[int64] = @[]
  for t in newTweets:
    if t.id notin feed.tweetIds:
      newIds.add t.id
  
  if newIds.len > 0:
    feed.tweetIds = newIds & feed.tweetIds
    # Keep only the latest 1000 tweets in global feed cache
    if feed.tweetIds.len > 1000:
      feed.tweetIds.setLen(1000)
  
  feed.cursor = cursor
  feed.lastUpdated = getTime().toUnix()
  
  # TTL of 15 minutes (900 seconds) for the feed accumulation window
  await setEx(globalFeedKey(), 900, compress(toFlatty(feed)))

proc getGlobalFeedDebug*(): Future[JsonNode] {.async.} =
  let feed = await getGlobalFeed()
  if feed.isSome:
    let f = feed.get()
    return %*{
      "tweetIds": f.tweetIds,
      "lastUpdated": f.lastUpdated,
      "cursor": f.cursor,
      "sampledUsers": f.sampledUsers
    }
  else:
    return %*{}

proc clearGlobalFeed*() {.async.} =
  pool.withAcquire(r):
    discard await r.del(globalFeedKey())

proc clearFollowingList*() {.async.} =
  pool.withAcquire(r):
    discard await r.del(followingKey())
