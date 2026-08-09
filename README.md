# ciso-assistant-railway

Railway-tuned wrapper images for [CISO Assistant](https://github.com/intuitem/ciso-assistant-community)
(GRC: risk register, compliance frameworks, audits, evidence, incidents).

Two images, both pinned to upstream **v3.21.0**:

| Image | Base | Role |
|---|---|---|
| `ghcr.io/bon5co/ciso-assistant-railway-backend` | `…/backend:v3.21.0` | Django + gunicorn + huey, SQLite and attachments on one volume |
| `ghcr.io/bon5co/ciso-assistant-railway-frontend` | `…/frontend:v3.21.0` | SvelteKit + an in-container nginx gateway (replaces upstream's separate Caddy service) |

What the wrappers change, and why:

**Backend**

* Refuses to boot without `DJANGO_SUPERUSER_PASSWORD`. Upstream only calls
  `createsuperuser` when `DJANGO_SUPERUSER_EMAIL` is set, and
  `create_superuser(password=None)` produces an account with an unusable
  password. CISO Assistant has no self-registration, so both cases leave a
  healthy instance nobody can ever log in to.
* Creates **or repairs** the admin account before gunicorn binds. Upstream's
  `createsuperuser --noinput` fails on every boot after the first, so a changed
  password never reaches the database; `railway-seed.py` sets it every boot.
* Runs huey under a restart loop instead of `… &`. A dead worker would
  otherwise be invisible: the healthcheck only probes gunicorn.
* Sizes gunicorn's workers from `/sys/fs/cgroup/cpu.max` rather than upstream's
  hardcoded 3.
* SQLite, huey's queue, the Django secret key and uploaded attachments all live
  under `/code/db`, which is the one mounted volume.

**Frontend**

* Folds upstream's Caddy into this container as nginx, so a deploy is two
  billed services rather than three. The backend documents that it manages no
  CORS headers at all, so frontend and API must answer on one origin.
* Binds nginx to Railway's injected `$PORT` and pins the SvelteKit server to an
  internal port. Railway's HTTP healthcheck dials the injected port, not the
  domain's target port, so the public listener has to be there.
* Rate limits the allauth login endpoint to 10 requests a minute per client,
  keyed on the **first** address of `X-Forwarded-For` (Railway's edge rotates
  the last hop, and `$remote_addr` is always the edge). Upstream ships no login
  throttle of any kind.
* Recomputes the V8 heap ceiling from `/sys/fs/cgroup/memory.max`; the upstream
  image bakes `--max-old-space-size=10240`.

Built and pushed by `.github/workflows/build.yml` on every push to `main`.
