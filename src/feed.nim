# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, options, logging, strutils, tables, times, json, random
import types, api, redis_cache

proc extractTweets(timeline: Timeline): seq[Tweet] =
  for thread in timeline.content:
    for t in thread:
      result.add t

const refreshBatchSize = 5

var skipCounters = initTable[string, int]()  # module-level: consecutive failures per user

# ---------------------------------------------------------------------------
# Cycle metrics — Phase 1: Worker Metrics & Status Endpoint
# ---------------------------------------------------------------------------

type CycleMetrics* = object
  startTime*: float        # epoch seconds
  duration*: float         # seconds (0 for in-progress cycle)
  usersFetched*: int
  tweetsFetched*: int
  tweetsNew*: int          # after dedup against current feed
  errors*: int
  rateLimitsHit*: int
  listsRefreshed*: seq[string]

var
  currentCycle* {.threadvar.}: Option[CycleMetrics]
  lastCycle* {.threadvar.}: Option[CycleMetrics]
  cycleHistory* {.threadvar.}: seq[CycleMetrics]
  forceRefreshFlag* {.threadvar.}: bool

const maxCycleHistory* = 20

proc triggerFeedRefresh*() =
  ## Signal the background worker to start the next cycle immediately.
  forceRefreshFlag = true
  info "[feed-refresher] Force refresh requested."

proc toJson*(cm: CycleMetrics): JsonNode =
  result = %*{
    "start_time": cm.startTime,
    "duration_seconds": cm.duration,
    "users_fetched": cm.usersFetched,
    "tweets_fetched": cm.tweetsFetched,
    "tweets_new": cm.tweetsNew,
    "errors": cm.errors,
    "rate_limits_hit": cm.rateLimitsHit,
    "lists": cm.listsRefreshed
  }

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

  # Track per-list metrics
  var listUsersFetched = 0
  var listTweetsFetched = 0
  var listTweetsNew = 0
  var listErrors = 0
  var listRateLimits = 0

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
        inc listUsersFetched
        skipCounters.del(batchUsers[i])  # success — reset counter
      except RateLimitError:
        inc listRateLimits
        skipCounters[batchUsers[i]] = skipCounters.getOrDefault(batchUsers[i], 0) + 1
        warn "[feed-refresher] Rate limited fetching '", batchUsers[i], "': ", getCurrentException().msg
      except CatchableError as e:
        inc listErrors
        skipCounters[batchUsers[i]] = skipCounters.getOrDefault(batchUsers[i], 0) + 1
        let failures = skipCounters[batchUsers[i]]
        if failures >= 3:
          warn "[feed-refresher] Skipping '", batchUsers[i], "' for ~10 cycles (", failures, " failures): ", e.msg
        else:
          warn "[feed-refresher] Fetch failed for '", batchUsers[i], "' (", failures, "/3): ", e.msg

    if batchTweets.len > 0:
      inc listTweetsFetched, batchTweets.len
      await cache(batchTweets)
      let newCount = await updateListFeed(listName, batchTweets)
      inc listTweetsNew, newCount
      info "[feed-refresher] Accumulated ", batchTweets.len, " tweets (", newCount, " new) for '", listName, "'"

  # Update current cycle metrics with this list's contribution
  if currentCycle.isSome:
    var c = currentCycle.get()
    c.usersFetched += listUsersFetched
    c.tweetsFetched += listTweetsFetched
    c.tweetsNew += listTweetsNew
    c.errors += listErrors
    c.rateLimitsHit += listRateLimits
    c.listsRefreshed.add(listName)
    currentCycle = some(c)

proc refreshAllLists*() {.async.} =
  ## Refresh all follow lists. Exported for testing.
  let lists = await getListNames()
  if lists.len == 0:
    return

  # Initialize cycle metrics
  currentCycle = some(CycleMetrics(
    startTime: epochTime(),
    duration: 0.0,
    usersFetched: 0,
    tweetsFetched: 0,
    tweetsNew: 0,
    errors: 0,
    rateLimitsHit: 0,
    listsRefreshed: @[]
  ))

  for listName in lists:
    await refreshListFeed(listName)

  # Finalize cycle
  if currentCycle.isSome:
    var c = currentCycle.get()
    c.duration = epochTime() - c.startTime
    lastCycle = some(c)
    # Add to rolling history (capped at maxCycleHistory)
    cycleHistory.add(c)
    if cycleHistory.len > maxCycleHistory:
      cycleHistory = cycleHistory[(cycleHistory.len - maxCycleHistory) .. ^1]
    # Persist to Redis (survives restart)
    await saveCycleMetrics($c.toJson())
    info "[feed-refresher] Cycle complete: ", c.usersFetched, " users, ",
         c.tweetsFetched, " tweets (", c.tweetsNew, " new), ",
         c.errors, " errors, ", c.rateLimitsHit, " rate limits in ",
         c.duration.formatFloat(ffDecimal, 1), "s"
  else:
    info "[feed-refresher] No lists to refresh."

  currentCycle = none(CycleMetrics)

proc loadPersistedCycleMetrics*() {.async.} =
  ## On startup, restore lastCycle from Redis (if available).
  let jsonStr = await loadCycleMetrics()
  if jsonStr.len > 0:
    try:
      let node = parseJson(jsonStr)
      var cm: CycleMetrics
      cm.startTime = node{"start_time"}.getFloat()
      cm.duration = node{"duration_seconds"}.getFloat()
      cm.usersFetched = node{"users_fetched"}.getInt()
      cm.tweetsFetched = node{"tweets_fetched"}.getInt()
      cm.tweetsNew = node{"tweets_new"}.getInt()
      cm.errors = node{"errors"}.getInt()
      cm.rateLimitsHit = node{"rate_limits_hit"}.getInt()
      if node.kind == JObject and "lists" in node:
        for l in node{"lists"}.items:
          cm.listsRefreshed.add(l.getStr())
      lastCycle = some(cm)
      info "[feed-refresher] Restored last cycle metrics from Redis."
    except:
      warn "[feed-refresher] Failed to restore cycle metrics from Redis."

proc startBurstRefresher*(intervalSeconds: int) {.async.} =
  ## Burst mode: fetch all users, sleep, repeat.
  ## Call from startFeedRefresher when staggeredRefresh is disabled.

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

    # Check force-refresh flag — if set, skip the sleep and go again
    if forceRefreshFlag:
      forceRefreshFlag = false
      info "[feed-refresher] Force refresh flag set, starting next cycle immediately."
      continue

proc startStaggeredRefresher*(intervalSeconds: int) {.async.} =
  ## Rolling/staggered refresh: spread per-user fetches across the interval
  ## instead of fetching all users in a burst and then sleeping. This keeps
  ## the feed continuously fresh and avoids hammering the API with 106
  ## parallel requests at once.
  ##
  ## On each cycle: collects all (listName, username) pairs, shuffles them,
  ## processes in batches of `refreshBatchSize`, and sleeps `staggerMs`
  ## between batches so the full sweep takes ~intervalSeconds.
  ##
  ## Supports force-refresh (POST /feed/refresh) to reset the rolling cycle.

  while true:
    let cycleStart = epochTime()

    # Collect all (listName, username) pairs across all lists
    let lists = await getListNames()
    var allPairs: seq[(string, string)]
    for listName in lists:
      for username in await getListMembers(listName):
        allPairs.add((listName, username))

    if allPairs.len == 0:
      await sleepAsync(intervalSeconds * 1000)
      continue

    allPairs.shuffle()
    let batches = allPairs.chunked(refreshBatchSize)
    let numBatches = batches.len

    # Stagger time per batch (ms). Minimum 3s to avoid hammering the API.
    let staggerMs = max((intervalSeconds * 1000) div numBatches, 3000)

    # Initialize cycle metrics
    currentCycle = some(CycleMetrics(
      startTime: epochTime(),
      duration: 0.0,
      usersFetched: 0,
      tweetsFetched: 0,
      tweetsNew: 0,
      errors: 0,
      rateLimitsHit: 0,
      listsRefreshed: @[]
    ))

    var allListsTouched: seq[string] = @[]

    for batchIdx, batch in batches:
      # Check force refresh — restart the cycle immediately
      if forceRefreshFlag:
        forceRefreshFlag = false
        info "[feed-refresher] Force refresh during rolling cycle."
        break

      # Group fetched tweets by list name for per-list Redis accumulation
      var batchTweetsByList = initTable[string, seq[Tweet]]()

      for (listName, username) in batch:
        if skipCounters.getOrDefault(username, 0) >= 3:
          continue

        let userId = await getUserId(username)
        if userId.len == 0 or userId == "suspended":
          continue

        try:
          let profile = await getGraphUserTweets(userId, TimelineKind.tweets)
          let tweets = profile.tweets.extractTweets()
          if tweets.len > 0:
            batchTweetsByList.mgetOrPut(listName, @[]).add(tweets)
            await cache(tweets)
          skipCounters.del(username)  # success — reset counter

          if currentCycle.isSome:
            var c = currentCycle.get()
            inc c.usersFetched
            c.tweetsFetched += tweets.len
            currentCycle = some(c)

        except RateLimitError:
          if currentCycle.isSome:
            var c = currentCycle.get()
            inc c.rateLimitsHit
            currentCycle = some(c)
          skipCounters[username] = skipCounters.getOrDefault(username, 0) + 1
          warn "[feed-refresher] Rate limited fetching '", username, "': ", getCurrentException().msg
        except CatchableError as e:
          if currentCycle.isSome:
            var c = currentCycle.get()
            inc c.errors
            currentCycle = some(c)
          skipCounters[username] = skipCounters.getOrDefault(username, 0) + 1
          if skipCounters[username] >= 3:
            warn "[feed-refresher] Skipping '", username, "' (~10 cycles): ", e.msg
          else:
            warn "[feed-refresher] Fetch failed for '", username, "' (", skipCounters[username], "/3): ", e.msg

      # Accumulate tweets per list to Redis
      for listName, tweets in batchTweetsByList:
        let newCount = await updateListFeed(listName, tweets)
        if currentCycle.isSome:
          var c = currentCycle.get()
          c.tweetsNew += newCount
          currentCycle = some(c)
        if listName notin allListsTouched:
          allListsTouched.add(listName)
        info "[feed-refresher] Accumulated ", tweets.len, " tweets (", newCount, " new) for '", listName, "'"

      # Sleep between batches (not after last)
      if batchIdx < numBatches - 1:
        await sleepAsync(staggerMs)

    # Decay skip counters after each full sweep
    for user, count in skipCounters.mpairs:
      if count >= 3:
        skipCounters[user] = count - 1

    # Finalize cycle metrics
    if currentCycle.isSome:
      var c = currentCycle.get()
      c.duration = epochTime() - c.startTime
      c.listsRefreshed = allListsTouched
      lastCycle = some(c)
      cycleHistory.add(c)
      if cycleHistory.len > maxCycleHistory:
        cycleHistory = cycleHistory[(cycleHistory.len - maxCycleHistory) .. ^1]
      await saveCycleMetrics($c.toJson())

      info "[feed-refresher] Rolling cycle: ", c.usersFetched, " users, ",
           c.tweetsFetched, " tweets (", c.tweetsNew, " new), ",
           c.errors, " errors, ", c.rateLimitsHit, " rate limits in ",
           c.duration.formatFloat(ffDecimal, 1), "s"

    currentCycle = none(CycleMetrics)

    # If force-refreshed, restart immediately
    if forceRefreshFlag:
      forceRefreshFlag = false
      continue

    # If the cycle finished before the interval, sleep the remainder
    let elapsed = epochTime() - cycleStart
    if elapsed < intervalSeconds.float:
      let remainingMs = int((intervalSeconds.float - elapsed) * 1000)
      await sleepAsync(remainingMs)

proc startFeedRefresher*(intervalSeconds: int; staggered: bool) {.async.} =
  ## Background loop entry point. Dispatches to burst or staggered mode.
  ## Call from nitter.nim after Redis init.

  # Restore last cycle metrics from Redis (survives restart)
  await loadPersistedCycleMetrics()

  # Immediate seed — populate feed cache within seconds of startup
  info "[feed-refresher] Starting initial feed refresh..."
  await refreshAllLists()
  info "[feed-refresher] Initial refresh complete."

  if staggered:
    info "[feed-refresher] Entering rolling/staggered refresh mode (interval=", intervalSeconds, "s)"
    await startStaggeredRefresher(intervalSeconds)
  else:
    info "[feed-refresher] Entering burst refresh mode (interval=", intervalSeconds, "s)"
    await startBurstRefresher(intervalSeconds)

proc refreshRespJson*(): JsonNode =
  result = newJObject()
  result["status"] = newJString("refresh_triggered")

proc buildFeedStatusJson*(): Future[JsonNode] {.async.} =
  ## Build the JSON response for GET /feed/status.
  result = %*{"worker": "running"}

  # --- Cycle metrics ---
  var cycleJson = newJObject()

  if currentCycle.isSome:
    let c = currentCycle.get()
    cycleJson["current"] = %*{
      "elapsed_seconds": epochTime() - c.startTime,
      "users_fetched": c.usersFetched,
      "tweets_fetched": c.tweetsFetched,
      "tweets_new": c.tweetsNew,
      "errors": c.errors,
      "rate_limits_hit": c.rateLimitsHit,
      "lists": c.listsRefreshed
    }

  if lastCycle.isSome:
    let lc = lastCycle.get()
    cycleJson["last"] = %*{
      "duration_seconds": lc.duration,
      "users_fetched": lc.usersFetched,
      "tweets_fetched": lc.tweetsFetched,
      "tweets_new": lc.tweetsNew,
      "errors": lc.errors,
      "rate_limits_hit": lc.rateLimitsHit,
      "completed_at": $fromUnix(lc.startTime.int),
      "lists": lc.listsRefreshed
    }

  if cycleHistory.len > 0:
    var historyArr = newJArray()
    for cm in cycleHistory:
      historyArr.add(cm.toJson())
    cycleJson["history"] = historyArr

  result["cycle"] = cycleJson

  # --- Per-list info ---
  var listsArr = newJArray()
  let listNames = await getListNames()
  for name in listNames:
    let members = await getListMembers(name)
    let fopt = await getListFeed(name)
    var listObj = %*{
      "name": name,
      "members": members.len
    }
    if fopt.isSome:
      let f = fopt.get()
      listObj["tweet_ids_cached"] = %(f.tweetIds.len)
      listObj["feed_age_seconds"] = %(int(epochTime()) - f.lastUpdated)
    else:
      listObj["tweet_ids_cached"] = %(0)
      listObj["feed_age_seconds"] = %(-1)
    listsArr.add(listObj)

  result["lists"] = listsArr

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

# ---------------------------------------------------------------------------
# HTML status page (used by GET /feed/status for browser requests)
# ---------------------------------------------------------------------------

proc renderStatusPage*(statusJson: JsonNode): string =
  ## Render the /feed/status endpoint as an HTML dashboard for browser users.
  let worker = statusJson{"worker"}.getStr("unknown")

  template section(title: string; body: string): string =
    "<hr><h2>" & title & "</h2>" & body

  proc card(label, value, unit: string): string =
    "<div class=\"metric-card\"><span class=\"metric-value\">" & value & "</span><span class=\"metric-label\">" & label & "</span>" &
    (if unit.len > 0: "<span class=\"metric-unit\">" & unit & "</span>" else: "") & "</div>"

  proc hasKey(node: JsonNode; key: string): bool =
    node.kind == JObject and key in node

  proc cycleHtml(title: string; cycle: JsonNode): string =
    result = "<div class=\"cycle-section\"><h3>" & title & "</h3>"
    if cycle.isNil or cycle.kind == JNull:
      result.add("<p class=\"dim\">No data</p>")
    else:
      result.add("<div class=\"metric-grid\">")
      result.add(card("Users", $cycle{"users_fetched"}.getInt(), "fetched"))
      result.add(card("Tweets", $cycle{"tweets_fetched"}.getInt(), "fetched"))
      result.add(card("New", $cycle{"tweets_new"}.getInt(), "new"))
      result.add(card("Errors", $cycle{"errors"}.getInt(), ""))
      result.add(card("Rate Limits", $cycle{"rate_limits_hit"}.getInt(), ""))
      if hasKey(cycle, "duration_seconds"):
        result.add(card("Duration", $cycle{"duration_seconds"}.getFloat() & "s", ""))
      if hasKey(cycle, "elapsed_seconds"):
        result.add(card("Elapsed", $cycle{"elapsed_seconds"}.getFloat() & "s", ""))
      if hasKey(cycle, "completed_at"):
        result.add(card("Completed", cycle{"completed_at"}.getStr(), ""))
      if hasKey(cycle, "lists") and cycle{"lists"}.kind == JArray:
        let listArr = cycle{"lists"}
        var listsStr = ""
        for idx in 0 ..< listArr.len:
          if idx > 0: listsStr.add(", ")
          listsStr.add(listArr[idx].getStr())
        if listsStr.len > 0:
          result.add(card("Lists", listsStr, ""))
      result.add("</div>")
    result.add("</div>")

  proc listRow(name: string; members, tweetsCached, ageSeconds: int): string =
    let ageStr = if ageSeconds < 0: "never"
                 elif ageSeconds < 60: $ageSeconds & "s"
                 elif ageSeconds < 3600: $(ageSeconds div 60) & "m"
                 elif ageSeconds < 86400: $(ageSeconds div 3600) & "h"
                 else: $(ageSeconds div 86400) & "d"
    "<tr><td>" & name & "</td><td>" & $members & "</td><td>" & $tweetsCached & "</td><td>" & ageStr & "</td></tr>"

  # Extract data from JSON
  var
    currentCycle: JsonNode = nil
    lastCycle: JsonNode = nil
    history: JsonNode = nil
    sessions: JsonNode = nil
    lists: JsonNode = nil

  if hasKey(statusJson, "cycle"):
    let c = statusJson{"cycle"}
    if hasKey(c, "current"): currentCycle = c{"current"}
    if hasKey(c, "last"): lastCycle = c{"last"}
    if hasKey(c, "history"): history = c{"history"}

  if hasKey(statusJson, "sessions"): sessions = statusJson{"sessions"}
  if hasKey(statusJson, "lists"): lists = statusJson{"lists"}

  # Build history HTML
  var historyHtml = ""
  if not history.isNil and history.kind == JArray and history.len > 0:
    historyHtml = section("Cycle History", "<div class=\"metric-grid\">")
    let startIdx = max(0, history.len - 6)
    for i in countdown(history.len - 1, startIdx):
      let h = history[i]
      let completed = if hasKey(h, "completed_at"): h{"completed_at"}.getStr() else: "?"
      historyHtml.add("<div class=\"history-entry\"><strong>" & completed & "</strong> - " &
        $h{"users_fetched"}.getInt() & " users, " & $h{"tweets_fetched"}.getInt() & " tweets (" &
        $h{"tweets_new"}.getInt() & " new), " & $h{"errors"}.getInt() & " err</div>")
    historyHtml.add("</div>")

  # Build sessions HTML
  var sessionsHtml = section("Session Rate Limits", "")
  if not sessions.isNil:
    sessionsHtml.add("<div class=\"metric-grid\">")
    if hasKey(sessions, "total"):
      sessionsHtml.add(card("Sessions", $sessions{"total"}.getInt(), "total"))
    if hasKey(sessions, "limited"):
      sessionsHtml.add(card("Limited", $sessions{"limited"}.getInt(), "sessions"))
    sessionsHtml.add("</div>")
  else:
    sessionsHtml.add("<p class=\"dim\">No session data</p>")

  # Build lists HTML
  var listsHtml = section("Following Lists", "")
  if not lists.isNil and lists.kind == JArray:
    listsHtml.add("<table class=\"pref-table\"><thead><tr><th>List</th><th>Members</th><th>Tweets Cached</th><th>Feed Age</th></tr></thead><tbody>")
    for idx in 0 ..< lists.len:
      let l = lists[idx]
      if hasKey(l, "name") and hasKey(l, "members"):
        listsHtml.add(listRow(l{"name"}.getStr(), l{"members"}.getInt(), l{"tweet_ids_cached"}.getInt(), l{"feed_age_seconds"}.getInt()))
    listsHtml.add("</tbody></table>")
  else:
    listsHtml.add("<p class=\"dim\">No lists</p>")

  let workerBadgeClass = if worker == "running": "ok" else: "warn"

  result = "<!DOCTYPE html>\n" &
    "<html lang=\"en\">\n<head>\n" &
    "<title>Feed Status | Nitter</title>\n" &
    "<link rel=\"stylesheet\" type=\"text/css\" href=\"/css/style.css?v=28\">\n" &
    "<link rel=\"stylesheet\" type=\"text/css\" href=\"/css/fontello.css?v=4\">\n" &
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n" &
    "</head>\n<body>\n" &
    "<div class=\"container\"><div class=\"panel-container\"><div class=\"preferences-container\">\n" &
    "<h1>Feed Worker Status</h1>\n" &
    "<div class=\"worker-badge " & workerBadgeClass & "\">Worker: " & worker & "</div>\n" &
    section("Current Cycle", cycleHtml("In Progress", currentCycle)) & "\n" &
    section("Last Completed Cycle", cycleHtml("Completed", lastCycle)) & "\n" &
    historyHtml & "\n" &
    sessionsHtml & "\n" &
    listsHtml & "\n" &
    "<hr>\n" &
    "<a href=\"/\" class=\"feed-status-back\">&lt;- Back to feed</a> | " &
    "<a href=\"/feed/status\" class=\"feed-status-refresh\">Refresh status</a>\n" &
    "</div></div></div>\n</body>\n</html>"
