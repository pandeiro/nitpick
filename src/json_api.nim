import json, options, times, sequtils
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
