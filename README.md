# Nitpick

<p align="center">
  <img src="/screenshot.png" alt="Nitpick Screenshot" width="600">
</p>

<p align="center">
  <strong>A privacy-focused Twitter front-end with chronological feeds and follow lists</strong>
</p>

<p align="center">
  <em>Fork of <a href="https://github.com/zedeus/nitter">Nitter</a></em>
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

---

## Screenshot

![Nitpick screenshot](/screenshot.png)

---

## Original Nitter Documentation

> [!NOTE]
> Running a Nitter instance now requires real accounts, since Twitter removed the previous methods. \
> For instructions on how to obtain session tokens, see [Creating session tokens](https://github.com/zedeus/nitter/wiki/Creating-session-tokens).

A free and open source alternative Twitter front-end focused on privacy and
performance. Inspired by the [Invidious](https://github.com/iv-org/invidious) project.

- All requests go through the backend, client never talks to Twitter
- Prevents Twitter from tracking your IP or JavaScript fingerprint
- Uses Twitter's unofficial API (no developer account required)
- Lightweight (for [@nim_lang](https://nitter.net/nim_lang), 60KB vs 784KB from twitter.com)

<details>
<summary>Donations (for original Nitter project)</summary>
Liberapay: https://liberapay.com/zedeus<br>
Patreon: https://patreon.com/nitter<br>
BTC: bc1qpqpzjkcpgluhzf7x9yqe7jfe8gpfm5v08mdr55<br>
ETH: 0x24a0DB59A923B588c7A5EBd0dBDFDD1bCe9c4460<br>
XMR: 42hKayRoEAw4D6G6t8mQHPJHQcXqofjFuVfavqKeNMNUZfeJLJAcNU19i1bGdDvcdN6romiSscWGWJCczFLe9RFhM3d1zpL<br>
SOL: ANsyGNXFo6osuFwr1YnUqif2RdoYRhc27WdyQNmmETSW<br>
ZEC: u1vndfqtzyy6qkzhkapxelel7ams38wmfeccu3fdpy2wkuc4erxyjm8ncjhnyg747x6t0kf0faqhh2hxyplgaum08d2wnj4n7cyu9s6zhxkqw2aef4hgd4s6vh5hpqvfken98rg80kgtgn64ff70djy7s8f839z00hwhuzlcggvefhdlyszkvwy3c7yw623vw3rvar6q6evd3xcvveypt
</details>

### Why?

It's impossible to use Twitter without JavaScript enabled, and as of 2024 you need to sign up. For privacy-minded folks, preventing JavaScript analytics and IP-based tracking is important. Despite being behind a VPN and using adblockers, you can still be tracked via [browser fingerprinting](https://restoreprivacy.com/browser-fingerprinting/). 

Using an instance of Nitter/Nitpick (hosted on a VPS), you can browse Twitter without JavaScript while retaining your privacy. Nitter is on average around 15 times lighter than Twitter, and serves pages faster.

### Resources

- [List of instances](https://github.com/zedeus/nitter/wiki/Instances)
- [Browser extensions](https://github.com/zedeus/nitter/wiki/Extensions)

### Roadmap

- Embeds
- Account system with timeline support
- Archiving tweets/profiles
- Developer API

### Installation

See the original [Nitter repository](https://github.com/zedeus/nitter) for full installation instructions.

**Dependencies:**
- libpcre
- libsass
- redis/valkey

**Quick start:**
```bash
$ git clone https://github.com/zedeus/nitter
$ cd nitter
$ nimble build -d:danger --mm:refc
$ nimble scss
$ nimble md
$ cp nitter.example.conf nitter.conf
```

### Contact

Original Nitter project:
- [Matrix channel](https://matrix.to/#/#nitter:matrix.org)
- Email: zedeus@pm.me
