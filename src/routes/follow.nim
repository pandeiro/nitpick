# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, strutils, tables, json

import jester

import router_utils
import ".."/[types, redis_cache, json_api]
import ../views/[general, following]

export following

proc createFollowRouter*(cfg: Config) =
  router follow:
    get "/following":
      let
        prefs = requestPrefs()
        listNames = await getListNames()
      var listsData = initTable[string, seq[string]]()
      for name in listNames:
        listsData[name] = await getListMembers(name)
      
      let acceptJson = request.headers.hasKey("accept") and request.headers["accept"] == "application/json" or
                       request.headers.hasKey("Accept") and request.headers["Accept"] == "application/json"
      
      if acceptJson:
        respJson(toJson(listNames, listsData))
      else:
        let html = renderFollowing(listNames, listsData)
        resp renderMain(html, request, cfg, prefs, "Following", lists = listNames)

    post "/follow":
      let
        username = @"username"
        listName = if @"list".len > 0: @"list" else: "default"
      if username.len == 0:
        let acceptJson = request.headers.hasKey("accept") and request.headers["accept"] == "application/json" or
                         request.headers.hasKey("Accept") and request.headers["Accept"] == "application/json"
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Missing username"), Http400)
        else:
          resp Http400, showError("Missing username", cfg)
      else:
        discard await addToList(listName, username)
        let acceptJson = request.headers.hasKey("accept") and request.headers["accept"] == "application/json" or
                         request.headers.hasKey("Accept") and request.headers["Accept"] == "application/json"
        if acceptJson:
          respJson(actionResponseJson(true, "follow", username, listName))
        else:
          redirect(refPath())

    post "/unfollow":
      let
        username = @"username"
        listName = if @"list".len > 0: @"list" else: "default"
      if username.len == 0:
        let acceptJson = request.headers.hasKey("accept") and request.headers["accept"] == "application/json" or
                         request.headers.hasKey("Accept") and request.headers["Accept"] == "application/json"
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Missing username"), Http400)
        else:
          resp Http400, showError("Missing username", cfg)
      else:
        discard await removeFromList(listName, username)
        let acceptJson = request.headers.hasKey("accept") and request.headers["accept"] == "application/json" or
                         request.headers.hasKey("Accept") and request.headers["Accept"] == "application/json"
        if acceptJson:
          respJson(actionResponseJson(true, "unfollow", username, listName))
        else:
          redirect(refPath())

    post "/lists/create":
      let name = @"name"
      if name.len == 0:
        resp Http400, showError("Missing list name", cfg)
      if name == "default":
        resp Http400, showError("Cannot create list named 'default'", cfg)
      discard await createList(name)
      redirect("/following")

    post "/lists/delete":
      let name = @"name"
      if name.len == 0:
        resp Http400, showError("Missing list name", cfg)
      if name == "default":
        resp Http400, showError("Cannot delete default list", cfg)
      discard await deleteList(name)
      redirect("/following")

    post "/lists/rename":
      let
        oldName = @"old_name"
        newName = @"new_name"
      if oldName.len == 0 or newName.len == 0:
        resp Http400, showError("Missing list name", cfg)
      if oldName == "default" or newName == "default":
        resp Http400, showError("Cannot rename default list", cfg)
      discard await renameList(oldName, newName)
      redirect("/following")
