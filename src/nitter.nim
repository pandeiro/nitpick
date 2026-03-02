# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, strformat, logging, os
from net import Port
from htmlgen import a
import karax/[karaxdsl, vdom]

import jester

import types, config, prefs, formatters, redis_cache, http_pool, auth, apiutils, feed
import views/[general, about, timeline]
import json_api
import routes/[
  preferences, timeline, status, media, search, rss, list, debug,
  unsupported, embed, resolver, router_utils, follow, pinned]

const instancesUrl = "https://github.com/zedeus/nitter/wiki/Instances"
const issuesUrl = "https://github.com/zedeus/nitter/issues"

let
  configPath = getEnv("NITTER_CONF_FILE", "./nitter.conf")
  (cfg, fullCfg) = getConfig(configPath)

  sessionsPath = getEnv("NITTER_SESSIONS_FILE", "./sessions.jsonl")

initSessionPool(cfg, sessionsPath)

# Configure structured logging
let logger = newConsoleLogger(fmtStr = "[$time] $levelid: ")
addHandler(logger)

if cfg.enableDebug:
  setLogFilter(lvlAll)
else:
  # Show info logs by default for better visibility of feed actions
  setLogFilter(lvlInfo)

stdout.write &"Starting Nitter at {getUrlPrefix(cfg)}\n"
stdout.flushFile

updateDefaultPrefs(fullCfg)
setCacheTimes(cfg)
setHmacKey(cfg.hmacKey)
setProxyEncoding(cfg.base64Media)
setMaxHttpConns(cfg.httpMaxConns)
setHttpProxy(cfg.proxy, cfg.proxyAuth)
setApiProxy(cfg.apiProxy)
setDisableTid(cfg.disableTid)
setMaxConcurrentReqs(cfg.maxConcurrentReqs)
initAboutPage(cfg.staticDir)

waitFor initRedisPool(cfg)
stdout.write &"Connected to Redis at {cfg.redisHost}:{cfg.redisPort}\n"
stdout.flushFile

createUnsupportedRouter(cfg)
createResolverRouter(cfg)
createPrefRouter(cfg)
createTimelineRouter(cfg)
createListRouter(cfg)
createStatusRouter(cfg)
createSearchRouter(cfg)
createMediaRouter(cfg)
createEmbedRouter(cfg)
createRssRouter(cfg)
createDebugRouter(cfg)
createFollowRouter(cfg)

settings:
  port = Port(cfg.port)
  staticDir = cfg.staticDir
  bindAddr = cfg.address
  reusePort = true

routes:
  error InternalError:
    let acceptJson = request.headers.getOrDefault("accept") == "application/json"
    if acceptJson:
      respJson(errorJson("INTERNAL_ERROR", "An internal error occurred."), Http500)
    echo error.exc.name, ": ", error.exc.msg
    const link = a("open a GitHub issue", href = issuesUrl)
    resp Http500, showError(
      &"An error occurred, please {link} with the URL you tried to visit.", cfg)

  error BadClientError:
    let acceptJson = request.headers.getOrDefault("accept") == "application/json"
    if acceptJson:
      respJson(errorJson("BAD_CLIENT", "Network error occurred."), Http500)
    echo error.exc.name, ": ", error.exc.msg
    resp Http500, showError("Network error occurred, please try again.", cfg)

  error RateLimitError:
    let acceptJson = request.headers.hasKey("accept") and request.headers["accept"] == "application/json" or
                     request.headers.hasKey("Accept") and request.headers["Accept"] == "application/json"
    if acceptJson:
      respJson(errorJson("RATE_LIMITED", "Instance has been rate limited."), Http429)
    const link = a("another instance", href = instancesUrl)
    resp Http429, showError(
      &"Instance has been rate limited.<br>Use {link} or try again later.", cfg)

  error NoSessionsError:
    echo "Request Headers: ", request.headers
    let acceptJson = request.headers.hasKey("accept") and request.headers["accept"] == "application/json" or
                     request.headers.hasKey("Accept") and request.headers["Accept"] == "application/json"
    if acceptJson:
      respJson(errorJson("RATE_LIMITED", "Instance has no auth tokens, or is fully rate limited."), Http429)
    const link = a("another instance", href = instancesUrl)
    resp Http429, showError(
      &"Instance has no auth tokens, or is fully rate limited.<br>Use {link} or try again later.", cfg)

  before:
    let acceptJson = request.headers.getOrDefault("accept") == "application/json"
    if acceptJson:
      let path = request.path
      if path == "/":
        let
          prefs = requestPrefs()
          listParam = @"list"
          listName = if listParam.len > 0: listParam else: "default"
          following = await getListMembers(listName)
          cursor = @"cursor"
        if following.len > 0:
          let timeline = await fetchFeed(following, prefs, cursor, prefs.feedStrategy, listName)
          respJson toJson(timeline)
        else:
          respJson emptyTimelineJson()
      
      if path.startsWith("/@") or (path.len > 1 and path[1] != 'i' and '/' notin path[1..^1]):
        let 
          name = if path.startsWith("/@"): path[2..^1] else: path[1..^1]
          tab = @"tab"
          prefs = requestPrefs()
          after = getCursor()
        
        var query = getQuery(request, tab, name)
        try:
          let profile = await fetchProfile(after, query)
          if profile.user.id.len == 0:
            respJson(errorJson("NOT_FOUND", "User not found"), Http404)
          respJson(toJson(profile, prefs))
        except RateLimitError:
          respJson(errorJson("RATE_LIMITED", "Instance has been rate limited."), Http429)
        except NoSessionsError:
          respJson(errorJson("RATE_LIMITED", "Instance has no auth tokens, or is fully rate limited."), Http429)
        except:
          let e = getCurrentException()
          respJson(errorJson("UNKNOWN_ERROR", $e.name & ": " & e.msg), Http500)

    # skip all file URLs
    cond "." notin request.path
    applyUrlPrefs()

  get "/favicon.ico":
    cond cfg.favicon != "favicon.ico" and fileExists(cfg.staticDir / cfg.favicon)
    sendFile(cfg.staticDir / cfg.favicon)

  get "/apple-touch-icon.png":
    cond cfg.favicon != "favicon.ico" and fileExists(cfg.staticDir / cfg.favicon)
    sendFile(cfg.staticDir / cfg.favicon)

  get "/favicon-32x32.png":
    cond cfg.favicon != "favicon.ico" and fileExists(cfg.staticDir / cfg.favicon)
    sendFile(cfg.staticDir / cfg.favicon)

  get "/favicon-16x16.png":
    cond cfg.favicon != "favicon.ico" and fileExists(cfg.staticDir / cfg.favicon)
    sendFile(cfg.staticDir / cfg.favicon)

  get "/android-chrome-192x192.png":
    cond cfg.favicon != "favicon.ico" and fileExists(cfg.staticDir / cfg.favicon)
    sendFile(cfg.staticDir / cfg.favicon)

  get "/android-chrome-384x384.png":
    cond cfg.favicon != "favicon.ico" and fileExists(cfg.staticDir / cfg.favicon)
    sendFile(cfg.staticDir / cfg.favicon)

  get "/android-chrome-512x512.png":
    cond cfg.favicon != "favicon.ico" and fileExists(cfg.staticDir / cfg.favicon)
    sendFile(cfg.staticDir / cfg.favicon)

  get "/pinned":
    let acceptJson = request.headers.hasKey("accept") and request.headers["accept"] == "application/json" or
                     request.headers.hasKey("Accept") and request.headers["Accept"] == "application/json"
    if acceptJson:
      let pinnedTweets = await getPinnedTweets()
      respJson(pinnedTweetsJson(pinnedTweets))
    else:
      respPinned(cfg)

  post "/pin":
    respPin(cfg)

  post "/unpin":
    respUnpin(cfg)

  get "/":
    let acceptJson = request.headers.getOrDefault("accept") == "application/json"
    let
      prefs = requestPrefs()
      listParam = @"list"
      listName = if listParam.len > 0: listParam else: "default"
      following = await getListMembers(listName)
      cursor = @"cursor"
      lists = await getListNames()
    if following.len > 0:
      let timeline = await fetchFeed(following, prefs, cursor, prefs.feedStrategy, listName)
      if acceptJson:
        respJson toJson(timeline)

      let tweets = renderTimelineTweets(timeline, prefs, "/", listName = listName)
      let body = buildHtml(tdiv(class="timeline-container")):
        tweets
      if @"scroll".len > 0:
        resp $body
      else:
        resp renderMain(body, request, cfg, prefs, listName = listName, lists = lists)
    else:
      if acceptJson:
        respJson emptyTimelineJson()

      resp renderMain(renderSearch(), request, cfg, prefs, listName = listName, lists = lists)

  get "/about":
    resp renderMain(renderAbout(), request, cfg, requestPrefs())

  get "/explore":
    redirect("/about")

  get "/help":
    redirect("/about")

  get "/i/redirect":
    let url = decodeUrl(@"url")
    if url.len == 0: resp Http404
    redirect(replaceUrls(url, requestPrefs()))

  error Http404:
    resp Http404, showError("Page not found", cfg)

  extend timeline, ""
  extend rss, ""
  extend status, ""
  extend search, ""
  extend media, ""
  extend list, ""
  extend preferences, ""
  extend resolver, ""
  extend embed, ""
  extend debug, ""
  extend unsupported, ""
  extend follow, ""
  extend pinned, ""
