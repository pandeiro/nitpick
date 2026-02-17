# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, strutils

import jester, karax/vdom

import router_utils
import ".."/[types, redis_cache]
import ../views/[general, pinned]

export pinned

proc createPinnedRouter*(cfg: Config) =
  router pinned:
    get "/pinned":
      let
        prefs = requestPrefs()
        pinnedTweets = await getPinnedTweets()
        html = renderPinned(pinnedTweets, prefs, getPath())
      resp renderMain(html, request, cfg, prefs, "Pinned Tweets")

    post "/pin":
      let tweetIdStr = @"tweetId"
      if tweetIdStr.len == 0:
        resp Http400, showError("Missing tweet ID", cfg)
      
      try:
        let tweetId = parseBiggestInt(tweetIdStr)
        # Fetch tweet data to store with pin
        let tweet = await getGraphTweetResult($tweetId)
        if tweet != nil and tweet.id != 0:
          discard await pinTweet(tweet)
      except:
        discard # Fail gracefully
      redirect(refPath())

    post "/unpin":
      let tweetIdStr = @"tweetId"
      if tweetIdStr.len == 0:
        resp Http400, showError("Missing tweet ID", cfg)
      
      try:
        let tweetId = parseBiggestInt(tweetIdStr)
        discard await unpinTweet(tweetId)
      except:
        discard # Fail gracefully
      redirect(refPath())
