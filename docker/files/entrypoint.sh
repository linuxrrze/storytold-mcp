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

# --pass-environment: named servers otherwise start without HOME/WORK_DIR.
# Servers run with WORK_DIR as cwd, so relative paths land in the shared dir.
cd "$WORK_DIR"
exec mcp-proxy \
	--host 0.0.0.0 --port 8080 \
	--pass-environment \
	--log-level "${MCP_LOG_LEVEL:-INFO}" \
	--named-server-config "$MCP_SERVERS_FILE" \
	"$@"
