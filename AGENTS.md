# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is (and what can run here)

Kaido is a **native iOS / SwiftUI app** (see `README.md`). Building or running the app and the
`KaidoTests` unit tests requires **macOS + Xcode 26 + XcodeGen** (`xcodegen generate` →
`xcodebuild`). That toolchain is Apple-only and **cannot run on the Linux Cloud VM** — do not try
`xcodegen`/`xcodebuild` here. For Swift/app/UI/test changes, rely on code review plus the `iOS
Build` GitHub Actions workflow (macOS runner), which builds and runs `KaidoTests` on every push/PR.
There is no Swift linter configured (no SwiftLint/SwiftFormat).

The **only component that runs on the Linux VM is the Supabase backend** — the "Ride Together"
schema, RPCs, and RLS policies in `supabase/migrations/0001_group_rides.sql`. That is the piece to
exercise for any server-side / SQL change.

### Running the Supabase backend locally (Linux VM)

Docker and the Supabase CLI are preinstalled in the VM image. Two things are **not** automatic and
must be done by hand each session (they are service startup, intentionally kept out of the update
script):

1. **Start the Docker daemon** (it does not auto-start). Run it in a background tmux session:
   `sudo dockerd`. Docker is configured for docker-in-docker via `/etc/docker/daemon.json`
   (`storage-driver: fuse-overlayfs` + `features.containerd-snapshotter: false`) — both are
   **required** for Docker 29 + fuse-overlayfs on this VM; do not remove them.
2. **Start the stack** from the repo root: `supabase start` (uses `supabase/config.toml`). This
   pulls several images the first time. Endpoints: Studio `http://127.0.0.1:54323`, REST/Auth API
   `http://127.0.0.1:54321`, Postgres `postgresql://postgres:postgres@127.0.0.1:54322/postgres`.
   If `supabase/config.toml` is missing (e.g. this setup PR wasn't merged), run `supabase init
   --force` first.

### Non-obvious gotcha: applying the migration needs a superuser

`supabase start` / `supabase db reset` apply migrations as a **non-superuser** role, which **fails**
on the last statements of `0001_group_rides.sql` (`alter table realtime.messages enable row level
security` and the two `realtime.messages` policies) with `must be owner of table messages`. On a
failed migration, `supabase start` tears the DB container down, so you get no usable database. The
public-schema tables, RPCs, and RLS (everything except the `realtime.messages` block) apply fine.

Reliable local workaround — apply the migration as the `supabase_admin` superuser (it bypasses the
ownership check; this is a local-dev quirk, hosted Supabase applies the realtime policies
differently):

```
# from repo root, with dockerd running
mv supabase/migrations/0001_group_rides.sql /tmp/            # let the DB come up clean
supabase start
mv /tmp/0001_group_rides.sql supabase/migrations/            # restore (keep the repo unchanged)
docker exec -i supabase_db_workspace psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 \
    < supabase/migrations/0001_group_rides.sql
```

The default table grants for `anon`/`authenticated`/`service_role` are applied automatically even
though `supabase_admin` created the tables, so RLS is still the effective gate.

### Verifying Ride Together (RLS/RPC)

`supabase/verification/ride_together_rls_check.sql` documents the intended scenarios. To impersonate
a user from `psql`, the rows must first exist in `auth.users`, then set the RLS context per
statement/session:

```
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"<user-uuid>","role":"authenticated"}', false);
```

To exercise the same logic over the real HTTP surface the iOS app uses (PostgREST at
`http://127.0.0.1:54321`), sign an HS256 JWT with the local JWT secret
(`super-secret-jwt-token-with-at-least-32-characters-long`) carrying `{"sub":"<uuid>","role":
"authenticated"}`, send it as `Authorization: Bearer`, and send the local `anon` key as the
`apikey` header.
