# SPDX-License-Identifier: AGPL-3.0-only
import karax/[karaxdsl, vdom]

import ".."/[types]
import tweet

proc renderPinned*(tweets: seq[Tweet]; prefs: Prefs; path: string): VNode =
  buildHtml(tdiv(class="timeline-container pinned-container")):
    tdiv(class="timeline-header"):
      h2: text "Pinned Tweets"
      if tweets.len == 0:
        p: text "No pinned tweets yet."

    if tweets.len > 0:
      tdiv(class="pinned-gallery"):
        for i, tweet in tweets:
          let last = (i == tweets.high)
          # Mark all tweets as pinned for display
          var displayTweet = tweet
          displayTweet.pinned = true
          tdiv(class="pinned-item"):
            renderTweet(displayTweet, prefs, "/pinned", index=i, last=last)
