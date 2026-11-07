#!/bin/bash
# Render the named-server config for this WORK_DIR, then serve every
# detected stdio MCP server over streamable HTTP via mcp-gateway:
#   http://<container>:8080/servers/<app>/mcp
# Each MCP session gets its own server process, started on the session's
# first real request (initialize and tool lists come from the build-time
# discovery cache, MCP_LAZY) and stopped when the session ends or idles
# (MCP_IDLE_TIMEOUT).
# Kept identical in storytold-mcp/ and solidcraft-mcp/ -- edit both.
set -euo pipefail

if [ ! -d "$WORK_DIR" ] || [ ! -w "$WORK_DIR" ]; then
	echo "entrypoint: WORK_DIR=$WORK_DIR is missing or not writable for uid $(id -u)" \
		"-- mount the shared work dir there (see docker-compose.yml.sample)" >&2
	exit 1
fi

mcp-servers render

# Only requests whose Host header is the service name clients use
# (MCP_SERVICE_HOST) or loopback are accepted; mcp-gateway adds the extra
# entries of MCP_ALLOWED_HOSTS (host = any port, or host:port) itself.
# Servers run with WORK_DIR as cwd, so relative paths land in the shared dir.
cd "$WORK_DIR"
exec mcp-gateway \
	--host 0.0.0.0 --port 8080 \
	--allowed-host "$MCP_SERVICE_HOST" \
	--config "$MCP_SERVERS_FILE" \
	"$@"
