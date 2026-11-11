# Handoff

Last updated: 2026-11-11

## Read first

1. `DESIGN.md`: the spec. Build order is in §8.
2. `AGENTS.md`: how to work here (Docker-only commands, invariants, testing expectations).
3. `backend/AGENTS.md`: Phoenix 1.8's generated Elixir/Ecto rules. Skip its HTML/LiveView/asset sections.

## Status

| Build step (DESIGN.md §8) | State |
|---|---|
| 1. Scaffold Phoenix + Vite, Postgres via compose | **Done** (commit `be5d216`) |
| 2. Migrations + Ecto schemas | **Next** |
| 3–9 | Not started |

Verified at the end of step 1: `mix test` (2 tests) and `npm test` (1 test) pass, plus `npm run typecheck` and `npm run lint`, all in containers. `docker compose up` serves Vite on :5173, and its `/api` requests reach Phoenix on :4000 (404, since no routes exist yet).

## Environment facts

- Images: `elixir:1.19` (Phoenix 1.8, `phx_new` baked in), `node:24-alpine`, `postgres:17`. Dockerfiles are in `docker/`.
- `_build`, `deps`, and `node_modules` are named volumes. Host checkouts have none of them, so run `mix deps.get` / `npm install` in the container after dependency changes.
- Required env vars (config fails without them, by design): `DATABASE_HOST` (backend dev/test config), `BACKEND_URL` (Vite dev-server proxy only; not needed under Vitest).
- Don't set `MIX_ENV` in compose, or `mix test` runs against the dev env and crashes.
- Dev tokens: `TASKTREE_TOKENS` defaults to `dev-human=human:dev,dev-agent=agent:dev` (not yet consumed; the auth plug is step 7).
- Frontend: React 19, Vite 8, TypeScript 7, Vitest 5, oxlint. Deps already installed but unused: `@tanstack/react-query`, `react-router`.

## Step 2 checklist (next)

- Migrations: `nodes`, `edges`, `events` per DESIGN.md §3.1–3.3.
  - ULID string PKs. Pick a ULID library (e.g. `ecto_ulid` or similar) and verify it's maintained before adding it.
  - `nodes`: check constraint making `claimed_by`/`claim_expires_at` both null or both set. Indexes: `(parent_id, position)`, `state`, GIN on `tags`, GIN on `fields`.
  - `edges`: unique `(from_id, to_id, kind)`, check `from_id <> to_id`, `kind` limited to `blocks`/`relates`.
  - `events`: `seq` bigserial PK, no FK on `node_id`, plus a trigger that raises on UPDATE/DELETE.
- Ecto schemas for all three.
- Tests: constraint violations surface as errors, and UPDATE/DELETE on `events` fails at the DB level (acceptance criterion in §10).

## Open items / deferred decisions

- Production SPA build: Vite `build.outDir` → `backend/priv/static`, plus Phoenix's `index.html` fallback for non-`/api` routes. Deferred to step 8. The frontend container only mounts `frontend/`, so this needs a mount or a copy step.
- DESIGN.md §7 adds `GET /api/schema` and `allowed_transitions` on nodes. These aren't yet in the §5 endpoint list but should be implemented with it.
- `property tests` for `Tasktree.Position` (step 3) need `stream_data` added to `mix.exs`.
