# SPDX-License-Identifier: AGPL-3.0-only
import strutils, uri, json

import jester

import router_utils
import ".."/[query, types, api, formatters, redis_cache, json_api]
import ../views/[general, search]

include "../views/opensearch.nimf"

export search

proc createSearchRouter*(cfg: Config) =
  router search:
    get "/search/?":
      let q = @"q"
      if q.len > 500:
        let acceptJson = acceptJson()
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Search input too long."), Http400)
        resp Http400, showError("Search input too long.", cfg)

      let
        prefs = requestPrefs()
        query = initQuery(params(request))
        title = "Search" & (if q.len > 0: " (" & q & ")" else: "")
        acceptJson = acceptJson()

      case query.kind
      of users:
        if "," in q:
          redirect("/" & q)
        var users: Result[User]
        try:
          users = await getGraphUserSearch(query, getCursor())
        except InternalError:
          users = Result[User](beginning: true, query: query)
        
        if acceptJson:
          respJson(toJson(users))
        else:
          resp renderMain(renderUserSearch(users, prefs), request, cfg, prefs, title)
      of tweets:
        let
          tweets = await getGraphTweetSearch(query, getCursor())
          rss = if cfg.enableRSSSearch: "/search/rss?" & genQueryUrl(query) else: ""
        await setPinnedStatus(tweets.content)
        
        if acceptJson:
          respJson(toJson(tweets))
        else:
          resp renderMain(renderTweetSearch(tweets, prefs, getPath()),
                          request, cfg, prefs, title, rss=rss)
      else:
        if acceptJson:
          respJson(errorJson("INVALID_REQUEST", "Invalid search"), Http404)
        resp Http404, showError("Invalid search", cfg)

    get "/hashtag/@hash":
      redirect("/search?f=tweets&q=" & encodeUrl("#" & @"hash"))

    get "/opensearch":
      let url = getUrlPrefix(cfg) & "/search?f=tweets&q="
      resp Http200, {"Content-Type": "application/opensearchdescription+xml"},
                     generateOpenSearchXML(cfg.title, cfg.hostname, url)
