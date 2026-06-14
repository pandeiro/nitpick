# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, json, times, options
import jester
import router_utils
import ".."/[types, redis_cache, auth, feed]
import ../views/[general, stats]

proc collectFeedStats(): Future[JsonNode] {.async.} =
  let
    listNames = await getListNames()
    followingCount = (await getListMembers("default")).len
  var
    totalTweets = 0
    listsJson = newJArray()
    lastUpdated = ""

  for name in listNames:
    let feedData = await getListFeed(name)
    var tweets = 0
    var updated = ""
    if feedData.isSome:
      let f = feedData.get()
      tweets = f.tweetIds.len
      totalTweets += tweets
      updated = if f.lastUpdated > 0:
                  $fromUnix(f.lastUpdated).utc()
                else:
                  "never"
    else:
      updated = "never"
    listsJson.add(%*{
      "name": name,
      "members": (await getListMembers(name)).len,
      "tweets": tweets,
      "lastUpdated": updated
    })
    if name == "default":
      lastUpdated = updated

  result = %*{
    "tweetCount": totalTweets,
    "followingCount": followingCount,
    "lastUpdated": lastUpdated,
    "lists": listsJson
  }

template respStats*(cfg: Config) =
  let
    prefs = requestPrefs()
    feedStats = await collectFeedStats()
    poolHealth = getSessionPoolHealth()
    counters = await getStatsCounters()
    skipCounters = getSkipCountersJson()
  let statsJson = %*{
    "feed": feedStats,
    "sessions": poolHealth{"sessions"},
    "requests": poolHealth{"requests"},
    "counters": counters,
    "skipCounters": skipCounters
  }
  let html = renderStats(statsJson)
  resp renderMain(html, request, cfg, prefs, "Stats")

proc createStatsRouter*(cfg: Config) =
  router stats:
    get "/stats":
      respStats(cfg)
