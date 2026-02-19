# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, random, algorithm, options, logging, strutils
import types, api, redis_cache

randomize()

proc fetchGlobalFeed*(following: seq[string]; prefs: Prefs; cursor = "";
                     strategy = "Sampling"): Future[Timeline] {.async.} =
  ## Fetches a chronological feed for the given list of followed users.
  ## Implements "Sampling with Accumulation":
  ## 1. On initial load, samples a subset of users (default 15).
  ## 2. Fetches their latest tweets via Twitter search.
  ## 3. Merges and de-duplicates results into a persistent Redis-backed global feed.
  ## 4. For pagination (load more), uses the same sampled users to maintain cursor consistency.
  if following.len == 0:
    info "[feed] Global feed requested but following list is empty."
    return Timeline()

  if cursor.len == 0:
    info "[feed] Initializing new global feed fetch (initial load)."
  else:
    info "[feed] Pagination request for global feed with cursor: ", cursor

  # 1. Load latest feed metadata
  let feedData = await getGlobalFeed()
  var 
    sampled: seq[string]
    useCursor = cursor

  # 2. Strategy: Initial Fetch (no cursor) vs Load More (has cursor)
  if useCursor.len == 0:
    # New sample
    sampled = following
    if strategy == "Sampling" and sampled.len > 15:
      sampled.shuffle()
      sampled.setLen(15)
    elif strategy == "Sequential" and sampled.len > 15:
      sampled.setLen(15)
    
    info "[feed] Sampling strategy: ", strategy, " (", sampled.len, " users sampled)"
    debug "[feed] Sampled users: ", sampled.join(", ")
  else:
    # Use existing sample for valid pagination
    if feedData.isSome:
      sampled = feedData.get().sampledUsers
      info "[feed] Continuing pagination with ", sampled.len, " users from cached metadata."
    else:
      # Fallback (shouldn't happen with valid cursor)
      warn "[feed] Cursor present but no cached metadata found. Falling back to new sample."
      sampled = following
      if sampled.len > 15: sampled.setLen(15)

  # 3. Construct search query: (from:user1 OR from:user2 OR ...)
  var queryStr = "("
  for i, user in sampled:
    queryStr.add "from:" & user
    if i < sampled.high:
      queryStr.add " OR "
  queryStr.add ")"

  # 4. Fetch from Twitter Search
  var excludes: seq[string] = @["replies"] # Always exclude replies as per 1a
  if prefs.hideRetweets:
    excludes.add "nativeretweets"
  
  info "[feed] Fetching tweets from Twitter search..."
  let 
    q = Query(text: queryStr, kind: tweets, excludes: excludes)
    searchResult = await getGraphTweetSearch(q, useCursor)
  
  info "[feed] Fetched ", searchResult.content.len, " thread(s) from Twitter API."
  
  # 5. Accumulate results
  var allTweets: seq[Tweet] = @[]
  for thread in searchResult.content:
    for t in thread:
      allTweets.add t
  
  # Cache all fetched tweets so they can be resolved later
  if allTweets.len > 0:
    info "[feed] Caching ", allTweets.len, " tweets to Redis."
    await cache(allTweets)
  
  # Update global feed in Redis (stores only tweet IDs)
  # Note: if it was a "Load More", searchResult.bottom is the next page's cursor
  await updateGlobalFeed(allTweets, searchResult.bottom, sampled)

  # 6. Prepare final timeline from accumulated cache
  # We read the latest IDs and then resolve them
  let updatedFeed = await getGlobalFeed()
  if updatedFeed.isSome:
    let f = updatedFeed.get()
    
    # Resolve the latest 50 tweet IDs into objects
    var latestIds = f.tweetIds
    if latestIds.len > 50: latestIds.setLen(50)
    
    info "[feed] Resolving ", latestIds.len, " tweet IDs from cache to build final timeline."
    let tweets = await getCachedTweets(latestIds)
    
    if tweets.len < latestIds.len:
      warn "[feed] Cache miss: requested ", latestIds.len, " tweets, only found ", tweets.len, " in cache."
    
    # Wrap tweets into threads for Timeline compatibility
    var threads: seq[Tweets] = @[]
    for t in tweets:
      threads.add @[t]
      
    info "[feed] Feed generation complete. ", f.tweetIds.len, " total tweets in global cache."
    result = Timeline(
      content: threads,
      beginning: useCursor.len == 0,
      top: searchResult.top,
      bottom: searchResult.bottom,
      query: q,
      sampledCount: f.sampledUsers.len,
      followingCount: following.len,
      lastUpdated: f.lastUpdated
    )
  else:
    error "[feed] Fatal error: Global feed cache disappeared during processing."
    # Fallback to current search result if cache failed
    result = searchResult
    result.beginning = useCursor.len == 0
