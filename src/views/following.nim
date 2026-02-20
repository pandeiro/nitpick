# SPDX-License-Identifier: AGPL-3.0-only
import strformat, tables
import karax/[karaxdsl, vdom]

import renderutils

proc renderFollowing*(listNames: seq[string]; listsData: Table[string, seq[string]]): VNode =
  buildHtml(tdiv(class="timeline-container")):
    tdiv(class="timeline-header"):
      h2: text "Following Lists"
    
    tdiv(class="lists-container"):
      for listName in listNames:
        let members = listsData.getOrDefault(listName, @[])
        tdiv(class="list-section"):
          tdiv(class="list-header"):
            h3:
              text if listName == "default": "Default" else: listName
              text " "
              span(class="list-count"): text "(" & $members.len & ")"
            
            if listName != "default":
              tdiv(class="list-actions"):
                form(`method`="post", action="/lists/delete", class="inline-form"):
                  hiddenField("name", listName)
                  verbatim """<button type="submit" class="delete-list-btn" onclick="return confirm('Delete this list?')">Delete</button>"""
          
          if members.len == 0:
            p(class="empty-list"): text "No users in this list"
          else:
            tdiv(class="following-list"):
              for username in members:
                tdiv(class="following-item"):
                  a(class="following-username", href=(&"/{username}")):
                    text "@" & username
                  form(`method`="post", action="/unfollow", class="following-unfollow-form"):
                    hiddenField("username", username)
                    hiddenField("list", listName)
                    hiddenField("referer", "/following")
                    button(`type`="submit", class="unfollow-btn"):
                      text "Remove"
      
      tdiv(class="create-list-section"):
        h3: text "Create New List"
        form(`method`="post", action="/lists/create", class="create-list-form"):
          hiddenField("referer", "/following")
          verbatim """<input type="text" name="name" placeholder="List name..." class="create-list-input" required>"""
          button(`type`="submit", class="create-list-btn"): text "Create"
