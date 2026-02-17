# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, strutils

import jester, karax/vdom

import router_utils
import ".."/[types, redis_cache, api]
import ../views/[general, pinned]

export pinned

template respPinned*(cfg: Config) =
  let
    prefs = requestPrefs()
    pinnedTweets = await getPinnedTweets()
    html = renderPinned(pinnedTweets, prefs, getPath())
  resp renderMain(html, request, cfg, prefs, "Pinned Tweets")

template respPin*(cfg: Config) =
  let tweetIdStr = @"tweetId"
  if tweetIdStr.len == 0:
    resp Http400, showError("Missing tweet ID", cfg)
  
  try:
    let tweetId = parseBiggestInt(tweetIdStr)
    # Try fetching from cache first, then API
    let tweet = await getCachedTweet(tweetId)
    if tweet != nil and tweet.id != 0:
      if tweet.user.username.len > 0:
        await cacheUserId(tweet.user.username, tweet.user.id)
        await cache(tweet.user)
      discard await addPinnedTweet(tweet)
  except:
    discard # Fail gracefully
  redirect("/pinned")

template respUnpin*(cfg: Config) =
  let tweetIdStr = @"tweetId"
  if tweetIdStr.len == 0:
    resp Http400, showError("Missing tweet ID", cfg)
  
  try:
    let tweetId = parseBiggestInt(tweetIdStr)
    discard await removePinnedTweet(tweetId)
  except:
    discard # Fail gracefully
  redirect(refPath())

proc createPinnedRouter*(cfg: Config) =
  router pinned:
    get "/pinned":
      respPinned(cfg)

    post "/pin":
      respPin(cfg)

    post "/unpin":
      respUnpin(cfg)
