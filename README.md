# Tasktree

What if org-mode were a structured data tree, rather than a text file?

Tasktree stores an outline of task nodes in a database. Each node has a stable ID, a workflow
state, typed fields, tags and a markdown body. Nodes can depend on each other through `blocks`
edges, and every change is recorded in an append-only event log with the actor who made it.
Humans use the web UI; agents use the same operations over an HTTP JSON API, and claim tasks
with leases so two agents don't pick up the same work.

- Backend: Elixir / Phoenix JSON API, PostgreSQL
- Frontend: React + TypeScript (Vite, TanStack Query, TipTap)

## Quick start

Everything runs in Docker. You need Docker with Compose.

```sh
docker compose up
```

This starts Postgres, the backend on <http://localhost:4000> (it runs migrations on start), and
the UI on <http://localhost:5173>.

Open <http://localhost:5173> and log in with a token:

| Token | Actor |
|---|---|
| `dev-human` | `human:dev` |
| `dev-agent` | `agent:dev` |

Set `TASKTREE_TOKENS` to use your own (`token=human:name,token2=agent:name`). The backend refuses
to start if it's missing or malformed.

## Using it

**Outline** (`/`): the whole tree.

- Click a title to edit it. Click a note to edit it in a rich-text editor. Changes save as you go.
- Keyboard:
  - **Enter:** new sibling.
  - **Tab / Shift+Tab:** indent / outdent.
  - **↑ ↓:** move between titles.
  - **Ctrl/⌘+↓:** edit the note.
  - **Esc:** stop editing.
- Notes with tables, checklists or raw HTML open as plain markdown, so editing can't change their meaning.
- If someone else changed a node while you were editing, you choose **Keep mine** or **Take theirs**. Nothing is overwritten silently.

**Node page** (`/n/:id`, via the ↗ link on a row):

- Fields, tags and markdown body.
- Edges ("this blocks…", "blocked by…", "relates to…").
- Claim and release. Humans can also steal a claim.
- Move, and the full history.

**Agenda** (`/agenda`): what's claimable, what's in progress, and what's blocked.

States, transitions and fields come from the workflow config (`backend/priv/workflow.exs`), which
is validated at boot. By default: `TODO`, `NEXT`, `DOING`, `DONE` (needs an `outcome`), `CANCELLED`.

## For agents

[`docs/AGENTS.md`](docs/AGENTS.md) walks through the agent loop with curl:

1. Find claimable work.
2. Claim it.
3. Transition it to `DONE` with an `outcome`.
4. Release it.
5. Read the history.

It also covers the error codes.

In short: mutations need `If-Match: <version>`. A missing header is a `428` error, and a stale one is `409 version_conflict`. Errors always have the shape
`{"error": {"code", "message", "details"}}`.

## Development

Don't run `mix`, `npm` or `psql` on the host; use the containers:

```sh
docker compose run --rm backend mix test
docker compose run --rm backend mix format
docker compose run --rm frontend npm test
docker compose run --rm frontend npm run typecheck
docker compose run --rm frontend npm run lint
```

`_build`, `deps` and `node_modules` live in Docker volumes. After changing `mix.exs` or
`package.json`, run `mix deps.get` / `npm install` in the container.

`docker compose down -v` deletes all volumes, **including the database**.

| Path | What |
|---|---|
| `backend/` | Phoenix app. Contexts in `lib/tasktree/`, HTTP layer in `lib/tasktree_web/` |
| `frontend/` | React app. Pages in `src/pages/`, outline editing in `src/outline/` |
| `DESIGN.md` | The spec: data model, API, invariants |
| `AGENTS.md` | Rules for coding agents working on this repo |
| `docs/AGENTS.md` | Guide for agents *using* Tasktree over the API |
| `HANDOFF.md` | Current status, decisions made, open items |

## Status

The MVP is implemented (DESIGN.md §8, steps 1–9), plus inline editing in the outline. Not done yet:

- **Production build:** Phoenix serving the built UI. The UI currently runs from the Vite dev server.

See `HANDOFF.md` for the full list.
