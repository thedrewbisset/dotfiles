# Paperclip backup & restore

Playbook, not a script. Paperclip ships a backup primitive but **no restore
command**, and its docs cover neither restore nor moving an instance to another
machine. The steps below were verified against a live instance on
`2026.811.0-canary.3`; re-check them after a version bump.

---

## What Paperclip already does for you

`database.backup` is enabled out of the box (visible in
`~/.paperclip/instances/default/config.json`):

| Setting | Value |
|---|---|
| `enabled` | `true` |
| `intervalMinutes` | `60` |
| `retentionDays` | `30` |
| `dir` | `instances/default/data/backups` |

It writes gzipped SQL scripts (`paperclip-<date>-<time>.sql.gz`, ~180KB each).
Each is self-contained and transactional — `BEGIN`, `session_replication_role =
replica`, then `DROP TABLE`/`CREATE TABLE`/`COPY` for every table. So it is a
`psql` script, not a `pg_restore` archive.

**The gap:** `backup.dir` sits *inside the tree it protects*. One disk loss
takes the database and every backup of it. Nothing here is off-machine until
you copy it off.

Force one on demand:

```bash
paperclipai db:backup --json
```

---

## State inventory

What lives under `~/.paperclip/instances/default/`, and whether it matters:

| Path | Size | What it is | Recoverable without a backup? |
|---|---|---|---|
| `db/` | 82M | Embedded Postgres data directory — **the real state** | No |
| `secrets/master.key` | 44B | Decrypts every stored secret | **No — irreplaceable** |
| `secrets/decision-signing.key` | 44B | Signs approval decisions | No |
| `.env` | — | `PAPERCLIP_AGENT_JWT_SECRET` | Regenerable, invalidates issued agent JWTs |
| `config.json` | 4K | Instance config; embeds absolute `/Users/...` paths | Yes, via `onboard`/`configure` |
| `data/backups/` | 41M | The hourly dumps | — |
| `data/storage/`, `data/run-logs/` | 1.3M | Uploads, run logs | No (but low value) |
| `companies/`, `skills/`, `projects/` | 2.9M | UUID-keyed materializations of DB rows | Yes — regenerated from the DB |
| `logs/` | 3.4M | Service logs | Yes |
| `~/.paperclip/cli/` | 1.0G | CLI payloads | Yes — `bin/install.sh paperclip` |

**Do not back up `cli/`.** It is a gigabyte of reinstallable npm payloads.

### The coupling that will bite you

`secrets.provider` is `local_encrypted`, with the master key at
`secrets/master.key`. Every secret in the database is encrypted with it.

> **A database backup without `master.key` is unrestorable.**

Paperclip's docs state the key "is created automatically during onboarding and
remains local to the machine" and say nothing about losing it or moving it.
Treat the two as a single unit: a dump and its key, or neither.

---

## Backup

### Tier 1 — cold instance copy (recommended)

The most reliable snapshot, and the only one that needs no database
credentials. Requires the service stopped so Postgres isn't mid-write.

```bash
# 1. Stop the service (agents stop; the embedded Postgres stops with it)
paperclipai service stop

# 2. Confirm nothing is still listening
lsof -nP -iTCP:54329 -sTCP:LISTEN

# 3. Copy the instance, excluding reinstallable payloads
DEST=~/Backups/paperclip/$(date +%Y%m%d-%H%M%S)
mkdir -p "$DEST"
rsync -a --exclude 'logs/' ~/.paperclip/instances/default/ "$DEST/instance/"

# 4. Restart
paperclipai service start
```

> After any `paperclipai service` command, re-run `bin/install.sh paperclip` —
> service lifecycle commands regenerate the LaunchAgent plist and drop the PATH
> patch that lets adapters find `node`.

This captures `db/`, `secrets/`, `.env`, `config.json` and `data/` as one
consistent set.

**Its limit:** a physical Postgres data directory is tied to the Postgres major
version *and* CPU architecture (here `@embedded-postgres/darwin-arm64`). It will
not restore onto an Intel Mac, or onto a build bundling a different Postgres
major. For those, you need Tier 2.

### Tier 2 — portable logical dumps

Keep the `.sql.gz` files as the architecture-independent escape hatch:

```bash
paperclipai db:backup --json          # fresh dump first
cp ~/.paperclip/instances/default/data/backups/*.sql.gz "$DEST/dumps/"
cp ~/.paperclip/instances/default/secrets/*.key        "$DEST/keys/"
cp ~/.paperclip/instances/default/.env                 "$DEST/keys/"
```

**Known unknown:** the embedded Postgres runs as a child of the Paperclip
service on port `54329` with generated credentials. They are not in
`config.json`, not in `paperclipai env` (which reports `DATABASE_URL` as
`missing` in embedded mode), and the obvious defaults are all rejected. So
replaying a dump with `psql` is not a documented or verified path — treat Tier 2
as *insurance you may need help using*, not a rehearsed procedure. If you need
it, ask upstream for the embedded connection string, or point the instance at an
external Postgres via `DATABASE_URL`, where restore becomes ordinary `psql`.

### Where the key material goes

`$DEST/keys/` contains **unencrypted** secrets. It must not go into this repo,
or into an unencrypted cloud-synced folder. Put it in your password manager or
an encrypted volume, and keep it paired with the dump it belongs to.

---

## Restore

### Same machine, same architecture

```bash
paperclipai service stop
mv ~/.paperclip/instances/default ~/.paperclip/instances/default.broken
rsync -a "$DEST/instance/" ~/.paperclip/instances/default/
chmod 700 ~/.paperclip/instances/default/secrets
chmod 600 ~/.paperclip/instances/default/secrets/*.key ~/.paperclip/instances/default/.env
paperclipai service start
bin/install.sh paperclip     # re-apply the plist PATH patch
```

Keep `default.broken` until you have verified the restore. Delete it yourself —
nothing here removes it for you.

### New machine

```bash
bin/install.sh paperclip     # CLI at the pinned version + LaunchAgent + PATH patch
paperclipai onboard          # creates a fresh instance, then stop it
paperclipai service stop
```

Then restore over the fresh instance as above. `config.json` embeds absolute
paths under the old home — if the username differs, run `paperclipai configure`
rather than hand-editing, and re-check `database.embeddedPostgresDataDir`,
`logging.logDir`, `storage.localDisk.baseDir` and `database.backup.dir`.

If the architecture differs, the copied `db/` will not start. That is the Tier 2
case above.

### Verify

```bash
paperclipai service status --json     # active, health.ok
paperclipai doctor
paperclipai company list              # companies present
paperclipai agent list -C <companyId> # agents present
```

Then confirm a secret decrypts — an agent run that reads one is the real test.
If `master.key` did not come across, this is where it surfaces.

---

## Org definition (separate from backup)

The database is operational state. The *org* — company, agents, prompts, skills
— exports as a portable file tree:

```bash
recipes/paperclip/export-company
```

Writes `COMPANY.md`, `.paperclip.yaml`, `agents/<slug>/{AGENTS,HEARTBEAT,SOUL,TOOLS}.md`,
`skills/**/SKILL.md` and `manifest.json` to `recipes/paperclip/company/<slug>/`
(gitignored — it carries no API keys, but it is every agent prompt you have
written).

Rebuild elsewhere with `paperclipai company import:preview` /
`import:apply`. Note the export skips built-in managed agents; it reported
"Skipped 2 built-in managed agents from export."

This is the artifact to keep if what you care about is *recreating the org*
rather than *recovering the instance*. It is much smaller than a backup, it
diffs usefully, and it survives version and architecture changes that a physical
`db/` copy does not.

---

## Hygiene

- Backups are only as good as their last restore test. Do the "New machine" path
  once against a throwaway `--data-dir` before you need it.
- `retentionDays: 30` prunes silently. A backup you needed from 31 days ago is
  gone.
- Nothing here is scheduled. The hourly job protects against *bad writes*, not
  *lost disks*; only your off-machine copy does that.
