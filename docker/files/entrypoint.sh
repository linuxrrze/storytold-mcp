#!/bin/bash
# Render the named-server config for this WORK_DIR, then serve every
# detected stdio MCP server over HTTP via mcp-proxy:
#   http://<container>:8080/servers/<app>/mcp   (streamable HTTP)
#   http://<container>:8080/servers/<app>/sse   (legacy SSE)
# Kept identical in storytold-mcp/ and solidcraft-mcp/ -- edit both.
set -euo pipefail

if [ ! -d "$WORK_DIR" ] || [ ! -w "$WORK_DIR" ]; then
	echo "entrypoint: WORK_DIR=$WORK_DIR is missing or not writable for uid $(id -u)" \
		"-- mount the shared work dir there (see docker-compose.yml.sample)" >&2
	exit 1
fi

mcp-servers render

# mcp-proxy >= 0.14 rejects (421) any Host header but loopback when bound to
# 0.0.0.0 -- trust the service name clients use (MCP_SERVICE_HOST), plus any
# extra space-separated authorities in MCP_ALLOWED_HOSTS (host or host:port).
allowed_hosts=()
for h in "$MCP_SERVICE_HOST" ${MCP_ALLOWED_HOSTS:-}; do
	allowed_hosts+=(--allowed-host "$h")
	[[ $h == *:* ]] || allowed_hosts+=(--allowed-host "$h:*")
done

# --pass-environment: named servers otherwise start without HOME/WORK_DIR.
# Servers run with WORK_DIR as cwd, so relative paths land in the shared dir.
cd "$WORK_DIR"
exec mcp-proxy \
	--host 0.0.0.0 --port 8080 \
	"${allowed_hosts[@]}" \
	--pass-environment \
	--log-level "${MCP_LOG_LEVEL:-INFO}" \
	--named-server-config "$MCP_SERVERS_FILE" \
	"$@"
