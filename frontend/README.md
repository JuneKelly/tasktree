# Tasktree frontend

React + TypeScript SPA (Vite, TanStack Query, React Router, TipTap). See the repository
`README.md` for how to run it (Docker only) and `AGENTS.md` for working conventions.

- `src/api/`: typed API client and query hooks
- `src/pages/`: Login, Outline, Node page, Agenda
- `src/outline/`: inline editing (autosave, keyboard structure editing)
- `src/editor/`: rich/raw body editors and the markdown round-trip guard
- `src/test/`: fetch mock, fixtures, render helper
