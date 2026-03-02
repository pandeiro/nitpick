# SPDX-License-Identifier: AGPL-3.0-only
import strformat
import karax/[karaxdsl, vdom]

import renderutils
import ".."/[types, utils]

proc renderListTabs*(query: Query; path: string): VNode =
  buildHtml(ul(class="tab")):
    li(class=query.getTabClass(posts)):
      a(href=(path)): text "Tweets"
    li(class=query.getTabClass(userList)):
      a(href=(path & "/members")): text "Members"

proc renderList*(body: VNode; query: Query; list: List): VNode =
  buildHtml(tdiv(class="timeline-container")):
    if list.banner.len > 0:
      tdiv(class="timeline-banner"):
        a(href=getPicUrl(list.banner), target="_blank"):
          genImg(list.banner)

    tdiv(class="timeline-header"):
      text &"\"{list.name}\" by @{list.username}"

      tdiv(class="timeline-description"):
        text list.description

    renderListTabs(query, &"/i/lists/{list.id}")
    body

proc renderUserLists*(username: string; lists: seq[string]): VNode =
  buildHtml(tdiv(class="timeline-container")):
    tdiv(class="timeline-header"):
      text &"Lists for @{username}"
    if lists.len == 0:
      tdiv(class="timeline-description"):
        text "No lists found"
    else:
      ul(class="list-members"):
        for listName in lists:
          li:
            a(href=("/i/lists/" & listName)):
              text listName
