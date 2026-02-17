# Follow Feature Design Document

This document outlines the implementation plan for adding a global follow feature to Nitter, storing followed users in Redis.

## Overview

- **Goal**: Add ability to follow Twitter users by clicking a Follow button on their profile page
- **Storage**: Global follow list persisted in Redis (per Nitter/Redis instance)
- **Scope**: Profile page Follow button + `/following` page for managing followed users

---

## 1. Redis Cache Layer (`src/redis_cache.nim`)

Add new functions with key pattern `following:global` (Redis SET):

```nim
# Key for global following list
template followingKey(): string = "following:global"

# Check if username is followed
proc isFollowing*(username: string): Future[bool] {.async.}

# Add to following list (returns true if added, false if already following)
proc followUser*(username: string): Future[bool] {.async.}

# Remove from following list (returns true if removed)
proc unfollowUser*(username: string): Future[bool] {.async.}

# Get all followed usernames
proc getFollowingList*(): Future[seq[string]] {.async.}
```

---

## 2. Routes (`src/routes/follow.nim`) - New File

```nim
# GET /following - Following list page
# POST /follow - Follow a user (form body: username)
# POST /unfollow - Unfollow a user (form body: username, referrer)
```

- Follow/unfollow will redirect back to the referrer (profile page)
- Following page will show all followed users with unfollow buttons

---

## 3. Profile View (`src/views/profile.nim`)

Modify `renderUserCard()` to:
- Accept an `isFollowing: bool` parameter
- Render a Follow/Unfollow button below the stats
- Button will be a form that POSTs to `/follow` or `/unfollow`

---

## 4. Following Page (`src/views/following.nim`) - New File

```nim
# renderFollowing(following: seq[string]): VNode
#   - List of followed users with username links
#   - Unfollow button for each user
```

---

## 5. CSS Styling (`src/sass/profile/card.scss`)

Add styles for `.follow-btn` matching the existing UI theme (similar to existing button styles).

---

## 6. Wire Up Routes (`src/nitter.nim`)

- Import the new follow router
- Call `createFollowRouter(cfg)` during startup
- Extend the router

---

## 7. Update Timeline Route (`src/routes/timeline.nim`)

Modify `showTimeline` to:
- Call `isFollowing(username)` before rendering
- Pass follow status to `renderProfile`

---

## Files Summary

| File | Action |
|------|--------|
| `src/redis_cache.nim` | Add 4 follow functions |
| `src/routes/follow.nim` | **New** - Follow/unfollow routes + following page |
| `src/routes/timeline.nim` | Add follow check, pass to profile render |
| `src/views/profile.nim` | Add follow button to user card |
| `src/views/following.nim` | **New** - Following list page view |
| `src/sass/profile/card.scss` | Add `.follow-btn` styles |
| `src/nitter.nim` | Import and register follow router |

---

## Redis Persistence Note

Redis persistence is configured in `redis.conf`, not the application. The `following:global` key will use no expiration, so:
- **RDB snapshots**: Data saved when Redis snapshots (configurable)
- **AOF (Append-Only File)**: Every write is logged, survives restarts

For production, the user should enable AOF (`appendonly yes`) in Redis config for maximum durability.