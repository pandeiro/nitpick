import json, options, times, sequtils, tables
import types

proc toJson*(user: User): JsonNode =
  %*{
    "id": user.id,
    "username": user.username,
    "display_name": user.fullname,
    "bio": user.bio,
    "location": user.location,
    "website": user.website,
    "verified": user.verifiedType != VerifiedType.none,
    "verified_type": $user.verifiedType,
    "protected": user.protected,
    "followers_count": user.followers,
    "following_count": user.following,
    "tweets_count": user.tweets,
    "likes_count": user.likes,
    "media_count": user.media,
    "avatar_url": user.userPic,
    "banner_url": user.banner,
    "join_date": $user.joinDate
  }

proc toJson*(tweet: Tweet): JsonNode

proc toJson*(photo: GalleryPhoto): JsonNode =
  %*{
    "url": photo.url,
    "tweet_id": photo.tweetId,
    "color": photo.color
  }

proc toJson*(rail: PhotoRail): JsonNode =
  result = newJArray()
  for p in rail:
    result.add p.toJson()

proc toJson*(tweets: seq[Tweet]): JsonNode =
  result = newJArray()
  for t in tweets:
    result.add(t.toJson())

proc toJson*(tweet: Tweet): JsonNode =
  result = %*{
    "id": $tweet.id,
    "text": tweet.text,
    "author": tweet.user.toJson(),
    "created_at": $tweet.time,
    "reply_count": tweet.stats.replies,
    "retweet_count": tweet.stats.retweets,
    "like_count": tweet.stats.likes,
    "view_count": tweet.stats.views,
    "pinned": tweet.pinned
  }
  
  if tweet.retweet.isSome:
    result["retweeted"] = %true
  else:
    result["retweeted"] = %false

  var media = newJArray()
  for p in tweet.photos:
    media.add %*{"type": "photo", "url": p.url}
  
  if tweet.video.isSome:
    let v = tweet.video.get
    media.add %*{"type": "video", "url": v.url, "thumb": v.thumb}

  if tweet.gif.isSome:
    let g = tweet.gif.get
    media.add %*{"type": "gif", "url": g.url, "thumb": g.thumb}
  
  if media.len > 0:
    result["media"] = media

proc emptyTimelineJson*(): JsonNode =
  %*{
    "tweets": [],
    "pagination": {
      "next_cursor": "",
      "previous_cursor": ""
    },
    "meta": {
      "sampled_count": 0,
      "following_count": 0,
      "result_count": 0,
      "last_updated": 0
    }
  }

proc toJson*(timeline: Timeline): JsonNode =
  var allTweets: seq[Tweet] = @[]
  for thread in timeline.content:
    for tweet in thread:
      allTweets.add(tweet)

  %*{
    "tweets": toJson(allTweets),
    "pagination": {
      "next_cursor": timeline.bottom,
      "previous_cursor": timeline.top
    },
    "meta": {
      "sampled_count": timeline.sampledCount,
      "following_count": timeline.followingCount,
      "result_count": allTweets.len,
      "last_updated": timeline.lastUpdated
    }
  }

proc toJson*(profile: Profile; prefs: Prefs): JsonNode =
  %*{
    "user": profile.user.toJson(),
    "tweets": profile.tweets.toJson(),
    "photo_rail": profile.photoRail.toJson(),
    "preferences": {
      "theme": prefs.theme,
      "replace_twitter": prefs.replaceTwitter,
      "replace_youtube": prefs.replaceYouTube
    }
  }

proc errorJson*(code, message: string): JsonNode =
  %*{
    "error": {
      "code": code,
      "message": message
    }
  }

proc toJson*(results: Result[User]): JsonNode =
  var usersArray = newJArray()
  for user in results.content:
    usersArray.add(toJson(user))
  %*{
    "tweets": [],
    "users": usersArray,
    "pagination": {
      "next_cursor": results.bottom
    }
  }

proc toJson*(listNames: seq[string]; listsData: Table[string, seq[string]]): JsonNode =
  var lists: JsonNode = newJArray()
  for name in listNames:
    var members: JsonNode = newJArray()
    for member in listsData[name]:
      members.add(%member)
    lists.add(%*{
      "name": name,
      "members": members
    })
  var allMembersSet = initTable[string, bool]()
  for name in listNames:
    for member in listsData[name]:
      allMembersSet[member] = true
  var allMembers: JsonNode = newJArray()
  for member in allMembersSet.keys:
    allMembers.add(%member)
  %*{
    "lists": lists,
    "all_members": allMembers
  }

proc toJson*(list: List; timeline: Timeline): JsonNode =
  %*{
    "list": {
      "id": list.id,
      "name": list.name,
      "description": list.description,
      "members": list.members,
      "username": list.username
    },
    "timeline": toJson(timeline)
  }
