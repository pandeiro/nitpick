# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, random, algorithm, options
import types, api, redis_cache

randomize()

proc fetchGlobalFeed*(following: seq[string]; cursor = "";
                     strategy = "Sampling"): Future[Timeline] {.async.} =
  if following.len == 0:
    return Timeline()

  var sampled: seq[string] = following
  if strategy == "Sampling":
    if sampled.len > 15:
      sampled.shuffle()
      sampled.setLen(15)
  else:
    # Sequential (Future)
    if sampled.len > 15:
      sampled.setLen(15)

  # Construct search query: (from:user1 OR from:user2 OR ...)
  var queryStr = "("
  for i, user in sampled:
    queryStr.add "from:" & user
    if i < sampled.high:
      queryStr.add " OR "
  queryStr.add ")"

  # Fetch using search API
  let q = Query(text: queryStr, kind: tweets)
  # We use the search API directly
  let searchResult = await getGraphTweetSearch(q, cursor)
  
  # Flatten threads into a single list of tweets for caching
  var allTweets: seq[Tweet] = @[]
  for thread in searchResult.content:
    for t in thread:
      allTweets.add t

  # Update the global feed cache with the results
  await updateGlobalFeed(allTweets, searchResult.bottom, sampled)
  
  # Return the searchResult cast to Timeline if necessary
  # For now, we'll return a new Timeline object
  result = Timeline(
    content: searchResult.content,
    beginning: searchResult.beginning,
    top: searchResult.top,
    bottom: searchResult.bottom,
    query: q
  )
