# Railway-tuned CISO Assistant backend (Django + gunicorn + huey).
#
# Pinned to a release tag rather than `latest`: the container runs
# `manage.py migrate` unconditionally on every start and Django migrations are
# not reversed automatically, so tracking `latest` turns every redeploy into an
# unrequested, one-way upgrade of the deployer's database.
FROM ghcr.io/intuitem/ciso-assistant-community/backend:v3.21.0

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY railway-seed.py /usr/local/bin/railway-seed.py
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# Baked, NOT published as template variables: templateGenerate drops a variable
# whose default is a literal and republishes it as a blank REQUIRED field on the
# deploy form. Only values that genuinely belong to the deployer stay variables,
# and those are Railway expressions.
#
# The image runs as root (upstream leaves `USER app` commented out), so HOME and
# the XDG paths are pointed at /tmp exactly as upstream's compose file does —
# the application writes caches there and /code is not writable in every layer.
ENV HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache \
    XDG_CONFIG_HOME=/tmp/.config \
    XDG_DATA_HOME=/tmp/.local/share \
    DJANGO_DEBUG=False \
    DJANGO_SUPERUSER_EMAIL=admin@ciso.local \
    SQLITE_FILE=/code/db/ciso-assistant.sqlite3 \
    LOCAL_STORAGE_DIRECTORY=/code/db/attachments \
    AUTH_TOKEN_TTL=7200

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
