# Tech Stack: Nitpick

## Core Languages & Frameworks
- **Primary Language:** Nim (>= 2.0.0)
- **Web Framework:** Jester (using specific commit `baca3f`)
- **Frontend / Templating:** Karax (using specific commit `5cf360c`)
- **Styling:** SCSS (compiled via libsass and custom `gencss` tool)

## Data & Caching
- **Primary Store:** Redis (Valkey recommended for open-source compliance)
- **Redis Client:** `redpool` and a custom `redis` fork (`zedeus/redis`)

## Key Libraries & Utilities
- **Serialization:** `jsony`, `packedjson`, `flatty`
- **Compression:** `zippy`, `supersnappy`
- **Cryptography:** `nimcrypto`
- **Authentication:** `oauth`
- **Markdown:** `markdown`
- **JSON Parsing:** `jsony`, `packedjson`

## Infrastructure & DevOps
- **Containerization:** Docker & Docker Compose
- **Development Environment:** `docker-compose.dev.yml` with hot-reload support (via volumes and custom `Dockerfile.dev`)
- **CI/CD:** Travis CI, GitHub Workflows
- **Deployment:** systemd service support, reverse proxy (Nginx/Apache recommended)

## Testing
- **Integration Tests:** Python-based test suite (using `requests` and `pytest` patterns)
