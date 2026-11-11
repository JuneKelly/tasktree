# TODO

Future work, roughly in priority order. `HANDOFF.md` has context on decisions already made.

## Next up

- [ ] **Production serving.** Vite `build.outDir` -> `backend/priv/static`, Phoenix serves the SPA and falls back to `index.html` for non-`/api` routes (DESIGN.md §2). The frontend container only mounts `frontend/`, so this needs a mount or a copy step. Add a prod Dockerfile / release config (`DATABASE_URL` etc.).
- [ ] **Walk the UI in a real browser.** The §10 flow and the inline editor (typing, paste, IME, Tab/Enter in tables, focus after moves) have only been tested in jsdom. Consider Playwright for a few end-to-end checks.
- [ ] **CI.** Run `mix test`, `npm test`, typecheck, lint and build on every push (the design said CI-less for MVP; the suite is now big enough to justify it).
- [ ] **Lazy-load the editor.** Bundle is ~990 kB (310 kB gzip) because of TipTap; code-split it so the outline loads without it.

## Editor and outline

- [ ] "Insert table" (and other block types) via a `/` menu or a small toolbar. Today new tables can only be created as markdown on the Node page.
- [ ] Use the rich editor on the Node page (it still edits notes as raw markdown).
- [ ] Outline: expander for nodes at the tree depth cutoff (needs a child count in the API), remember collapse state across reloads, show claim/release on the row.
- [ ] Outline: Alt+↑/↓ to reorder siblings, multi-select move.
- [ ] Task-list support in the rich editor (`- [ ]` currently forces raw-markdown editing).
- [ ] Better conflict view: show a diff of the winning version next to the draft.
- [ ] Accessibility pass (focus order, announce autosave and conflicts, contrast in dark mode).

## Backend / API

- [ ] Explicit state order in the workflow config so `/api/schema` and the UI can show a canonical order (currently sorted by name).
- [ ] Decide whether edge changes should write one global event instead of one per endpoint (the `/api/events` feed shows them twice).
- [ ] Position ties from concurrent writers can sort slightly off from the requested spot; consider a rebalance or a tie-aware `between`.
- [ ] Token management beyond static `TASKTREE_TOKENS` (rotation, per-token scopes) if more than a couple of actors are needed.
- [ ] Node deletion/archival is a non-goal for the MVP; revisit if the CANCELLED state clutters the outline (e.g. a "hide terminal nodes" view filter).
- [ ] Test DB accumulates a few `events` rows per run from the real-concurrency tests (append-only trigger blocks cleanup); drop/recreate the test DB periodically or give those tests their own schema.

## Docs

- [ ] Keep `docs/AGENTS.md` curl examples verified against a running backend when the API changes.
- [ ] Add screenshots to the README once the UI settles.
