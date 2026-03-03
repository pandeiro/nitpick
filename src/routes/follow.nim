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
      
      let acceptJson = acceptJson()
      
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
        let acceptJson = acceptJson()
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Missing username"), Http400)
        else:
          resp Http400, showError("Missing username", cfg)
      else:
        discard await addToList(listName, username)
        let acceptJson = acceptJson()
        if acceptJson:
          respJson(actionResponseJson(true, "follow", username, listName))
        else:
          redirect(refPath())

    post "/unfollow":
      let
        username = @"username"
        listName = if @"list".len > 0: @"list" else: "default"
      if username.len == 0:
        let acceptJson = acceptJson()
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Missing username"), Http400)
        else:
          resp Http400, showError("Missing username", cfg)
      else:
        discard await removeFromList(listName, username)
        let acceptJson = acceptJson()
        if acceptJson:
          respJson(actionResponseJson(true, "unfollow", username, listName))
        else:
          redirect(refPath())

    post "/lists/create":
      let name = @"name"
      let acceptJson = acceptJson()
      if name.len == 0:
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Missing list name"), Http400)
        else:
          resp Http400, showError("Missing list name", cfg)
        return
      if name == "default":
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Cannot create list named 'default'"), Http400)
        else:
          resp Http400, showError("Cannot create list named 'default'", cfg)
        return
      discard await createList(name)
      if acceptJson:
        respJson(actionResponseJson(true, "create_list", name, ""))
      else:
        redirect("/following")

    post "/lists/delete":
      let name = @"name"
      let acceptJson = acceptJson()
      if name.len == 0:
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Missing list name"), Http400)
        else:
          resp Http400, showError("Missing list name", cfg)
        return
      if name == "default":
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Cannot delete default list"), Http400)
        else:
          resp Http400, showError("Cannot delete default list", cfg)
        return
      discard await deleteList(name)
      if acceptJson:
        respJson(actionResponseJson(true, "delete_list", name, ""))
      else:
        redirect("/following")

    post "/lists/rename":
      let
        oldName = @"old_name"
        newName = @"new_name"
      let acceptJson = acceptJson()
      if oldName.len == 0 or newName.len == 0:
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Missing list name"), Http400)
        else:
          resp Http400, showError("Missing list name", cfg)
        return
      if oldName == "default" or newName == "default":
        if acceptJson:
          respJson(errorJson("BAD_REQUEST", "Cannot rename default list"), Http400)
        else:
          resp Http400, showError("Cannot rename default list", cfg)
        return
      discard await renameList(oldName, newName)
      if acceptJson:
        respJson(actionResponseJson(true, "rename_list", oldName, newName))
      else:
        redirect("/following")
