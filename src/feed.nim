# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, random, options, logging, strutils
import types, api, redis_cache

randomize()

const
  ChunkSize = 15
  TotalSampleSize = 30

proc buildSearchQuery(users: seq[string]; excludes: seq[string]): Query =
  var queryStr = "("
  for i, user in users:
    queryStr.add "from:" & user
    if i < users.high:
      queryStr.add " OR "
  queryStr.add ")"
  result = Query(text: queryStr, kind: tweets, excludes: excludes)

proc extractTweets(timeline: Timeline): seq[Tweet] =
  for thread in timeline.content:
    for t in thread:
      result.add t

proc fetchGlobalFeed*(following: seq[string]; prefs: Prefs; cursor = "";
                     strategy = "Sampling"): Future[Timeline] {.async.} =
  ## Fetches a chronological feed for the given list of followed users.
  ## Implements "Sampling with Accumulation":
  ## 1. On initial load, samples up to 30 users, split into 2 parallel searches.
  ## 2. Fetches their latest tweets via Twitter search.
  ## 3. Merges and de-duplicates results into a persistent Redis-backed global feed.
  ## 4. For pagination (load more), iterates through all search pool entries.
  if following.len == 0:
    info "[feed] Global feed requested but following list is empty."
    return Timeline()

  if cursor.len == 0:
    info "[feed] Initializing new global feed fetch (initial load)."
  else:
    info "[feed] Pagination request for global feed with cursor: ", cursor

  let feedData = await getGlobalFeed()
  var searchPool: seq[SearchPoolEntry]
  
  var excludes: seq[string] = @["replies"]
  if prefs.hideRetweets:
    excludes.add "nativeretweets"

  if cursor.len == 0:
    var sampled = following
    if strategy == "Sampling" and sampled.len > TotalSampleSize:
      sampled.shuffle()
      sampled.setLen(TotalSampleSize)
    elif strategy == "Sequential" and sampled.len > TotalSampleSize:
      sampled.setLen(TotalSampleSize)
    
    info "[feed] Sampling strategy: ", strategy, " (", sampled.len, " users sampled)"
    debug "[feed] Sampled users: ", sampled.join(", ")
    
    # Split into chunks of ChunkSize
    var i = 0
    while i < sampled.len:
      var chunk: seq[string]
      var j = i
      while j < min(i + ChunkSize, sampled.len):
        chunk.add sampled[j]
        inc j
      if chunk.len > 0:
        searchPool.add SearchPoolEntry(users: chunk, cursor: "")
      i += ChunkSize
    
    info "[feed] Created ", searchPool.len, " search pool entries."
    for idx, entry in searchPool:
      debug "[feed] Pool entry ", idx, ": ", entry.users.len, " users"
  else:
    if feedData.isSome:
      searchPool = feedData.get().searchPool
      info "[feed] Continuing pagination with ", searchPool.len, " search pool entries from cache."
    else:
      warn "[feed] Cursor present but no cached metadata found. Falling back to new sample."
      var sampled = following
      if sampled.len > TotalSampleSize: sampled.setLen(TotalSampleSize)
      var i = 0
      while i < sampled.len:
        var chunk: seq[string]
        var j = i
        while j < min(i + ChunkSize, sampled.len):
          chunk.add sampled[j]
          inc j
        if chunk.len > 0:
          searchPool.add SearchPoolEntry(users: chunk, cursor: "")
        i += ChunkSize

  # Execute parallel searches (skip exhausted entries on pagination)
  var futures: seq[Future[Timeline]]
  var queries: seq[Query]
  var poolIndices: seq[int]
  
  for i, entry in searchPool:
    if cursor.len > 0 and entry.cursor.len == 0:
      info "[feed] Pool entry ", i, " exhausted (no more results), skipping."
      continue
    let q = buildSearchQuery(entry.users, excludes)
    queries.add q
    poolIndices.add i
    futures.add getGraphTweetSearch(q, entry.cursor)
  
  if futures.len == 0:
    info "[feed] All pool entries exhausted. No more results to fetch."
    let f = feedData.get()
    var latestIds = f.tweetIds
    if latestIds.len > 50: latestIds.setLen(50)
    let tweets = await getCachedTweets(latestIds)
    var threads: seq[Tweets]
    for t in tweets:
      threads.add @[t]
    return Timeline(
      content: threads,
      beginning: false,
      bottom: "",
      sampledCount: f.searchPool.len * ChunkSize,
      followingCount: following.len,
      lastUpdated: f.lastUpdated
    )
  
  info "[feed] Executing ", futures.len, " parallel search queries..."
  
  var allTweets: seq[Tweet]
  var updatedPool = searchPool
  var lastBottom: string
  
  for i, fut in futures:
    let searchResult = await fut
    let poolIdx = poolIndices[i]
    info "[feed] Query ", i, " (pool entry ", poolIdx, ") returned ", searchResult.content.len, " thread(s)."
    
    allTweets.add extractTweets(searchResult)
    
    updatedPool[poolIdx] = SearchPoolEntry(
      users: searchPool[poolIdx].users,
      cursor: searchResult.bottom
    )
    lastBottom = searchResult.bottom

  # Cache all fetched tweets
  if allTweets.len > 0:
    info "[feed] Caching ", allTweets.len, " tweets to Redis."
    await cache(allTweets)

  # Update global feed in Redis
  await updateGlobalFeed(allTweets, updatedPool)

  # Prepare final timeline from accumulated cache
  let updatedFeed = await getGlobalFeed()
  if updatedFeed.isSome:
    let f = updatedFeed.get()
    
    var latestIds = f.tweetIds
    if latestIds.len > 50: latestIds.setLen(50)
    
    info "[feed] Resolving ", latestIds.len, " tweet IDs from cache to build final timeline."
    let tweets = await getCachedTweets(latestIds)
    
    if tweets.len < latestIds.len:
      warn "[feed] Cache miss: requested ", latestIds.len, " tweets, only found ", tweets.len, " in cache."
    
    var threads: seq[Tweets]
    for t in tweets:
      threads.add @[t]
    
    var totalSampledUsers = 0
    for entry in f.searchPool:
      totalSampledUsers += entry.users.len
    
    info "[feed] Feed generation complete. ", f.tweetIds.len, " total tweets in global cache. ", 
         f.searchPool.len, " pool(s) covering ", totalSampledUsers, "/", following.len, " followed users."
    
    result = Timeline(
      content: threads,
      beginning: cursor.len == 0,
      top: "",
      bottom: lastBottom,
      query: if queries.len > 0: queries[0] else: Query(),
      sampledCount: totalSampledUsers,
      followingCount: following.len,
      lastUpdated: f.lastUpdated
    )
  else:
    error "[feed] Fatal error: Global feed cache disappeared during processing."
    result = Timeline(beginning: cursor.len == 0)
