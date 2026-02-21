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

### Docker-based Flow (Host Environment)

**Requirements:** Docker and docker-compose.

```bash
make dev          # Start Nitpick and Redis in the background
make build        # Rebuild the development container
make test         # Run integration tests (headless)
make test-headed  # Run integration tests with visible browser
make logs         # Follow application logs
make down         # Stop the development environment
```

Exposes Nitpick on `http://localhost:7000` by default.

### Mise-based Flow (Remote/Container Development)

**Requirements:** [mise](https://mise.jdx.dev/) installed.

```bash
mise install                    # Install Nim and tools
mise exec -- nimble install -y  # Install Nim dependencies
mise exec -- nimble build       # Build the project
mise exec -- nim check src/nitter.nim  # Typecheck after changes
```

For agents working in this environment, see `AGENTS.md` for detailed guidelines.
