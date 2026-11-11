# AGENTS.md

Guidance for coding agents working on Tasktree. `DESIGN.md` is the spec. Read it before changing behavior. If the code and the spec disagree, raise it; don't silently pick one.

## Layout

```
backend/    Elixir/Phoenix JSON API (app: :tasktree, modules Tasktree.* / TasktreeWeb.*)
frontend/   React + TypeScript (Vite, TanStack Query, React Router)
docker/     Dev Dockerfiles
compose.yaml
DESIGN.md   Spec (source of truth for behavior)
```

## Everything runs in Docker

Don't run `mix`, `npm`, `node`, or `psql` on the host. Use compose:

```sh
docker compose up -d db                       # Postgres only
docker compose up                             # db + backend (:4000) + frontend (:5173)
docker compose run --rm backend mix test      # backend tests (MIX_ENV is overridden to test by mix)
docker compose run --rm backend mix <task>    # any mix task (deps.get, ecto.migrate, format, ...)
docker compose run --rm frontend npm test     # frontend tests (Vitest)
docker compose run --rm frontend npm <cmd>    # any npm command
```

Notes:
- `_build`, `deps`, and `node_modules` live in named volumes, not on the host. After changing `mix.exs` or `package.json`, run `mix deps.get` / `npm install` in the container.
- Backend talks to Postgres at host `db` (`DATABASE_HOST`). The Vite dev server proxies `/api` to `BACKEND_URL` (`http://backend:4000`).
- Dev auth tokens come from `TASKTREE_TOKENS` in `compose.yaml` (`dev-human` → `human:dev`, `dev-agent` → `agent:dev`).
- If a fresh DB is needed: `docker compose down -v` wipes **all** volumes, including the DB. Ask before doing this if the DB holds anything you didn't create.

## Working rules

- Follow the build order in DESIGN.md §8. Each step leaves `mix test` and `npm test` green.
- Run the smallest relevant test set after a change (`mix test test/path_test.exs`), then broaden as needed.
- Run `mix format` on backend changes. Run the frontend typecheck/lint on frontend changes.
- Commit in small, coherent steps with descriptive messages. Don't commit secrets, build output, or `node_modules`.

## Invariants (from DESIGN.md; don't weaken them)

- **Never default invalid input.** Unknown fields, bad types, illegal transitions, missing `If-Match`, and malformed workflow config are errors (`422`/`428`/boot failure), never silently corrected.
- **Every mutation writes its event in the same transaction** (`Ecto.Multi`/`Repo.transaction`). Only `Tasktree.Nodes` (and `Tasktree.Edges` for edges) write nodes, edges, or events.
- Events are append-only, and a DB trigger enforces this. Never add code that updates or deletes events.
- The actor always comes from the bearer token, never from the request body.
- Controllers hold no business logic. Errors flow as `{:error, reason}` to `FallbackController`, which renders `{"error": {"code", "message", "details"}}`.
- Derived predicates (`blocked`, `claimable`) are SQL, not per-row Elixir.
- The frontend is driven by `GET /api/schema`. Don't hardcode states, transitions, or fields in the UI.
- On `version_conflict`, the UI refetches and notifies. It never auto-overwrites.

## Testing expectations

- Every Nodes/Edges op has a happy-path test and a test for each error code it can return.
- Concurrency tests (claim race, optimistic version) use real concurrent processes against the sandbox in shared mode or with explicit allowances.
- `Tasktree.Position` has property tests (StreamData).
- Controller tests assert the error contract (status and `error.code`).
