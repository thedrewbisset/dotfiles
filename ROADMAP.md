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

## Encrypt the Windows machine's drives

**Goal:** Full-disk encryption on the Windows box, so a credential on disk is
protected by more than file permissions.

**Why:** A key-based SSH logon session cannot reach Windows Credential Manager, so
`gh` falls back to a plaintext token file. Permissions are enforced by the running
OS; an unencrypted drive does not need the OS to be read. Encryption is what makes
those permissions mean anything once the disk leaves the machine. Same shape as the
`dotenvx` goal above: at-rest protection for a secret that has to exist somewhere.

**Blocked on physical access.** Secure Boot is a firmware setting, and a TPM that
fails to release the key stops the machine at a recovery prompt before the network
comes up. Both steps need the console, so this cannot be driven over SSH.

### Steps

The sequence, requirements and verification are written up in
[docs/windows-disk-encryption.md](docs/windows-disk-encryption.md). Per-machine state
and recovery-key IDs stay out of this repo deliberately -- see `.gitignore`.

1. Turn on Secure Boot at the console (UEFI boot mode, not legacy/CSM).
2. Turn on Device encryption and confirm the recovery key is backed up elsewhere.
3. Check each fixed drive, including the Dev Drive, which may need enabling on its own.
4. Narrow the `gh` credential to a fine-grained PAT, which is worth doing either way.
