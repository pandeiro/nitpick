# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, options, logging, strutils, tables
import types, api, redis_cache

proc extractTweets(timeline: Timeline): seq[Tweet] =
  for thread in timeline.content:
    for t in thread:
      result.add t

const refreshBatchSize = 3

var skipCounters = initTable[string, int]()  # module-level: consecutive failures per user

proc chunked*[T](s: openArray[T]; chunkSize: int): seq[seq[T]] =
  ## Splits a sequence into fixed-size chunks. The last chunk may be smaller.
  result = @[]
  var i = 0
  while i < s.len:
    let endIdx = min(i + chunkSize, s.len)
    var chunk: seq[T]
    for j in i ..< endIdx:
      chunk.add s[j]
    result.add chunk
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
    var batchUsers: seq[string]  # tracks which user each future corresponds to

    for user in batch:
      if skipCounters.getOrDefault(user, 0) >= 3:
        debug "[feed-refresher] Skipping '", user, "' (", skipCounters[user], " consecutive failures)"
        continue

      let userId = await getUserId(user)  # cached after first resolve
      if userId.len == 0:
        warn "[feed-refresher] Empty userId for '", user, "', skipping."
        continue
      if userId == "suspended":
        debug "[feed-refresher] User '", user, "' is suspended, skipping."
        continue
      futures.add getGraphUserTweets(userId, TimelineKind.tweets)
      batchUsers.add user

    if futures.len == 0:
      continue

    var batchTweets: seq[Tweet]
    for i, fut in futures:
      try:
        let profile = await fut
        batchTweets.add profile.tweets.extractTweets()
        skipCounters.del(batchUsers[i])  # success — reset counter
      except CatchableError as e:
        skipCounters[batchUsers[i]] = skipCounters.getOrDefault(batchUsers[i], 0) + 1
        let failures = skipCounters[batchUsers[i]]
        if failures >= 3:
          warn "[feed-refresher] Skipping '", batchUsers[i], "' for ~10 cycles (", failures, " failures): ", e.msg
        else:
          warn "[feed-refresher] Fetch failed for '", batchUsers[i], "' (", failures, "/3): ", e.msg

    if batchTweets.len > 0:
      await cache(batchTweets)
      await updateListFeed(listName, batchTweets)
      info "[feed-refresher] Accumulated ", batchTweets.len, " tweets for '", listName, "'"

proc refreshAllLists*() {.async.} =
  ## Refresh all follow lists. Exported for testing.
  let lists = await getListNames()
  for listName in lists:
    await refreshListFeed(listName)

proc startFeedRefresher*(intervalSeconds: int) {.async.} =
  ## Background loop: immediately refresh all lists, then repeat on a timer.
  ## Call from nitter.nim after Redis init.

  # Immediate seed — populate feed cache within seconds of startup
  info "[feed-refresher] Starting initial feed refresh..."
  await refreshAllLists()
  info "[feed-refresher] Initial refresh complete."

  # Periodic refreshes
  while true:
    await sleepAsync(intervalSeconds * 1000)
    info "[feed-refresher] Starting periodic refresh cycle..."
    await refreshAllLists()
    # Decay skip counters after each full cycle
    if skipCounters.len > 0:
      for user, count in skipCounters.mpairs:
        if count >= 3:
          skipCounters[user] = count - 1  # gradual decay toward re-check
    info "[feed-refresher] Periodic refresh complete."

proc fetchFeed*(following: seq[string]; prefs: Prefs; cursor = "";
                strategy = "Sampling"; listName = "default"): Future[Timeline] {.async.} =
  ## DEPRECATED: Replaced by background worker (startFeedRefresher).
  ## Kept as stub for rollback compatibility; reads from Redis cache.
  if following.len == 0:
    return Timeline()
  let feedData = await getListFeed(listName)
  if feedData.isSome:
    let f = feedData.get()
    let latestIds = if f.tweetIds.len > 50: f.tweetIds[0..<50] else: f.tweetIds
    let tweets = await getCachedTweets(latestIds)
    var threads: seq[Tweets]
    for t in tweets:
      threads.add @[t]
    return Timeline(
      content: threads,
      beginning: cursor.len == 0,
      bottom: "",
      query: Query(),
      sampledCount: f.tweetIds.len,
      followingCount: following.len,
      lastUpdated: f.lastUpdated
    )
  return Timeline()

proc fetchGlobalFeed*(following: seq[string]; prefs: Prefs; cursor = "";
                      strategy = "Sampling"): Future[Timeline] {.async.} =
  result = await fetchFeed(following, prefs, cursor, strategy, "default")
