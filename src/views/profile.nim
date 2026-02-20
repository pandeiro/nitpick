# SPDX-License-Identifier: AGPL-3.0-only
import strutils, strformat
import karax/[karaxdsl, vdom, vstyles]

import renderutils, search
import ".."/[types, utils, formatters]

proc renderStat(num: int; class: string; text=""): VNode =
  let t = if text.len > 0: text else: class
  buildHtml(li(class=class)):
    span(class="profile-stat-header"): text capitalizeAscii(t)
    span(class="profile-stat-num"):
      text insertSep($num, ',')

proc renderFollowButton*(username: string; userLists: seq[string]; 
                         allLists: seq[string]; prefs: Prefs): VNode =
  let isFollowing = userLists.len > 0
  let btnClass = if isFollowing: "follow-btn following" else: "follow-btn"
  let btnText = if isFollowing: "Following" else: "Follow"
  
  buildHtml(tdiv(class="follow-button-container")):
    verbatim """<button type="button" class="$#" onclick="openFollowModal()">$#</button>""" % [btnClass, btnText & (if isFollowing and userLists.len > 1: " (" & $userLists.len & ")" else: "")]
    
    tdiv(id="follow-modal", class="follow-modal"):
      tdiv(class="follow-modal-content"):
        tdiv(class="follow-modal-header"):
          h3: text "Add to list"
          verbatim """<button type="button" class="close-modal" onclick="closeFollowModal()">×</button>"""
        
        tdiv(class="follow-modal-body"):
          for listName in allLists:
            let isChecked = listName in userLists
            tdiv(class="list-checkbox-item"):
              form(`method`="post", action=if isChecked: "/unfollow" else: "/follow", 
                   class="list-toggle-form"):
                hiddenField("username", username)
                hiddenField("list", listName)
                hiddenField("referer", "/" & username)
                let displayName = if listName == "default": "Default" else: listName
                if isChecked:
                  verbatim """<label class="list-checkbox-label"><input type="checkbox" checked onchange="this.form.submit()"> $# ✓</label>""" % displayName
                else:
                  verbatim """<label class="list-checkbox-label"><input type="checkbox" onchange="this.form.submit()"> $#</label>""" % displayName
          
          tdiv(class="create-list-section"):
            form(`method`="post", action="/lists/create", class="create-list-form"):
              hiddenField("referer", "/" & username)
              verbatim """<input type="text" name="name" placeholder="Create new list..." class="create-list-input" required>"""
              button(`type`="submit", class="create-list-btn"): text "+"

proc renderUserCard*(user: User; prefs: Prefs; userLists: seq[string]; 
                     allLists: seq[string]): VNode =
  buildHtml(tdiv(class="profile-card")):
    tdiv(class="profile-card-info"):
      let
        url = getPicUrl(user.getUserPic())
        size =
          if prefs.autoplayGifs and user.userPic.endsWith("gif"): ""
          else: "_400x400"

      a(class="profile-card-avatar", href=url, target="_blank"):
        genImg(user.getUserPic(size))

      tdiv(class="profile-card-tabs-name"):
        linkUser(user, class="profile-card-fullname")
        verifiedIcon(user)
        linkUser(user, class="profile-card-username")

    tdiv(class="profile-card-extra"):
      if user.bio.len > 0:
        tdiv(class="profile-bio"):
          p(dir="auto"):
            verbatim replaceUrls(user.bio, prefs)

      if user.location.len > 0:
        tdiv(class="profile-location"):
          span: icon "location"
          let (place, url) = getLocation(user)
          if url.len > 1:
            a(href=url): text place
          elif "://" in place:
            a(href=place): text place
          else:
            span: text place

      if user.website.len > 0:
        tdiv(class="profile-website"):
          span:
            let url = replaceUrls(user.website, prefs)
            icon "link"
            a(href=url): text url.shortLink

      tdiv(class="profile-joindate"):
        span(title=getJoinDateFull(user)):
          icon "calendar", getJoinDate(user)

      tdiv(class="profile-card-extra-links"):
        ul(class="profile-statlist"):
          renderStat(user.tweets, "posts", text="Tweets")
          renderStat(user.following, "following")
          renderStat(user.followers, "followers")
          renderStat(user.likes, "likes")

        renderFollowButton(user.username, userLists, allLists, prefs)

proc renderPhotoRail(profile: Profile): VNode =
  let count = insertSep($profile.user.media, ',')
  buildHtml(tdiv(class="photo-rail-card")):
    tdiv(class="photo-rail-header"):
      a(href=(&"/{profile.user.username}/media")):
        icon "picture", count & " Photos and videos"

    input(id="photo-rail-grid-toggle", `type`="checkbox")
    label(`for`="photo-rail-grid-toggle", class="photo-rail-header-mobile"):
      icon "picture", count & " Photos and videos"
      icon "down"

    tdiv(class="photo-rail-grid"):
      for i, photo in profile.photoRail:
        if i == 16: break
        let photoSuffix =
          if "format" in photo.url or "placeholder" in photo.url: ""
          else: ":thumb"
        a(href=(&"/{profile.user.username}/status/{photo.tweetId}#m")):
          genImg(photo.url & photoSuffix)

proc renderBanner(banner: string): VNode =
  buildHtml():
    if banner.len == 0:
      a()
    elif banner.startsWith('#'):
      a(style={backgroundColor: banner})
    else:
      a(href=getPicUrl(banner), target="_blank"): genImg(banner)

proc renderProtected(username: string): VNode =
  buildHtml(tdiv(class="timeline-container")):
    tdiv(class="timeline-header timeline-protected"):
      h2: text "This account's tweets are protected."
      p: text &"Only confirmed followers have access to @{username}'s tweets."

proc renderProfile*(profile: var Profile; prefs: Prefs; path: string; 
                    userLists: seq[string]; allLists: seq[string]): VNode =
  profile.tweets.query.fromUser = @[profile.user.username]

  buildHtml(tdiv(class="profile-tabs")):
    if not prefs.hideBanner:
      tdiv(class="profile-banner"):
        renderBanner(profile.user.banner)

    let sticky = if prefs.stickyProfile: " sticky" else: ""
    tdiv(class=("profile-tab" & sticky)):
      renderUserCard(profile.user, prefs, userLists, allLists)
      if profile.photoRail.len > 0:
        renderPhotoRail(profile)

    if profile.user.protected:
      renderProtected(profile.user.username)
    else:
      renderTweetSearch(profile.tweets, prefs, path, profile.pinned)
