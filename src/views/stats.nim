# SPDX-License-Identifier: AGPL-3.0-only
import json
import karax/[karaxdsl, vdom]

proc renderStats*(statsJson: JsonNode): VNode =
  buildHtml(tdiv(class="timeline-container stats-container")):
    tdiv(class="timeline-header"):
      h2: text "Instance Stats"

    # ── Feed Status ──
    let feed = statsJson{"feed"}
    if feed.kind != JNull:
      tdiv(class="stats-section"):
        h3: text "Feed Status"
        table(class="stats-table"):
          tbody:
            tr:
              td: text "Tweets Cached"
              td: text $feed{"tweetCount"}.getInt()
            tr:
              td: text "Following"
              td: text $feed{"followingCount"}.getInt()
            tr:
              td: text "Last Updated"
              td: text feed{"lastUpdated"}.getStr()

    # ── Lists ──
    let lists = statsJson{"lists"}
    if lists.kind == JArray and lists.len > 0:
      tdiv(class="stats-section"):
        h3: text "Following Lists"
        table(class="stats-table"):
          thead:
            tr:
              th: text "List"
              th: text "Members"
              th: text "Tweets Cached"
              th: text "Last Updated"
          tbody:
            for lst in lists.items:
              tr:
                td: text lst{"name"}.getStr()
                td: text $lst{"members"}.getInt()
                td: text $lst{"tweets"}.getInt()
                td: text lst{"lastUpdated"}.getStr()

    # ── Ingest Throughput ──
    let counters = statsJson{"counters"}
    if counters.kind != JNull:
      tdiv(class="stats-section"):
        h3: text "Refresher Throughput (rolling 2h)"
        let
          ingested = counters{"ingested"}.getInt()
          refreshes = counters{"refreshes"}.getInt()
          errors = counters{"errors"}.getInt()
          total = refreshes + errors
          successPct = if total > 0: $(refreshes * 100 div total) & "%" else: "N/A"
        table(class="stats-table"):
          tbody:
            tr:
              td: text "Tweets Ingested"
              td: text $ingested
            tr:
              td: text "Successful Refreshes"
              td: text $refreshes
            tr:
              td: text "Failed Refreshes"
              td: text $errors
            tr:
              td: text "Success Rate"
              td: text successPct

    # ── Sessions ──
    let sessions = statsJson{"sessions"}
    if sessions.kind != JNull:
      tdiv(class="stats-section"):
        h3: text "Session Pool"
        table(class="stats-table"):
          tbody:
            tr:
              td: text "Total Sessions"
              td: text $sessions{"total"}.getInt()
            tr:
              td: text "Limited Sessions"
              td: text $sessions{"limited"}.getInt()
            tr:
              td: text "Oldest Session"
              td: text sessions{"oldest"}.getStr()
            tr:
              td: text "Newest Session"
              td: text sessions{"newest"}.getStr()

    # ── API Requests (per endpoint) ──
    let requests = statsJson{"requests"}
    if requests.kind != JNull and requests{"apis"}.kind == JObject:
      tdiv(class="stats-section"):
        h3: text "API Requests (since last reset)"
        let apis = requests{"apis"}
        if apis.kind == JObject and apis.len > 0:
          table(class="stats-table"):
            thead:
              tr:
                th: text "API"
                th: text "Requests"
            tbody:
              for api, count in apis.pairs:
                tr:
                  td: code: text api
                  td: text $count.getInt()

    # ── Skip Counters ──
    let skips = statsJson{"skipCounters"}
    if skips.kind == JObject and skips.len > 0:
      tdiv(class="stats-section"):
        h3: text "Skipped Users (consecutive failures)"
        table(class="stats-table"):
          thead:
            tr:
              th: text "User"
              th: text "Failures"
          tbody:
            for user, count in skips.pairs:
              tr:
                td: text user
                td: text $count.getInt()
