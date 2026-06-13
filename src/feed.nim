# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, options, logging, strutils, tables, random
import types, api, redis_cache

proc extractTweets(timeline: Timeline): seq[Tweet] =
  for thread in timeline.content:
    for t in thread:
      result.add t

const refreshBatchSize = 3
const chunksPerCycle = 3

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

proc getAllUsers*(): Future[seq[string]] {.async.} =
  ## Collect all unique usernames across all follow lists.
  let lists = await getListNames()
  var users = initTable[string, bool]()
  for listName in lists:
    let members = await getListMembers(listName)
    for user in members:
      if user.len > 0:
        users[user] = true
  result = @[]
  for user in users.keys:
    result.add user

proc refreshUserChunk(users: seq[string]) {.async.} =
  ## Fetch timelines for a chunk of users and update their respective lists.
  if users.len == 0:
    return

  for batch in users.chunked(refreshBatchSize):
    var futures: seq[Future[Profile]]
    var batchUsers: seq[string]

    for user in batch:
      if skipCounters.getOrDefault(user, 0) >= 3:
        continue
      let userId = await getUserId(user)
      if userId.len == 0:
        continue
      if userId == "suspended":
        continue
      futures.add getGraphUserTweets(userId, TimelineKind.tweets)
      batchUsers.add user

    if futures.len == 0:
      continue

    for i, fut in futures:
      var userTweets: seq[Tweet]
      try:
        let profile = await fut
        userTweets = profile.tweets.extractTweets()
        skipCounters.del(batchUsers[i])
      except CatchableError as e:
        skipCounters[batchUsers[i]] = skipCounters.getOrDefault(batchUsers[i], 0) + 1
        let failures = skipCounters[batchUsers[i]]
        if failures >= 3:
          warn "[feed-refresher] Skipping '", batchUsers[i], "' for ~10 cycles (", failures, " failures): ", e.msg
        else:
          warn "[feed-refresher] Fetch failed for '", batchUsers[i], "' (", failures, "/3): ", e.msg
        continue

      if userTweets.len > 0:
        await cache(userTweets)
        let lists = await getUserLists(batchUsers[i])
        for listName in lists:
          await updateListFeed(listName, userTweets)
        info "[feed-refresher] Accumulated ", userTweets.len, " tweets for '", batchUsers[i], "'"

proc refreshAllLists*() {.async.} =
  ## Refresh all follow lists. (Maintained for backward compatibility.)
  let users = await getAllUsers()
  await refreshUserChunk(users)

proc startFeedRefresher*(intervalSeconds: int) {.async.} =
  ## Background loop: round-robin through all users in 3 chunks, shuffling each cycle.
  ## No initial burst — the first chunk runs after the first sleep interval.
  var users: seq[string] = @[]
  var chunkIndex = 0
  var chunks: seq[seq[string]] = @[]

  while true:
    if users.len == 0 or chunkIndex >= chunksPerCycle:
      # Decay skip counters from the previous full cycle
      if skipCounters.len > 0:
        for user, count in skipCounters.mpairs:
          if count >= 3:
            skipCounters[user] = count - 1

      users = await getAllUsers()
      if users.len == 0:
        info "[feed-refresher] No users to refresh, waiting..."
        await sleepAsync(intervalSeconds * 1000)
        continue

      users.shuffle()
      let chunkSize = max(1, (users.len + chunksPerCycle - 1) div chunksPerCycle)
      chunks = users.chunked(chunkSize)
      chunkIndex = 0
      info "[feed-refresher] Full cycle complete. Reshuffled ", users.len, " users into ", chunks.len, " chunks."

    let chunk = chunks[chunkIndex]
    info "[feed-refresher] Refreshing chunk ", chunkIndex + 1, " of ", chunks.len, " (", chunk.len, " users)"
    await refreshUserChunk(chunk)

    chunkIndex += 1
    if chunkIndex >= chunksPerCycle:
      info "[feed-refresher] All chunks processed. Starting new cycle."
    else:
      info "[feed-refresher] Chunk ", chunkIndex, " complete. Waiting for next cycle."

    await sleepAsync(intervalSeconds * 1000)

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
