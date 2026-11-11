# Handoff

Last updated: 2026-11-11

## Read first

1. `DESIGN.md`: the spec. Build order is in §8.
2. `AGENTS.md`: how to work here (Docker-only commands, invariants, testing expectations).
3. `backend/AGENTS.md`: Phoenix 1.8's generated Elixir/Ecto rules. Skip its HTML/LiveView/asset sections.

## Status

| Build step (DESIGN.md §8) | State |
|---|---|
| 1–7 (scaffold, schema, Workflow/Position, Nodes/Events/Edges, Queries, HTTP API) | **Done** |
| 8. Frontend (client, Login, Outline, Node page, Agenda) | **Done** |
| 9. `docs/AGENTS.md` curl examples | **Done** (flow verified against a live backend) |

Verified: `mix test` (129+ tests) in Docker; `npm test` (26), `npm run typecheck`, `npm run lint`, `npm run build` in Docker. Backend and UI were exercised over HTTP, but the UI was never driven in a real browser (only jsdom tests with a mocked fetch).

## Environment facts

- Images: `elixir:1.19`, `node:24-alpine`, `postgres:17`. `_build`, `deps`, `node_modules` are named volumes.
- Required env: `DATABASE_HOST`, `BACKEND_URL` (Vite proxy), `TASKTREE_TOKENS` (outside test; compose defaults `dev-human=human:dev,dev-agent=agent:dev`).
- Don't set `MIX_ENV` in compose.
- `nodes_concurrency_test.exs` commits real data (separate connections), so it leaves a few `events` rows in the test DB; the append-only trigger prevents deleting them. Harmless; keyed by unique node ids.

## Decisions made along the way (all flagged to the user at the time)

- ULID generator is in-repo (`Tasktree.ULID`), no dependency.
- `nodes.position` has `COLLATE "C"` so keys sort bytewise.
- Edge add/remove writes one event per endpoint node. Edge changes don't bump node versions.
- `claim`/`release` bump `version`. A no-op update writes nothing.
- `version_conflict` puts the current node at `details.current`.
- Tree `depth` counts levels including the top. The UI requests `depth=50`.
- Added `GET /api/me` (DESIGN.md §7 updated) for login validation and the human-only "steal claim" button.
- Expired claims render as `claimed_by: null` in JSON.

## Open items / deferred decisions

- **Production SPA build** (not done, not in the §8 steps or §10 acceptance criteria): Vite `build.outDir` -> `backend/priv/static`, plus a Phoenix `index.html` fallback for non-`/api` routes. The frontend container only mounts `frontend/`, so this needs a mount or a copy step. `npm run build` itself works.
- UI has never been driven in a real browser; walk the §10 flow by hand (`docker compose up`, open :5173, log in with `dev-human`).
- Outline can't show an expander for nodes at the tree depth cutoff (no child-count in the API); irrelevant while the UI requests depth 50.
- States in `/api/schema` are sorted by name (workflow config is a map). Add an explicit order to the config if the UI should show a canonical order.
- The dev DB contains two nodes created by smoke tests ("smoke", "doc-example").
