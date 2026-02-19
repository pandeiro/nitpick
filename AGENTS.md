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
