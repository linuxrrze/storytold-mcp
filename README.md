# storytold-mcp

Docker image serving the MCP servers of all
[storytold](https://github.com/storytold) "ArtCraft" Crafting Apps over
HTTP, built via Gitea Actions -- see
[`.gitea/workflows/storytold-mcp-rebuild.yml`](../.gitea/workflows/storytold-mcp-rebuild.yml).
This directory is also the **hub** of the Craft MCP stack: its compose
sample runs this image and [`solidcraft-mcp`](../solidcraft-mcp/) next to
[`codingenv`](../codingenv/), so claude/opencode there can use them.

Based on `ubuntu:26.04`, with the apps installed from the `storytold` apt
repo of [linuxrrze/deb-repos](https://github.com/linuxrrze/deb-repos)
(every app except `artcraft-launcher`, the GUI installer, and -- for now --
`craft-anything`, see below). Each app package
ships `<app>-cli`, whose `<app>-cli mcp` is a headless MCP server -- **stdio
only**. `mcp-gateway` (`docker/files/mcp-gateway`, Python standard library
only) serves all of them on port 8080, **one server process per MCP
session**, started on demand:

| Endpoint | |
| --- | --- |
| `http://storytold-mcp:8080/servers/<app>/mcp` | streamable HTTP |
| `http://storytold-mcp:8080/status` | sessions per app (`running` with PIDs, `notStarted`), cached protocol versions (JSON) |
| `http://storytold-mcp:8080/healthz` | liveness (healthcheck) |

- Every session gets its own fresh `<app>-cli mcp` (3-140 ms to start), so
  clients never see each other's open documents.
- **Lazy start** (`MCP_LAZY=1`, the default): `initialize`, `ping` and the
  tool/prompt/resource lists are answered from a discovery cache baked
  into the image (`/etc/mcp-gateway/cache/<app>.json`, the answers of a
  fresh process). The session's process starts on its first other request,
  usually the first tool call. The gateway replays the client's
  `initialize` to it first, so the client never notices. After that
  everything goes to the process, as before. A client asking for a
  protocol version not in the cache gets its process at `initialize`, and
  those answers are cached in memory for later sessions. Sessions that
  never started a process cost nothing and are kept for
  `MCP_LAZY_IDLE_TIMEOUT` seconds (default 86400) without a request.
  `MCP_LAZY=0` starts every session's process at `initialize`.
- The process is stopped when the client deletes the session, when it
  exits, or after `MCP_IDLE_TIMEOUT` seconds (default 1800) with no request
  running and the client's event stream closed. Clients reconnecting after
  that get a new session -- documents not saved to the work dir are gone.
- `MCP_MAX_SESSIONS` (default 16) caps the running processes per app
  (sessions that never started one don't count);
  further sessions get HTTP 503.
- Only the session-based protocol versions (up to 2025-11-25) are offered:
  the session-less 2026-07-28 protocol would need a process per request,
  losing the apps' in-memory documents between calls. Clients that try it
  first fall back (checked with Claude Code 2.1.309 and opencode).
- The legacy SSE transport (`/servers/<app>/sse` under mcp-proxy) is gone.

`<app>` is one of cadcraft, deckcraft, designcraft, effectcraft, figcraft,
filmcraft, gridcraft, lightcraft, pdfcraft, photocraft, soundcraft,
texturecraft, vectorcraft, wordcraft -- whichever the build detected (see
below). New apps in the repo are picked up
automatically; only their `app-args.conf` line (work-dir confinement) has
to be added by hand.

## Files

| File | Used by CI? | Purpose |
| --- | --- | --- |
| `docker/Dockerfile` | yes | Adds the storytold repo, installs the apps (`ARG STORYTOLD_PINS`: space-separated `pkg=version` apt pins; empty installs every app in the repo) plus the Mesa/X11 libs headless rendering needs, then probes which apps serve MCP. |
| `docker/files/mcp-gateway` | yes | The HTTP gateway: streamable HTTP per session, idle reaper, Host/Origin checks, optional API key (`MCP_API_KEY`) and per-server raw TCP (unused here). `mcp-gateway --help` lists its options. Identical copy in `solidcraft-mcp/`. |
| `docker/files/mcp-servers` | yes | `detect` (build: probe every `<app>-cli mcp` with an MCP `initialize`, write `/etc/mcp-gateway/apps.list`; then the discovery cache, see [Discovery cache](#discovery-cache)), `render` (start: write mcp-gateway's server config for the current `WORK_DIR`), `client-config [claude\|opencode]` (print client config). Identical copy in `solidcraft-mcp/`. |
| `docker/files/app-args.conf` | yes | Per-app `mcp` flags -- mostly the automation roots confining file access to the work dir. |
| `docker/files/entrypoint.sh` | yes | Checks the work dir, renders the config, execs mcp-gateway. Identical copy in `solidcraft-mcp/`. |
| `.storytold-mcp-version` | yes | Sorted `<package>=<version>` lines (every app) CI last built; compared against the repo index. Updated automatically by CI. |
| `.storytold-mcp-base-digest` | yes | Registry digest of the `ubuntu:26.04` base image the last build used. Updated automatically by CI. |
| `.env.sample` | yes (build) | Template for the local (gitignored) `.env`: `STORYTOLD_PINS` (kept in sync by CI), the stack's runtime knobs (`HOST_HOME`, `PUID`/`PGID`, `CODINGENV_NETWORK`, `MCP_LOG_LEVEL`, `MCP_ALLOWED_HOSTS`, `MCP_IDLE_TIMEOUT`, `MCP_MAX_SESSIONS`, `MCP_LAZY`, `MCP_LAZY_IDLE_TIMEOUT`) and `TZ`. No secrets. |
| `docker-compose.yml.sample` | no | Sanitized hub compose for storytold-mcp + solidcraft-mcp. The real file is gitignored. |

## Usage

Start codingenv first (its network must exist), then here:

```sh
cp docker-compose.yml.sample docker-compose.yml
cp .env.sample .env    # HOST_HOME, PUID/PGID as for codingenv; CODINGENV_NETWORK
mkdir -p "$HOST_HOME/work"
docker compose up -d
```

- **Network:** both services join codingenv's compose network
  (`CODINGENV_NETWORK`, default `codingenv_default` -- check with
  `docker network ls`) as an external network, so codingenv's own compose
  file needs no change. **No ports are published**: without `MCP_API_KEY`
  the gateway has no authentication, anything on that network can use the
  servers. The
  sample has a commented `127.0.0.1:8081` mapping for testing from the host.
- **Shared work dir:** `$HOST_HOME/work` is mounted at
  `/home/sandbox/work` -- the path it already has inside codingenv
  (Option A mounts `HOST_HOME` at `/home/sandbox`), so a path the agent
  hands to a tool means the same file everywhere. The servers run with it
  as their cwd, and every app with automation-root flags (see
  `app-args.conf`) can only read/write inside it; cadcraft, filmcraft,
  gridcraft and lightcraft have no such flag in MCP mode.
- **Not included: craft-anything.** The repo's reverse-engineering tool is
  excluded for now (workflow's version check + the Dockerfile's fallback
  list): it has no work-dir confinement flag, and its `rebuild_*` tools
  start a coding agent (needs an AI backend via `craft-anything-cli ai
  ...`).
- **User:** the containers run as `PUID:PGID` (codingenv's), so files they
  write into the work dir are yours. The entrypoint aborts if the work dir
  is missing or not writable for that uid.
- **Resources:** nothing runs until a tool is called. claude and opencode
  initialize every configured server and list its tools when they start.
  With lazy start that costs no process, so a client with all apps
  configured only runs the apps it actually calls (~5-20 MB each idle).
  Every client gets its own. Rendering (screenshots, previews) runs on
  the CPU via Mesa's lavapipe -- no GPU or display needed; renders go to the
  `/tmp` tmpfs (10 GB limit in the compose sample), shared by all sessions.
- **Concurrent instances:** checked for every app: several `<app>-cli mcp`
  run side by side as the same user without locks, shared state or
  listening sockets; saves go through uniquely named temp files plus
  rename, effectcraft's `--autosave` uses a directory per process.
  Sessions share the work dir, so two clients saving the same file name
  overwrite each other (last save wins).

### Connecting claude / opencode in codingenv

Print ready-made config for everything this image serves:

```sh
docker compose exec storytold-mcp mcp-servers client-config claude    # .mcp.json
docker compose exec storytold-mcp mcp-servers client-config opencode  # opencode.json "mcp"
docker compose exec solidcraft-mcp mcp-servers client-config claude
```

or add single servers by hand inside codingenv:

```sh
claude mcp add --transport http pdfcraft http://storytold-mcp:8080/servers/pdfcraft/mcp
claude mcp add --transport http solidcraft http://solidcraft-mcp:8080/servers/solidcraft/mcp
claude mcp list
```

opencode (`opencode.json`):

```json
{ "mcp": { "pdfcraft": { "type": "remote", "url": "http://storytold-mcp:8080/servers/pdfcraft/mcp", "enabled": true } } }
```

### What is installed / served

```sh
docker compose exec storytold-mcp cat /etc/mcp-gateway/versions.txt  # package versions
docker compose exec storytold-mcp cat /etc/mcp-gateway/apps.list     # served apps
docker compose exec storytold-mcp curl -s localhost:8080/status      # running sessions
```

## Discovery cache

`mcp-servers detect` writes it at build time, after the served apps are
known. For each app and each protocol version in `CACHE_VERSIONS`
(2024-11-05 .. 2025-11-25) it starts a fresh process and records the
`initialize` result and every list the server announces (`tools/list`,
`prompts/list`, `resources/list`, `resources/templates/list`, all pages
merged). Some apps name their allowed folders in instructions or tool
descriptions, so the probe runs with the image's real `WORK_DIR` (passed
in by the Dockerfile as `MCP_CACHE_WORK_DIR`). `mcp-servers render` passes
a cache to the gateway only while the container's `WORK_DIR` is still that
dir. An app whose second fresh process answers differently is **not
cached** (e.g. a per-process autosave folder in effectcraft's
instructions); its sessions start at `initialize`, as before. The build
log shows which apps got cached and how many tools each has. The cache is
part of the image, so a rebuild (new app versions) replaces it.

Assumption: a server's discovery answers depend neither on the client's
`initialize` parameters (`clientInfo`, capabilities) nor on anything that
differs between build and container other than `WORK_DIR`. Once a
session's process runs, all lists come from it live.

### Alternatives considered

The gateway's own lazy start was chosen after looking at existing tools
(November 2026):

- **mcp-later**, **dsh-lazy-mcp**: same idea (cached discovery, spawn on
  first call), but as stdio wrappers on the client side -- they would
  have to be set up in every client and still need a process per session
  behind them.
- **FastMCP proxy**: connects upstream on the first `initialize`, so it
  isn't lazy past the handshake.
- **Docker MCP Gateway**: one container per server, removed after each
  call unless `--long-lived`. Tool metadata comes from its catalog. It is
  a Docker CLI plugin with no documented Podman support, and short-lived
  containers lose the apps' in-memory documents between calls.
- **ToolHive** (Docker or Podman): isolates each *server* from the host
  in a container, not *sessions* from each other.
- **ContextForge, MetaMCP, 1mcp**: aggregators with long-lived upstreams
  shared by all clients -- exactly the shared state the gateway avoids.

**A container per session (podman)** was ruled out for now. Nested
rootless podman needs `/dev/fuse`, subuids and relaxed seccomp/AppArmor.
Mounting the host's podman socket instead gives the gateway root on the
host. Starting a session would take ~0.3-1 s instead of 3-140 ms, and
the work dir would need per-container mounts with uid mapping. Its gains
(a memory/CPU cap per session, a private `/tmp`) would be cheaper with
`setrlimit` in the gateway's `spawn()`, if a runaway session ever becomes
a problem.

## Build & version tracking

The workflow (flavor 1 in
[`.gitea/workflows/README.md`](../.gitea/workflows/README.md)) runs every
3 hours (the repo index is rebuilt every 3 hours), on manual dispatch, and
on pushes to `main` that touch `storytold-mcp/docker/**` or the workflow.

- **Package versions:** downloads the repo's
  `dists/stable/main/binary-amd64/Packages` and takes the newest version of
  every app. The index keeps several versions per app and is **not** in
  version order, hence `sort -V` instead of the first/last stanza. Any
  change against `.storytold-mcp-version` triggers a rebuild.
- **Base image:** a new `ubuntu:26.04` digest (vs.
  `.storytold-mcp-base-digest`) also triggers a rebuild.
- **App detection:** the build probes each `<app>-cli mcp` (with its
  `app-args.conf` flags) with an MCP `initialize`. Apps that answer are
  served, others are skipped -- both lists are in the build log. The build
  **fails** if an app works without its flags but not with them (an
  upstream flag change -- fix `app-args.conf`), or if no app works.
- Build (`docker build --pull --no-cache`), startup banner
  (`.gitea/scripts/add-banner.sh`), Trivy scan
  (`.gitea/scripts/trivy-scan.sh`).
- **Tags:** 14 apps have no single version, so the version tag is the
  first 12 hex digits of the version list's sha256, plus
  `<tag>-<YYYYMMDD>` (rollback) and `latest`.
- Finally CI writes the version list/digest to `.storytold-mcp-version`,
  `.storytold-mcp-base-digest` and `.env.sample` and pushes that commit
  (with a retry-with-rebase loop) -- only if something actually changed.
