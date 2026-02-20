# Agent Guidelines

## Environment Setup

If `mise.toml` is present in the project root, the project uses mise for tool version management.

Before running Nim commands (`nim`, `nimble`), ensure the mise environment is activated:

```bash
source ~/.bashrc 2>/dev/null || true
/root/.local/bin/mise install  # Install tools from mise.toml
/root/.local/bin/mise exec -- nim check src/nitter.nim
```

Or use the full path to mise binaries:
```bash
/root/.local/bin/mise exec -- nimble build
```

## Build Commands

- **Typecheck**: `nim check src/nitter.nim`
- **Build**: `nimble build`
- **Install deps**: `nimble install -y`

## Typecheck After Changes

Always run `nim check src/nitter.nim` after modifying any `.nim` files to catch type errors, missing imports, and syntax issues before committing.

## Code Style

- Do not add comments unless explicitly requested
- Follow existing patterns and conventions in the codebase

## Git Workflow

- Stage and commit changes at your discretion
- Never push to remote without first asking the user, unless the user explicitly directs you to push

## Architecture

### Chronological Feed

The chronological feed (`src/feed.nim`) fetches tweets from followed users via Twitter's search API.

**Search Pool Strategy:**
- Samples up to 30 users, split into 2 chunks of 15
- Each chunk is a `SearchPoolEntry` (users + cursor)
- Twitter search queries are limited; 15 users per query keeps queries manageable
- Chunks execute in parallel for faster initial loads

**Multi-Cursor Pagination:**
- Each pool entry tracks its own cursor for "Load More" requests
- On pagination, all non-exhausted entries are queried in parallel
- Results are merged and deduplicated before caching

**Redis Accumulation:**
- Global feed cached in Redis with 60-minute TTL
- Each request accumulates new tweets into the existing cache
- Deduplicates by tweet ID, keeps latest 1000 tweets sorted chronologically
- Key: `nitpick:feed:global` (see `src/redis_cache.nim`)

**Key Types (`src/types.nim`):**
- `SearchPoolEntry`: users + cursor for one parallel query
- `GlobalFeed`: tweetIds + searchPool + lastUpdated

### Following Lists

Users can be organized into multiple following lists. Each list has its own chronological feed.

**Redis Keys:**
- `following:global` - Default list (backward compatible with original single-list)
- `following:lists` - Set of custom list names
- `following:list:<name>` - Set of usernames for each custom list
- `nitpick:feed:list:<name>` - Per-list feed cache (GlobalFeed object)

**Key Functions (`src/redis_cache.nim`):**
- `getListNames()` - Returns all list names (always includes "default")
- `getListMembers(name)` - Get usernames in a specific list
- `getUserLists(username)` - Get all lists a user belongs to
- `addToList(name, username)` / `removeFromList(name, username)` - Modify list membership
- `createList(name)` / `deleteList(name)` - Manage lists

**Routes (`src/routes/follow.nim`):**
- `GET /following` - Shows all lists with members
- `POST /follow` / `POST /unfollow` - Accept `list` parameter
- `POST /lists/create` / `/lists/delete` - CRUD for lists

**Feed Filtering:**
- Home route `/?list=<name>` loads feed for that list
- `fetchFeed()` in `src/feed.nim` accepts `listName` parameter
- Each list has independent feed cache and search pool
