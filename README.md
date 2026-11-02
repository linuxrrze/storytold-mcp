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
only**. [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) serves all of
them from one process on port 8080:

| Endpoint | Transport |
| --- | --- |
| `http://storytold-mcp:8080/servers/<app>/mcp` | streamable HTTP (use this) |
| `http://storytold-mcp:8080/servers/<app>/sse` | legacy SSE |
| `http://storytold-mcp:8080/status` | proxy status (healthcheck) |

`<app>` is one of cadcraft, deckcraft, designcraft, effectcraft, figcraft,
filmcraft, gridcraft, lightcraft, pdfcraft, photocraft, soundcraft,
texturecraft, vectorcraft, wordcraft -- whichever the build detected (see
below). New apps in the repo are picked up
automatically; only their `app-args.conf` line (work-dir confinement) has
to be added by hand.

## Files

| File | Used by CI? | Purpose |
| --- | --- | --- |
| `docker/Dockerfile` | yes | Adds the storytold repo, installs the apps (`ARG STORYTOLD_PINS`: space-separated `pkg=version` apt pins; empty installs every app in the repo) plus the Mesa/X11 libs headless rendering needs, mcp-proxy (`ARG MCP_PROXY_VERSION`) in `/opt/mcp-proxy`, then probes which apps serve MCP. |
| `docker/files/mcp-servers` | yes | `detect` (build: probe every `<app>-cli mcp` with an MCP `initialize`, write `/etc/mcp-proxy/apps.list`), `render` (start: write mcp-proxy's server config for the current `WORK_DIR`), `client-config [claude\|opencode]` (print client config). Identical copy in `solidcraft-mcp/`. |
| `docker/files/app-args.conf` | yes | Per-app `mcp` flags -- mostly the automation roots confining file access to the work dir. |
| `docker/files/entrypoint.sh` | yes | Checks the work dir, renders the config, execs mcp-proxy. Identical copy in `solidcraft-mcp/`. |
| `.storytold-mcp-version` | yes | Sorted `<package>=<version>` lines (every app + `mcp-proxy`) CI last built; compared against the repo index + PyPI. Updated automatically by CI. |
| `.storytold-mcp-base-digest` | yes | Registry digest of the `ubuntu:26.04` base image the last build used. Updated automatically by CI. |
| `.env.sample` | yes (build) | Template for the local (gitignored) `.env`: `STORYTOLD_PINS` + `MCP_PROXY_VERSION` (kept in sync by CI), the stack's runtime knobs (`HOST_HOME`, `PUID`/`PGID`, `CODINGENV_NETWORK`, `MCP_LOG_LEVEL`) and `TZ`. No secrets. |
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
  file needs no change. **No ports are published**: mcp-proxy has no
  authentication, anything on that network can use the servers. The
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
- **Resources:** mcp-proxy starts every served app's headless engine at
  startup, and all clients share that one session per app. Rendering
  (screenshots, previews) runs on the CPU via Mesa's lavapipe -- no GPU or
  display needed.

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
docker compose exec storytold-mcp cat /etc/mcp-proxy/versions.txt  # package versions
docker compose exec storytold-mcp cat /etc/mcp-proxy/apps.list     # served apps
```

## Build & version tracking

The workflow (flavor 1 in
[`.gitea/workflows/README.md`](../.gitea/workflows/README.md)) runs every
3 hours (the repo index is rebuilt every 3 hours), on manual dispatch, and
on pushes to `main` that touch `storytold-mcp/docker/**` or the workflow.

- **Package versions:** downloads the repo's
  `dists/stable/main/binary-amd64/Packages` and takes the newest version of
  every app. The index keeps several versions per app and is **not** in
  version order, hence `sort -V` instead of the first/last stanza. Plus
  mcp-proxy's latest version from PyPI. Any change against
  `.storytold-mcp-version` triggers a rebuild.
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
