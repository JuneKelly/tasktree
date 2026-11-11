# Tasktree: Design Doc (MVP)

Status: design approved in discussion, no code written yet. This doc is meant to be sufficient for an implementing agent to start work.

## 1. Concept

"What if org-mode were a structured data tree, rather than a text file?"

Org-mode is already a tree of typed nodes (heading, TODO state, tags, properties, timestamps, logbook, body) serialized as text. Parsing is lossy and ambiguous, identity is optional, and concurrent edits are unsafe. Tasktree makes the **node** the primary object, stored in a database and mutated through validated operations. Humans use a web UI; agents use the same operations over an HTTP JSON API.

Differences from org-mode that justify the project:

- Stable, mandatory node IDs.
- State machine and typed fields enforced by schema. Invalid input is an error, never silently defaulted.
- A strict outline tree **plus** typed dependency edges (org has no real dependency graph).
- An append-only event log (org's LOGBOOK made first-class), with actor provenance (`human:*` vs `agent:*`).
- Claims (leases) so multiple agents don't take the same task.
- Views are queries, not text-file conventions.

## 2. Stack

| Layer | Choice |
|---|---|
| Backend | Elixir, Phoenix (JSON API only, no LiveView, no HTML templates except the SPA shell) |
| DB | PostgreSQL via Ecto (jsonb, row locking). SQLite is a viable swap but not the default. |
| Frontend | React + TypeScript, built with Vite, TanStack Query for data fetching, React Router |
| Serving | Phoenix serves the built SPA from `priv/static` and falls back to `index.html` for non-`/api` routes. In dev, run Vite dev server with a proxy to Phoenix. |
| Tests | ExUnit (backend), Vitest + Testing Library (frontend) |

Suggested layout (single repo):

```
tasktree/
  backend/    # mix phx.new tasktree --no-html --no-assets --no-live --no-mailer
  frontend/   # vite react-ts
  DESIGN.md
```

## 3. Domain model

### 3.1 Node (`nodes` table)

| Column | Type | Notes |
|---|---|---|
| `id` | ULID (string, PK) | generated server-side |
| `parent_id` | ULID, nullable, FK nodes | null = root. Strict single parent. |
| `position` | string | fractional index (lexicographic order among siblings). See 3.5. |
| `title` | string, required | |
| `body` | text, default `""` | markdown, free-form prose. Empty string is a legitimate value here, since body is optional by contract. |
| `state` | string, required | must exist in workflow; new nodes start in the workflow's `initial` state |
| `fields` | jsonb object | validated against field schema |
| `tags` | text[] | deduplicated, case-sensitive |
| `claimed_by` | string, nullable | actor |
| `claim_expires_at` | utc_datetime_usec, nullable | `claimed_by` and `claim_expires_at` are both null or both set (DB check constraint) |
| `version` | integer, default 1 | incremented on every mutation; used for optimistic concurrency |
| `inserted_at`, `updated_at` | utc_datetime_usec | |

Indexes: `(parent_id, position)`, `state`, GIN on `tags`, GIN on `fields`.

Deleting a node: **not in MVP**. Use the terminal `CANCELLED` state. (Avoids orphan and event-log integrity questions.)

### 3.2 Edge (`edges` table)

`id`, `from_id`, `to_id`, `kind` (enum: `blocks`, `relates`), `inserted_at`. Unique on `(from_id, to_id, kind)`. `from_id != to_id`.

Semantics: `A blocks B` means B is *blocked* until A is in a terminal state. `blocks` edges must form a DAG: creating an edge that would introduce a cycle returns `422 cycle`. Check with a recursive CTE inside the creating transaction. `relates` is symmetric-in-meaning, stored directionally, with no constraints beyond uniqueness.

### 3.3 Event (`events` table, append-only)

| Column | Type |
|---|---|
| `seq` | bigserial PK (global monotonic order) |
| `node_id` | ULID (no FK, so history survives any future deletion) |
| `actor` | string (`human:june`, `agent:planner`) |
| `op` | string: `create`, `update`, `transition`, `move`, `claim`, `release`, `claim_expired`, `edge_add`, `edge_remove` |
| `payload` | jsonb: `{before: {...}, after: {...}}` containing only changed attributes; for edge ops `{edge: {...}}` |
| `at` | utc_datetime_usec |

Invariant: every mutation writes the node change and its event(s) in **one DB transaction**. Nothing updates or deletes event rows (enforce with a Postgres trigger that rejects UPDATE/DELETE).

### 3.4 Workflow and field schema

A single config file for MVP, `backend/priv/workflow.exs` (or `config/workflow.json`), loaded and validated at boot. **Boot fails** if it is malformed.

```elixir
%{
  initial: "TODO",
  states: %{
    "TODO"      => %{terminal: false, next: ["NEXT", "DOING", "CANCELLED"]},
    "NEXT"      => %{terminal: false, next: ["TODO", "DOING", "CANCELLED"]},
    "DOING"     => %{terminal: false, next: ["TODO", "NEXT", "DONE", "CANCELLED"]},
    "DONE"      => %{terminal: true,  next: ["TODO"], require_fields: ["outcome"]},
    "CANCELLED" => %{terminal: true,  next: ["TODO"]}
  },
  actionable: ["NEXT", "TODO"],   # states considered "available to work on"
  fields: %{
    "outcome"   => %{type: "string"},
    "scheduled" => %{type: "date"},
    "deadline"  => %{type: "date"},
    "effort"    => %{type: "int"},          # minutes
    "priority"  => %{type: "enum", values: ["A", "B", "C"]},
    "assignee"  => %{type: "string"}
  }
}
```

Rules:

- `require_fields` for a state must be present (in the node's fields or in the transition request) at transition time, else `422`.
- Unknown field names are rejected (`422`), not stored.
- Setting a field to `null` in PATCH removes it. Removing a field required by the node's current state is `422`.
- Per-subtree workflow overrides are a non-goal for MVP. Keep the lookup behind one function (`Workflow.for_node/1`) so it can be added later.

### 3.5 Ordering

`position` is a base-62 fractional index string. Inserting between siblings A and B generates a key strictly between `A.position` and `B.position`; appending uses a key after the last; prepending, a key before the first. Reordering one node never rewrites siblings. Implement a small pure module `Tasktree.Position` with `between(a | nil, b | nil) :: String.t()` and property-test it (result sorts strictly between inputs; never equal). If two concurrent moves yield identical keys, break ties by `id`.

### 3.6 Claims

- `claim` with `ttl_seconds` (default 900, max 86400) succeeds if the node is unclaimed, the existing claim is expired, or the claimant is the current holder (renewal). Otherwise `409 claimed` with the holder in `details`.
- Use `SELECT ... FOR UPDATE` on the node row.
- An expired claim is treated as absent everywhere. The `claim_expired` event is written lazily the next time the node is touched by a mutation (or by an explicit claim attempt), not by a background job.
- Mutations (`PATCH`, `transition`, `move`) on a node claimed by a *different* live actor return `409 claimed`. Humans in the UI are subject to the same rule, and the UI offers "steal claim" as an explicit `release` with `force: true` for `human:*` actors only.

### 3.7 Derived predicates

- **blocked**: has an incoming `blocks` edge from a node whose state is not terminal.
- **claimable**: state in `actionable`, not blocked, no live claim.

These are implemented as SQL (not computed in Elixir per row) so list endpoints stay one query.

## 4. Auth and actors

Static bearer tokens mapped to actors in runtime config (`TASKTREE_TOKENS="tok1=human:june,tok2=agent:planner"`). A plug resolves `Authorization: Bearer <tok>` to `conn.assigns.actor`, or returns `401`. The browser UI gets a token from a login screen (paste token, stored in `localStorage`). Real user management is a non-goal.

The actor always comes from the token. Clients cannot supply one.

## 5. HTTP API

JSON everywhere, prefixed `/api`. All endpoints require auth.

```
POST   /api/nodes                    {parent_id?, title, body?, fields?, tags?, after_id?}   -> 201 node
GET    /api/nodes/:id                -> node + {children: [ids], edges: {out:[], in:[]}, blocked, claimable}
PATCH  /api/nodes/:id                {title?, body?, fields?, tags?}  header If-Match: <version>  -> node
POST   /api/nodes/:id/transition     {to, fields?}  header If-Match  -> node
POST   /api/nodes/:id/move           {parent_id|null, after_id?|before_id?}  header If-Match  -> node
POST   /api/nodes/:id/claim          {ttl_seconds?}  -> node
POST   /api/nodes/:id/release        {force?: bool}  -> node
POST   /api/edges                    {from_id, to_id, kind}  -> 201 edge
DELETE /api/edges/:id                -> 204
GET    /api/nodes                    query, see below -> {data: [...], next_cursor}
GET    /api/tree                     ?root=:id&depth=N -> nested outline for UI (default: all roots, depth 3)
GET    /api/nodes/:id/events         -> {data: [events]} newest last
GET    /api/events?since=<seq>&limit= -> {data: [events], last_seq}
```

`GET /api/nodes` filters (all optional, AND-combined): `state` (repeatable), `tag` (repeatable), `field.<name>=<value>`, `under=<id>` (descendants, recursive CTE), `claimable=true`, `blocked=true|false`, `claimed_by=<actor>`, `limit`, `cursor`.

Conventions:

- `If-Match` carries the integer `version`. Mismatch -> `409 version_conflict` with the current node in `details`. A missing `If-Match` on a mutation is `428`, not a silent last-write-wins.
- Error body is always `{"error": {"code": "...", "message": "...", "details": {...}}}`. Codes: `unauthorized`, `not_found`, `validation_failed` (422, `details` lists field errors), `invalid_transition` (422), `cycle` (422), `version_conflict` (409), `claimed` (409), `precondition_required` (428).
- Moving a node under its own descendant is `422 cycle`.
- Timestamps are ISO8601 UTC. Dates are `YYYY-MM-DD`.

## 6. Backend structure (Phoenix contexts)

```
Tasktree.Nodes        # create/update/transition/move/claim/release; the only writer of nodes+events
Tasktree.Edges        # add/remove, cycle check
Tasktree.Events       # append (internal), list
Tasktree.Workflow     # load/validate config, transition rules, field validation
Tasktree.Position     # fractional indexing (pure)
Tasktree.Queries      # list/filter/tree/claimable/blocked SQL
TasktreeWeb.*         # controllers, FallbackController (error mapping), AuthPlug, JSON views
```

All writes go through `Ecto.Multi` (or `Repo.transaction`) that includes the event insert. Controllers contain no business logic. The `FallbackController` maps `{:error, reason}` tuples to the error shape in section 5. Never rescue exceptions to return a fake success.

## 7. Frontend (React + TS)

Pages:

1. **Outline** (`/`): collapsible tree from `/api/tree`; each row shows state badge, title, tags, claim indicator (who/expiry), blocked icon. Inline actions: change state (menu limited to allowed transitions, which the API returns on each node as `allowed_transitions`), add child, add sibling. Drag-and-drop reorder is **not** MVP, and "move" is via a dialog or a keyboard shortcut.
2. **Node page** (`/n/:id`): editable title, markdown body (textarea plus rendered preview), fields form generated from the field schema (served at `GET /api/schema`), tags, edges list with add/remove, claim/release buttons, and the event timeline (actor, op, diff summary).
3. **Agenda** (`/agenda`): three saved queries rendered as lists: *Claimable*, *In progress* (`DOING`), *Blocked*.
4. **Login** (`/login`): token entry.

Data layer: a typed API client (hand-written, one file), TanStack Query for caching, polling every 5s on Outline/Agenda (realtime push is a non-goal; Phoenix Channels is the natural follow-up). On `version_conflict`, refetch and show a "node changed, review and retry" notice. Never auto-overwrite.

Add `GET /api/me` to the API list: returns `{actor}` for the bearer token (the login screen uses it to validate a pasted token; the UI uses it to decide whether to offer "steal claim", which is for `human:*` actors only).

Add `GET /api/schema` to the API list: returns `{states, transitions, fields, actionable}` so the UI is driven by the workflow config rather than hardcoding it.

## 8. Build order

Each step should leave tests green.

1. Scaffold the Phoenix app (no html/live/mailer) and the Vite app. Postgres via docker-compose. CI-less; `mix test` and `npm test` must work.
2. Migrations (`nodes`, `edges`, `events` including the append-only trigger and the claim check constraint) and Ecto schemas.
3. `Workflow` (load, validate, boot failure on bad config) and `Position` (with property tests).
4. `Nodes` operations plus `Events`, with unit tests for every op's happy path and every error code. Include concurrency tests for claim (two processes racing) and optimistic versioning.
5. `Edges` with cycle detection tests (including move-under-descendant).
6. `Queries` (filters, `under`, `claimable`, `blocked`, tree) with tests.
7. Phoenix controllers, auth plug, FallbackController, `/api/schema`. Controller tests cover the error contract.
8. Frontend: API client, Login, Outline, Node page, Agenda.
9. `docs/AGENTS.md`: curl examples for the agent loop (find claimable, claim, work, transition with `outcome`, release).

## 9. Non-goals (MVP)

Org-mode text import/export or round-tripping, node deletion, multi-user accounts and permissions, per-subtree workflows, recurring tasks, time clocking, full-text search, drag-and-drop reordering, realtime push, background jobs, and heartbeat-based claims.

## 10. Acceptance criteria

- An agent using only curl and a token can: list claimable nodes, claim one, transition it to `DONE` with an `outcome`, and see the full history via `/events`.
- Two concurrent claim requests on one node: exactly one succeeds, the other gets `409 claimed`.
- A stale `If-Match` is rejected with `409 version_conflict`; a missing one with `428`.
- Creating a `blocks` cycle, or moving a node under its own descendant, is rejected with `422 cycle`.
- Transition to `DONE` without `outcome` is rejected with `422`.
- Every successful mutation has a matching event with the correct actor, and attempts to UPDATE/DELETE an event row fail at the DB level.
- A bad workflow config prevents boot.
- The web UI can do the above flow for a human, driven by `/api/schema` rather than hardcoded states.

## 11. Decisions worth knowing the reasons for

- **Postgres over SQLite**: row locks give simple claim/version semantics, and jsonb and GIN indexes cover field and tag queries. SQLite would work with a single writer if setup friction matters more.
- **Fractional `position`**: a single-row write per move keeps events small and avoids sibling rewrites.
- **Events carry before/after, not full snapshots**: the node row is the current state, so history only needs diffs.
- **Lazy claim expiry**: no scheduler needed. Expiry is just a timestamp comparison, and the event is recorded when next observable.
- **Strict single-parent tree plus edges**: multi-parent trees make move and delete semantics ambiguous.
