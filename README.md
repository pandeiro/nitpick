# Nitpick

![Serene Hellscape of Social Media](/logo.png)

<p align="center">
  <strong>
    A privacy-focused Twitter front-end with chronological feeds and follow lists
    <br />
    <em style="font-size: 0.9em;">
      Fork of the incredible <a href="https://github.com/zedeus/nitter">Nitter</a>
    </em>
  </strong>
</p>

<p align="center">
  
</p>

---

## Features

- **Chronological Feed** — Follow users and see their tweets in chronological order, not algorithmically sorted
- **Multiple Follow Lists** — Organize followed users into custom lists, each with its own feed
- **Pinned Tweets** — Pin tweets for quick reference
- **No JavaScript or Ads** — Clean, fast, privacy-respecting
- **RSS Feeds** — Subscribe to timelines via RSS
- **Themes** — Choose your preferred look
- **Mobile Support** — Responsive design works on all devices
- **AGPLv3 Licensed** — No proprietary instances permitted

~[App Screenshot](/screen.png)

---

## Development

**Requirements:** [mise](https://mise.jdx.dev/) installed.

```bash
mise install                    # Install Nim and tools
mise exec -- nimble install -y  # Install Nim dependencies
mise exec -- nimble build       # Build the project
mise exec -- nim check src/nitter.nim  # Typecheck after changes
```

For agents working in this environment, see `AGENTS.md` for detailed guidelines.

---

## Deployment

### Docker Compose

```bash
docker-compose up -d
```

Exposes Nitpick on `http://localhost:7000`.

---

## JSON API

Nitpick supports JSON responses via content negotiation. Send `Accept: application/json` to receive JSON instead of HTML.

### Example Requests

```bash
# Get home feed as JSON
curl -H "Accept: application/json" http://localhost:8888/

# Get user profile as JSON
curl -H "Accept: application/json" http://localhost:8888/jack

# Get user replies as JSON
curl -H "Accept: application/json" http://localhost:8888/jack/with_replies

# Get user media as JSON
curl -H "Accept: application/json" http://localhost:8888/jack/media

# Search as JSON
curl -H "Accept: application/json" "http://localhost:8888/search?q=nitter"

# Get following lists as JSON
curl -H "Accept: application/json" http://localhost:8888/following

# Get user lists as JSON
curl -H "Accept: application/json" http://localhost:8888/jack/lists

# Get list profile as JSON
curl -H "Accept: application/json" http://localhost:8888/i/lists/123456

# Get list members as JSON
curl -H "Accept: application/json" http://localhost:8888/i/lists/123456/members

# Get single tweet as JSON
curl -H "Accept: application/json" http://localhost:8888/jack/status/1234567890

# Get pinned tweets as JSON
curl -H "Accept: application/json" http://localhost:8888/pinned

# Follow a user (JSON response)
curl -X POST -H "Accept: application/json" -d "username=jack" http://localhost:8888/follow

# Unfollow a user (JSON response)
curl -X POST -H "Accept: application/json" -d "username=jack" http://localhost:8888/unfollow

# Pin a tweet (JSON response)
curl -X POST -H "Accept: application/json" -d "tweetId=1234567890" http://localhost:8888/pin

# Unpin a tweet (JSON response)
curl -X POST -H "Accept: application/json" -d "tweetId=1234567890" http://localhost:8888/unpin

# Create a list (JSON response)
curl -X POST -H "Accept: application/json" -d "name=mylist" http://localhost:8888/lists/create

# Delete a list (JSON response)
curl -X POST -H "Accept: application/json" -d "name=mylist" http://localhost:8888/lists/delete

# Rename a list (JSON response)
curl -X POST -H "Accept: application/json" -d "old_name=oldlist&new_name=newlist" http://localhost:8888/lists/rename
```

### Response Format

Successful JSON responses include the requested data:
```json
{
  "username": "jack",
  "lists": ["default", "tech", "news"]
}
```

Action responses include success status:
```json
{
  "success": true,
  "action": "follow",
  "username": "jack",
  "list": "default"
}
```

Error responses include error details:
```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Tweet not found"
  }
}
```
