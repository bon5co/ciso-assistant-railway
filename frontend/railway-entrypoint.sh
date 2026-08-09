#!/usr/bin/env bash
# Railway wrapper entrypoint for the CISO Assistant frontend + gateway.
#
#   1. Start SvelteKit on a FIXED internal port. Railway injects PORT into every
#      service and adapter-node honours it, so without pinning it the node
#      server would take the same port nginx must bind.
#   2. Bind nginx to the INJECTED port. Railway's HTTP healthcheck dials the
#      injected port rather than the domain's target port, so the public
#      listener has to be there and nowhere else.
#   3. Resolve the backend over Railway's private network. nginx needs an
#      explicit resolver for a runtime-variable upstream, and the private
#      domains are IPv6-only, so the nameserver is read out of resolv.conf
#      rather than hardcoded.
set -euo pipefail

export NGINX_PORT="${PORT:-8080}"
export FRONTEND_NODE_PORT="${FRONTEND_NODE_PORT:-3000}"
export BACKEND_PORT="${BACKEND_PORT:-8080}"

: "${BACKEND_HOST:?BACKEND_HOST must be the private domain of the backend service}"
export BACKEND_HOST

NGINX_RESOLVER=""
NGINX_RESOLVER="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
if [[ -z ${NGINX_RESOLVER:-} ]]; then
	NGINX_RESOLVER="fd12::10"
fi
case "${NGINX_RESOLVER}" in
*:*) NGINX_RESOLVER="[${NGINX_RESOLVER}]" ;;
esac
export NGINX_RESOLVER

# --- V8 heap from the cgroup, not the baked 10 GB ----------------------------
if [[ -z ${NODE_OPTIONS:-} ]]; then
	heap=1024
	if [[ -r /sys/fs/cgroup/memory.max ]]; then
		limit="$(cat /sys/fs/cgroup/memory.max)"
		if [[ ${limit} != "max" ]]; then
			heap=$((limit / 1024 / 1024 * 70 / 100))
		fi
	fi
	[[ ${heap} -ge 256 ]] || heap=256
	export NODE_OPTIONS="--max-old-space-size=${heap}"
	echo "[railway] node heap ceiling ${heap} MB"
fi

mkdir -p /tmp/nginx-body /tmp/nginx-proxy /tmp/nginx-fastcgi /tmp/nginx-uwsgi /tmp/nginx-scgi

cat >/etc/nginx/railway-proxy-headers.conf <<'EOF'
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $ciso_scheme;
proxy_set_header X-Forwarded-Host $host;
EOF

envsubst '${NGINX_PORT} ${NGINX_RESOLVER} ${BACKEND_HOST} ${BACKEND_PORT} ${FRONTEND_NODE_PORT}' \
	</etc/nginx/railway.conf.template >/etc/nginx/nginx.conf

nginx -t

echo "[railway] gateway :${NGINX_PORT} -> node :${FRONTEND_NODE_PORT}, /api -> ${BACKEND_HOST}:${BACKEND_PORT}"

PORT="${FRONTEND_NODE_PORT}" HOST=127.0.0.1 node server &
node_pid=$!

trap 'kill -TERM "${node_pid}" 2>/dev/null || true' TERM INT

exec nginx -g 'daemon off;'
