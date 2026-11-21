FROM ubuntu:26.04
# Space-separated apt pins, e.g. "cadcraft=0.14.0-1 deckcraft=0.12.0-1 ..."
# (CI passes the repo's newest version of every app). Empty installs every
# app currently in the repo.
ARG STORYTOLD_PINS
ENV UBUNTU_VERSION=26.04

# Official ArtCraft APT repository, see https://getartcraft.com/linux
ENV ARTCRAFT_URL=https://getartcraft.com

RUN << EORUN
set -e
# Skip docs/man pages -- pure image-size trimming, has to be in place before
# the first package unpacks anything under /usr/share.
{ echo 'path-exclude=/usr/share/doc/*'; \
  echo 'path-exclude=/usr/share/man/*'; \
  echo 'path-exclude=/usr/share/groff/*'; \
  echo 'path-exclude=/usr/share/info/*'; } > /etc/dpkg/dpkg.cfg.d/01_nodoc

apt update && apt -y dist-upgrade
apt install -y ca-certificates curl python3 tini --no-install-recommends

# Add the official ArtCraft repo (signing key fingerprint
# 2B76741B414AAD6CD33E631213A005C0B9D7C3ED). apt verifies the signed
# InRelease; the .debs are served from the apps' GitHub release assets.
install -d -m 755 /etc/apt/keyrings
curl -fsSL "$ARTCRAFT_URL/keys/artcraft.gpg" -o /etc/apt/keyrings/artcraft.gpg
chmod 644 /etc/apt/keyrings/artcraft.gpg
curl -fsSL "$ARTCRAFT_URL/apt/artcraft.sources" -o /etc/apt/sources.list.d/artcraft.sources
apt update

PINS="$STORYTOLD_PINS"
if [ -z "$PINS" ]; then
	# Every app in the repo; artcraft-launcher is a GUI-only installer,
	# craft-anything is excluded for now (same list as the workflow's).
	PINS=$(awk '/^Package:/ && $2 != "artcraft-launcher" && $2 != "craft-anything" { print $2 }' \
		/var/lib/apt/lists/*getartcraft.com_apt_*_Packages | sort -u)
fi
# Headless MCP needs no display, but the apps link the X11/Wayland/Vulkan
# client libs (some only Recommended) and render offscreen via Mesa's CPU
# Vulkan (lavapipe in mesa-vulkan-drivers) -- install those explicitly
# instead of all Recommends (xdg-desktop-portal, cups, pipewire, ...).
# The .debs are kept in their own dir until the checks below are done
# (ubuntu's docker-clean hook empties /var/cache/apt/archives after every
# install). apt names each one after its index entry: <pkg>_<version>_<arch>.deb.
# apt-get, not apt: apt deletes the .debs right after installing them.
DEBS=/var/cache/apt/storytold
mkdir -p "$DEBS/partial"
# shellcheck disable=SC2086
apt-get install -y $PINS --no-install-recommends \
	-o Dir::Cache::Archives="$DEBS/" -o APT::Keep-Downloaded-Packages=true \
	mesa-vulkan-drivers libegl-mesa0 libwayland-client0 libx11-6 libx11-xcb1 \
	libxcursor1 libxi6 libxrandr2 fonts-dejavu-core

# What an index package got installed as: `<package>=<version>`. Normally its
# own name, but the index and the .deb can disagree -- e.g. the index's
# artcraft 0.41.1-1 is a .deb with Package: art-craft, Version: 0.41.1 --
# then dpkg only knows the .deb's name, so read that from the .deb.
installed_as() {
	if dpkg-query -W -f='${Package}=${Version}\n' "$1" 2>/dev/null; then
		return
	fi
	set -- "$1" "$DEBS/$1"_*.deb
	[ $# = 2 ] && [ -f "$2" ] || { echo "no installed package or .deb for $1" >&2; return 1; }
	set -- "$1" "$(dpkg-deb -f "$2" Package)"
	echo "WARNING: index package $1 is installed as $2" >&2
	dpkg-query -W -f='${Package}=${Version}\n' "$2"
}

# Make sure every pinned version is what got installed (for a renamed .deb:
# the pinned version minus its Debian revision, as the .deb drops it too)
for pin in $STORYTOLD_PINS; do
	got=$(installed_as "${pin%%=*}")
	if [ "${got%%=*}" = "${pin%%=*}" ]; then
		[ "$got" = "$pin" ]
	else
		want=${pin#*=}
		[ "${got#*=}" = "$want" ] || [ "${got#*=}" = "${want%-*}" ]
	fi || { echo "pinned $pin, installed $got" >&2; exit 1; }
done
# Installed app versions, for `docker run ... cat`.
# Package names, not a '*craft' glob: an app isn't bound to be named *craft.
mkdir -p /etc/mcp-gateway
for pin in $PINS; do
	installed_as "${pin%%=*}"
done > /etc/mcp-gateway/versions.txt

rm -rf /var/lib/apt/lists/* "$DEBS"

# Runs under an arbitrary compose `user:` (the agent-env PUID) -- give it a
# writable HOME for the apps' config/autosave dirs.
mkdir -p /home/mcp
chmod 1777 /home/mcp

# ubuntu:26.04 ships /usr/bin/pebble (Canonical's container init) as a plain
# unregistered binary built with Go 1.26.5, which carries unpatched HIGH CVEs
# (e.g. CVE-2026-33818). This image never runs pebble -- its entrypoint
# starts mcp-gateway directly -- so drop it instead of scanning around it.
# Re-evaluate (and re-add) if an ubuntu:26.04 point release ships pebble
# built with Go >= 1.26.6 and it becomes load-bearing.
rm -f /usr/bin/pebble
EORUN

ENV HOME=/home/mcp \
    WORK_DIR=/home/sandbox/work \
    MCP_SERVICE_HOST=storytold-mcp \
    MCP_SERVERS_FILE=/tmp/mcp-servers.json

COPY files/app-args.conf /etc/mcp-gateway/
COPY --chmod=755 files/mcp-servers files/mcp-gateway /usr/local/bin/
COPY --chmod=755 files/entrypoint.sh /

# Probe every installed <app>-cli once, so the served set is fixed per
# image (and visible in the build log). The probe's WORK_DIR is a throwaway;
# the discovery cache (initialize + tool lists, so mcp-gateway starts a
# server only on first use) is probed with the real WORK_DIR, as some apps
# name their allowed folders in it.
RUN MCP_CACHE_WORK_DIR="$WORK_DIR" WORK_DIR=/tmp/mcp-probe mcp-servers detect \
 && rm -rf /tmp/mcp-probe /home/mcp/* /home/mcp/.[!.]*

WORKDIR /home/sandbox/work
EXPOSE 8080/tcp

ENTRYPOINT [ "tini", "--", "/entrypoint.sh" ]
HEALTHCHECK --start-period=60s CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1
