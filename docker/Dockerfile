FROM ubuntu:26.04
# Space-separated apt pins, e.g. "cadcraft=0.14.0-1 deckcraft=0.12.0-1 ..."
# (CI passes the repo's newest version of every app). Empty installs every
# app currently in the repo.
ARG STORYTOLD_PINS
ARG MCP_PROXY_VERSION
ENV UBUNTU_VERSION=26.04

ENV DEB_REPO=https://linuxrrze.github.io/deb-repos

RUN << EORUN
set -e
# Skip docs/man pages -- pure image-size trimming, has to be in place before
# the first package unpacks anything under /usr/share.
{ echo 'path-exclude=/usr/share/doc/*'; \
  echo 'path-exclude=/usr/share/man/*'; \
  echo 'path-exclude=/usr/share/groff/*'; \
  echo 'path-exclude=/usr/share/info/*'; } > /etc/dpkg/dpkg.cfg.d/01_nodoc

apt update && apt -y dist-upgrade
apt install -y ca-certificates curl python3 python3-venv tini --no-install-recommends

# Add the storytold repo. mirror+https: apt reads the indexes from github.io
# and fetches the .debs straight from the apps' GitHub release assets.
mkdir -p /etc/apt/keyrings
curl -fsSL "$DEB_REPO/deb-repos.asc" -o /etc/apt/keyrings/deb-repos.asc
cat > /etc/apt/sources.list.d/storytold.sources << EOF
Types: deb
URIs: mirror+$DEB_REPO/storytold/mirrors.txt
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/deb-repos.asc
EOF
apt update

PINS="$STORYTOLD_PINS"
if [ -z "$PINS" ]; then
	# Every app in the repo; artcraft-launcher is a GUI-only installer.
	PINS=$(awk '/^Package:/ && $2 != "artcraft-launcher" { print $2 }' \
		/var/lib/apt/lists/*storytold*_Packages | sort -u)
fi
# Headless MCP needs no display, but the apps link the X11/Wayland/Vulkan
# client libs (some only Recommended) and render offscreen via Mesa's CPU
# Vulkan (lavapipe in mesa-vulkan-drivers) -- install those explicitly
# instead of all Recommends (xdg-desktop-portal, cups, pipewire, ...).
# shellcheck disable=SC2086
apt install -y $PINS --no-install-recommends \
	mesa-vulkan-drivers libegl-mesa0 libwayland-client0 libx11-6 libx11-xcb1 \
	libxcursor1 libxi6 libxrandr2 fonts-dejavu-core

# Make sure every pinned version is what got installed
for pin in $STORYTOLD_PINS; do
	dpkg-query -W -f='${Version}\n' "${pin%%=*}" | grep -qxF "${pin#*=}"
done

rm -rf /var/lib/apt/lists/*

# mcp-proxy (stdio -> streamable HTTP/SSE) in its own venv
python3 -m venv /opt/mcp-proxy
/opt/mcp-proxy/bin/pip install --no-cache-dir "mcp-proxy${MCP_PROXY_VERSION:+==$MCP_PROXY_VERSION}"
ln -s /opt/mcp-proxy/bin/mcp-proxy /usr/local/bin/mcp-proxy

# Runs under an arbitrary compose `user:` (the codingenv PUID) -- give it a
# writable HOME for the apps' config/autosave dirs.
mkdir -p /home/mcp /etc/mcp-proxy
chmod 1777 /home/mcp

# ubuntu:26.04 ships /usr/bin/pebble (Canonical's container init) as a plain
# unregistered binary built with Go 1.26.5, which carries unpatched HIGH CVEs
# (e.g. CVE-2026-33818). This image never runs pebble -- its entrypoint
# starts mcp-proxy directly -- so drop it instead of scanning around it.
# Re-evaluate (and re-add) if an ubuntu:26.04 point release ships pebble
# built with Go >= 1.26.6 and it becomes load-bearing.
rm -f /usr/bin/pebble
EORUN

ENV HOME=/home/mcp \
    WORK_DIR=/home/sandbox/work \
    MCP_SERVICE_HOST=storytold-mcp \
    MCP_SERVERS_FILE=/tmp/mcp-servers.json

COPY files/app-args.conf /etc/mcp-proxy/
COPY --chmod=755 files/mcp-servers /usr/local/bin/
COPY --chmod=755 files/entrypoint.sh /

# Probe every installed <app>-cli once, so the served set is fixed per
# image (and visible in the build log). The probe's WORK_DIR is a throwaway.
# The installed versions go next to it for `docker run ... cat`.
RUN WORK_DIR=/tmp/mcp-probe mcp-servers detect \
 && rm -rf /tmp/mcp-probe /home/mcp/* /home/mcp/.[!.]* \
 && { dpkg-query -W -f='${Package}=${Version}\n' '*craft'; \
      echo "mcp-proxy=$(/opt/mcp-proxy/bin/pip show mcp-proxy | awk '$1=="Version:"{print $2}')"; } \
    > /etc/mcp-proxy/versions.txt

WORKDIR /home/sandbox/work
EXPOSE 8080/tcp

ENTRYPOINT [ "tini", "--", "/entrypoint.sh" ]
HEALTHCHECK --start-period=60s CMD curl -fsS http://127.0.0.1:8080/status || exit 1
