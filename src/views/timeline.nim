# SPDX-License-Identifier: AGPL-3.0-only
import strutils, strformat, algorithm, uri, options, times
import karax/[karaxdsl, vdom, vstyles]

import ".."/[types, query, formatters]
import tweet, renderutils

proc getQuery(query: Query): string =
  if query.kind != posts:
    result = genQueryUrl(query)
  if result.len > 0:
    result &= "&"

proc renderToTop*(focus="#"): VNode =
  buildHtml(tdiv(class="top-ref")):
    icon "down", href=focus

proc renderNewer*(query: Query; path: string; focus=""; listName = "default"): VNode =
  let
    q = genQueryUrl(query)
    listParam = if listName != "default": "list=" & encodeUrl(listName, usePlus=false) else: ""
    url = if q.len > 0 and listParam.len > 0: "?" & q & listParam
          elif q.len > 0: "?" & q
          elif listParam.len > 0: "?" & listParam
          else: ""
    p = if focus.len > 0: path.replace("#m", focus) else: path
  buildHtml(nav(class="timeline-item show-more")):
    a(href=(p & url)):
      text "Load newest"

proc renderMore*(query: Query; cursor: string; focus=""; listName = "default"): VNode =
  let
    listParam = if listName != "default": "&list=" & encodeUrl(listName, usePlus=false) else: ""
  buildHtml(nav(class="show-more")):
    a(href=(&"?{getQuery(query)}cursor={encodeUrl(cursor, usePlus=false)}{listParam}{focus}")):
      text "Load more"

proc renderNoMore(): VNode =
  buildHtml(footer(class="timeline-footer")):
    h2(class="timeline-end"):
      text "No more items"

proc renderNoneFound(): VNode =
  buildHtml(header(class="timeline-header")):
    h2(class="timeline-none"):
      text "No items found"

proc renderThread(thread: Tweets; prefs: Prefs; path: string): VNode =
  buildHtml(tdiv(class="thread-line")):
    let sortedThread = thread.sortedByIt(it.id)
    for i, tweet in sortedThread:
      if i > 0 and tweet.replyId != sortedThread[i - 1].id:
        tdiv(class="timeline-item thread more-replies-thread"):
          tdiv(class="more-replies"):
            a(class="more-replies-text", href=getLink(tweet)):
              text "more replies"

      let show = i == thread.high and sortedThread[0].id != tweet.threadId
      let header = if tweet.pinned or tweet.retweet.isSome: "with-header " else: ""
      renderTweet(tweet, prefs, path, class=(header & "thread"),
                  index=i, last=(i == thread.high))

proc renderUser(user: User; prefs: Prefs): VNode =
  buildHtml(tdiv(class="timeline-item", data-username=user.username)):
    a(class="tweet-link", href=("/" & user.username))
    tdiv(class="tweet-body profile-result"):
      tdiv(class="tweet-header"):
        a(class="tweet-avatar", href=("/" & user.username)):
          genImg(user.getUserPic("_bigger"), class=prefs.getAvatarClass)

        tdiv(class="tweet-name-row"):
          tdiv(class="fullname-and-username"):
            linkUser(user, class="fullname")
            verifiedIcon(user)
        linkUser(user, class="username")

      tdiv(class="tweet-content media-body", dir="auto"):
        verbatim replaceUrls(user.bio, prefs)

proc renderTimelineUsers*(results: Result[User]; prefs: Prefs; path=""): VNode =
  buildHtml(tdiv(class="timeline")):
    if not results.beginning:
      renderNewer(results.query, path)

    if results.content.len > 0:
      for user in results.content:
        renderUser(user, prefs)
      if results.bottom.len > 0:
        renderMore(results.query, results.bottom)
      renderToTop()
    elif results.beginning:
      renderNoneFound()
    else:
      renderNoMore()

proc renderFeedHeader*(results: Timeline; listName = "default"): VNode =
  let displayName = if listName == "default": "Default" else: listName
  let feedAge = if results.lastUpdated > 0:
    let now = epochTime().int
    let age = now - results.lastUpdated
    if age < 60:
      $age & "s ago"
    elif age < 3600:
      $(age div 60) & "m ago"
    else:
      $(age div 3600) & "h ago"
  else:
    "never"
  buildHtml(header(class="feed-header")):
    tdiv(class="feed-header-info"):
      span:
        text "Feed - " & displayName & " (" & $results.sampledCount & "/" & $results.followingCount & ")"
    tdiv(class="feed-header-age"):
      span(class="feed-age-badge"):
        text "updated " & feedAge
      form(`method`="post", action="/feed/refresh", class="feed-refresh-form"):
        button(`type`="submit", class="feed-refresh-btn", title="Refresh now"):
          text "↻"

proc renderTimelineTweets*(results: Timeline; prefs: Prefs; path: string;
                           pinned=none(Tweet); listName = "default"): VNode =
  buildHtml(tdiv(class="timeline")):
    if results.followingCount > 0:
      renderFeedHeader(results, listName)
    if not results.beginning:
      renderNewer(results.query, parseUri(path).path, listName = listName)

    if not prefs.hidePins and pinned.isSome:
      let tweet = get pinned
      renderTweet(tweet, prefs, path)

    if results.content.len == 0:
      if not results.beginning:
        renderNoMore()
      else:
        renderNoneFound()
    else:
      var retweets: seq[int64]

      for thread in results.content:
        if thread.len == 1:
          let
            tweet = thread[0]
            retweetId = if tweet.retweet.isSome: get(tweet.retweet).id else: 0

          if retweetId in retweets or tweet.id in retweets or
             tweet.pinned and prefs.hidePins:
            continue

          if retweetId != 0 and tweet.retweet.isSome:
            retweets &= retweetId
          renderTweet(tweet, prefs, path)
        else:
          renderThread(thread, prefs, path)

      if results.bottom.len > 0:
        renderMore(results.query, results.bottom, listName = listName)
      renderToTop()
