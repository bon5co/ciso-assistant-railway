#!/usr/bin/env python3
"""Create or repair the CISO Assistant admin account before anything listens.

Upstream's startup.sh calls `manage.py createsuperuser --noinput`, which:

  * does nothing at all when DJANGO_SUPERUSER_EMAIL is empty, and
  * fails with "email already exists" on every boot after the first, so a
    changed DJANGO_SUPERUSER_PASSWORD never reaches the database.

Both matter on Railway, where redeploys are routine and the deploy form is the
only place a password is ever typed. This script is idempotent: it creates the
superuser on the first boot and resets its password on every later boot, so the
value shown in the Variables tab is always the value that logs in.
"""

import os
import sys

import django

sys.path.insert(0, "/code")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "ciso_assistant.settings")
django.setup()

from django.contrib.auth import get_user_model  # noqa: E402

email = os.environ.get("DJANGO_SUPERUSER_EMAIL", "").strip()
password = os.environ.get("DJANGO_SUPERUSER_PASSWORD", "")

if not email or not password:
    sys.exit("[railway] refusing to seed an admin without an email and a password")

User = get_user_model()
user = User.objects.filter(email__iexact=email).first()

if user is None:
    User.objects.create_superuser(email=email, password=password)
    print(f"[railway] created admin {email}")
else:
    user.set_password(password)
    user.is_superuser = True
    user.is_active = True
    user.keep_local_login = True
    user.save()
    print(f"[railway] admin {email} already existed; password reset to the current variable")
