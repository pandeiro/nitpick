# SPDX-License-Identifier: AGPL-3.0-only
import strformat
import karax/[karaxdsl, vdom]

import renderutils
import ".."/[types, utils]

proc renderFollowing*(following: seq[string]): VNode =
  buildHtml(tdiv(class="timeline-container")):
    tdiv(class="timeline-header"):
      h2: text "Following"
      if following.len == 0:
        p: text "You are not following anyone yet."

    if following.len > 0:
      tdiv(class="following-list"):
        for username in following:
          tdiv(class="following-item"):
            a(class="following-username", href=(&"/{username}")):
              text "@" & username
            form(`method`="post", action="/unfollow", class="following-unfollow-form"):
              hiddenField("username", username)
              hiddenField("referer", "/following")
              button(`type`="submit", class="unfollow-btn"):
                text "Unfollow"