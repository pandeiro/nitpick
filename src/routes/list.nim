# SPDX-License-Identifier: AGPL-3.0-only
import strutils, strformat, uri
import karax/[karaxdsl, vdom]
import json

import jester

import router_utils
import ".."/[types, redis_cache, api, json_api]
import ../views/[general, timeline, list]

template respList*(list, timeline, title, vnode: typed) =
  if list.id.len == 0 or list.name.len == 0:
    resp Http404, showError(&"""List "{@"id"}" not found""", cfg)

  let
    html = renderList(vnode, timeline.query, list)
    rss = if cfg.enableRSSList: &"""/i/lists/{@"id"}/rss""" else: ""

  resp renderMain(html, request, cfg, prefs, titleText=title, rss=rss, banner=list.banner)

proc title*(list: List): string =
  &"@{list.username}/{list.name}"

proc createListRouter*(cfg: Config) =
  proc listMembersJson(list: List; members: Result[User]): JsonNode =
    var membersArr = newJArray()
    for user in members.content:
      membersArr.add(toJson(user))
    let listObj = newJObject()
    listObj["id"] = %list.id
    listObj["name"] = %list.name
    listObj["description"] = %list.description
    listObj["members"] = %list.members
    listObj["username"] = %list.username
    result = newJObject()
    result["list"] = listObj
    result["members"] = membersArr

  router list:
    get "/@name/lists/?":
      cond '.' notin @"name"
      cond @"name" != "i"
      let
        username = @"name"
        userLists = await getUserLists(username)
        pageTitle = &"@{username}/lists"

      let acceptJson = acceptJson()

      if acceptJson:
        respJson(toJson(username, userLists))
      else:
        var listsHtml = buildHtml(tdiv(class="timeline-container")):
          tdiv(class="timeline-header"):
            text pageTitle
          if userLists.len == 0:
            tdiv(class="timeline-description"):
              text "No lists found"
          else:
            ul(class="list-members"):
              for listName in userLists:
                li:
                  a(href=("/i/lists/" & listName)):
                    text listName
        resp renderMain(listsHtml, request, cfg, requestPrefs(), titleText=pageTitle)

    get "/@name/lists/@slug/?":
      cond '.' notin @"name"
      cond @"name" != "i"
      cond @"slug" != "memberships"
      let
        slug = decodeUrl(@"slug")
        list = await getCachedList(@"name", slug)
      if list.id.len == 0:
        resp Http404, showError(&"""List "{@"slug"}" not found""", cfg)
      redirect(&"/i/lists/{list.id}")

    get "/i/lists/@id/?":
      cond '.' notin @"id"
      let
        prefs = requestPrefs()
        list = await getCachedList(id=(@"id"))
        timeline = await getGraphListTweets(list.id, getCursor())
      await setPinnedStatus(timeline.content)
      
      let acceptJson = acceptJson()
      
      if acceptJson:
        if list.id.len == 0 or list.name.len == 0:
          respJson(errorJson("NOT_FOUND", &"List '{@\"id\"}' not found"), Http404)
        else:
          respJson(toJson(list, timeline))
      else:
        let vnode = renderTimelineTweets(timeline, prefs, request.path)
        respList(list, timeline, list.title, vnode)

    get "/i/lists/@id/members":
      cond '.' notin @"id"
      let
        prefs = requestPrefs()
        list = await getCachedList(id=(@"id"))
        members = await getGraphListMembers(list, getCursor())

      let acceptJson = acceptJson()

      if acceptJson:
        if list.id.len == 0 or list.name.len == 0:
          respJson(errorJson("NOT_FOUND", &"List '{@\"id\"}' not found"), Http404)
        else:
          respJson(toJson(list, members))
      else:
        respList(list, members, list.title, renderTimelineUsers(members, prefs, request.path))
