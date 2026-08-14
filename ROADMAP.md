# Roadmap

## Adopt `dotenvx` for secret management

**Goal:** Standardize secrets on a declarative-but-encrypted pattern — committed `.env` files that hold *Keychain lookups*, never plaintext values.

**Why dotenvx:** Unlike standard dotenv loaders (which store literal values), `dotenvx` supports `$(command)` substitution resolved at load time. This lets a committed `.env` reference macOS Keychain while the secret stays encrypted at rest:

```
AWS_BEARER_TOKEN_BEDROCK="$(security find-generic-password -s claude-bedrock-token -w)"
```

**Current state (interim):** The Bedrock token lives in macOS Keychain and is resolved inline via command substitution in `claude-chartpro()` (`source/.zshrc`). This is the same core mechanism — it just lacks the declarative single-file manifest a `.env` provides.

**Caveat:** Encryption is at-rest only. Once resolved, the value sits in the process environment in cleartext, readable by the process and its children.

### Steps

1. Add a `recipes/dotenvx/install` recipe (install via Homebrew or npm).
2. Establish the convention: committed `.env` files contain only `security find-generic-password` references — never literal secrets. Audit `.gitignore` to guarantee no plaintext `.env` is ever committed.
3. Migrate the Bedrock token path from the `claude-chartpro()` inline export to a declarative `.env` resolved via `dotenvx run -- claude`.
4. Extend the README `## Secrets management` section with `dotenvx` usage. (The Keychain store/rotate/`pbpaste` flow is already documented there.)
5. Evaluate `direnv` for per-directory auto-loading (deferred — adds magic; revisit if multi-project scope grows).

### Open questions

- Per-project `.env` files vs. a single global manifest.
- Naming convention for Keychain service names (e.g. `claude-bedrock-token`).
