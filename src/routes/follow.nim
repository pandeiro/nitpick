# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, strutils

import jester, karax/vdom

import router_utils
import ".."/[types, redis_cache]
import ../views/[general, following, profile]

export following

proc createFollowRouter*(cfg: Config) =
  router follow:
    get "/following":
      let
        prefs = requestPrefs()
        following = await getFollowingList()
        html = renderFollowing(following)
      resp renderMain(html, request, cfg, prefs, "Following")

    post "/follow":
      let username = @"username"
      if username.len == 0:
        resp Http400, showError("Missing username", cfg)
      discard await followUser(username)
      redirect(refPath())

    post "/unfollow":
      let username = @"username"
      if username.len == 0:
        resp Http400, showError("Missing username", cfg)
      discard await unfollowUser(username)
      redirect(refPath())