# Railway-tuned CISO Assistant frontend, with the reverse proxy folded in.
#
# Upstream's compose file puts a separate Caddy container in front of the
# SvelteKit frontend and the Django backend so that both answer on ONE origin —
# the backend documents that it manages no CORS headers at all, so a split-origin
# deploy cannot log in. On Railway a separate proxy is a third billed service
# for a job that fits in this container, so nginx runs here instead.
#
# Pinned to a release tag: the frontend build must match the backend's API.
FROM ghcr.io/intuitem/ciso-assistant-community/frontend:v3.21.0

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx gettext-base curl \
    && rm -rf /var/lib/apt/lists/*

COPY nginx.conf.template /etc/nginx/railway.conf.template
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# Baked, NOT published as template variables (a literal default publishes as a
# blank required field on the deploy form).
#
# NODE_OPTIONS is deliberately cleared here and recomputed at boot from
# /sys/fs/cgroup/memory.max: the upstream image bakes
# --max-old-space-size=10240, i.e. a 10 GB V8 heap ceiling inside containers
# that are routinely smaller than that, which turns an OOM into a kill instead
# of a garbage collection.
ENV NODE_OPTIONS="" \
    NODE_ENV=production \
    HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache \
    XDG_CONFIG_HOME=/tmp/.config \
    XDG_DATA_HOME=/tmp/.local/share \
    PROTOCOL_HEADER=x-forwarded-proto \
    HOST_HEADER=x-forwarded-host \
    BODY_SIZE_LIMIT=50000000 \
    FRONTEND_NODE_PORT=3000 \
    BACKEND_PORT=8080

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
