#!/usr/bin/env bash
# Railway wrapper entrypoint for the CISO Assistant backend.
#
# Four jobs, in this order, all before gunicorn binds a port:
#
#   1. Refuse to boot when no admin password was supplied. Upstream's
#      startup.sh only runs `createsuperuser` when DJANGO_SUPERUSER_EMAIL is
#      set, and `create_superuser(password=None)` produces an account with an
#      unusable password. CISO Assistant has no self-registration, so either
#      case leaves a healthy instance nobody can log in to and no reset path.
#   2. Make the durable directories on the mounted volume: the SQLite database,
#      the huey queue and the uploaded attachments all live under /code/db.
#   3. Create OR REPAIR the admin account before anything listens.
#      `createsuperuser --noinput` fails on the second boot ("email already
#      exists"), so a rotated password would never take effect; the seed script
#      sets the password every boot instead.
#   4. Size gunicorn's worker count from the container's CPU quota. Upstream
#      hardcodes 3 workers regardless of plan.
#
# Then hand over to upstream's own startup.sh, which runs `migrate` (a no-op
# after step 3 already ran it), `storelibraries` and gunicorn. The superuser
# environment is cleared first so upstream's own createsuperuser branch is
# skipped and cannot log an error over our seeded account.
set -euo pipefail

cd /code

: "${DJANGO_SUPERUSER_EMAIL:?admin email is required}"
if [[ -z ${DJANGO_SUPERUSER_PASSWORD:-} ]]; then
	echo "[railway] DJANGO_SUPERUSER_PASSWORD is empty." >&2
	echo "[railway] CISO Assistant has no sign-up page, so booting without an" >&2
	echo "[railway] admin password would publish an instance that nobody can" >&2
	echo "[railway] ever log in to. Set it in the service variables." >&2
	exit 1
fi

mkdir -p /code/db/attachments

# --- gunicorn workers from the cgroup quota ---------------------------------
if [[ -z ${GUNICORN_WORKERS:-} ]]; then
	cpus=1
	if [[ -r /sys/fs/cgroup/cpu.max ]]; then
		read -r quota period </sys/fs/cgroup/cpu.max || true
		if [[ ${quota:-max} != "max" && ${period:-0} -gt 0 ]]; then
			cpus=$(((quota + period - 1) / period))
		fi
	fi
	[[ $cpus -ge 1 ]] || cpus=1
	workers=$((2 * cpus + 1))
	[[ $workers -le 9 ]] || workers=9
	export GUNICORN_WORKERS="$workers"
	echo "[railway] cpu=${cpus} gunicorn_workers=${GUNICORN_WORKERS}"
fi

# --- migrations + admin account, before the listener ------------------------
echo "[railway] applying migrations"
python manage.py migrate --noinput

echo "[railway] seeding the admin account"
python /usr/local/bin/railway-seed.py

# --- huey, supervised -------------------------------------------------------
# Upstream's compose file runs huey as its own always-restarting container. The
# only way to keep it inside one Railway service is to run it here, and a bare
# `... &` would make a dead worker invisible: the healthcheck only probes
# gunicorn, so scheduled jobs would stop with the deploy still green.
(
	while true; do
		python manage.py run_huey -w 2 --scheduler-interval 60 || true
		echo "[railway] huey exited (rc=$?), restarting in 5s" >&2
		sleep 5
	done
) &

unset DJANGO_SUPERUSER_EMAIL DJANGO_SUPERUSER_PASSWORD

exec uv run bash startup.sh
