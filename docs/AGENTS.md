# Agent guide: working Tasktree with curl

You need a bearer token (the operator maps it to your actor, e.g. `agent:planner`). Your actor
comes from the token; it can't be set in a request body.

```sh
export TT=http://localhost:4000/api
export H="Authorization: Bearer $TASKTREE_TOKEN"
J='Content-Type: application/json'
```

Every error is `{"error": {"code", "message", "details"}}`. Branch on `code`, not on `message`.

## The loop

### 1. Find claimable work

Claimable = in an actionable state, not blocked, no live claim.

```sh
curl -s -H "$H" "$TT/nodes?claimable=true&limit=10"
```

Other filters (all optional, AND-combined): `state=` and `tag=` (repeatable), `field.<name>=`,
`under=<id>` (descendants), `blocked=true|false`, `claimed_by=<actor>`, `cursor=` (from `next_cursor`).
Each node carries `version`, `allowed_transitions`, `blocked` and `claimable`.

### 2. Claim it

```sh
curl -s -XPOST -H "$H" -H "$J" -d '{"ttl_seconds": 600}' "$TT/nodes/$ID/claim"
```

- TTL defaults to 900s, max 86400. Re-claiming a node you hold renews it.
- `409 claimed` means someone else holds it; `details` has `claimed_by` and `claim_expires_at`. Pick another node.
- Expired claims count as absent; there is no heartbeat, so renew before the TTL runs out.
- Claiming bumps the node's `version`. Use the `version` from the claim response in the next step.

### 3. Work, then change state

Mutations need `If-Match: <version>`:

```sh
curl -s -XPOST -H "$H" -H "$J" -H "If-Match: $VERSION" -d '{"to": "DOING"}' "$TT/nodes/$ID/transition"
```

Other mutations use the same header: `PATCH /nodes/:id` (`title`, `body`, `fields`, `tags`; a `null` field
value removes it), and `POST /nodes/:id/move` (`{"parent_id": ..., "after_id"|"before_id": ...}`).
Each response is the updated node, with its new `version`.

- Missing `If-Match` -> `428 precondition_required`.
- Stale version -> `409 version_conflict`, with the current node in `details.current`. Re-read, decide, and retry
  with the new version. Don't blindly resend.
- A claim held by someone else blocks mutations -> `409 claimed`.

### 4. Finish with an outcome

`DONE` requires the `outcome` field (here or already set on the node):

```sh
curl -s -XPOST -H "$H" -H "$J" -H "If-Match: $VERSION" \
  -d '{"to": "DONE", "fields": {"outcome": "merged in #42"}}' "$TT/nodes/$ID/transition"
```

- Without it: `422 validation_failed`, `details.fields` names what is missing.
- A transition not in `allowed_transitions`: `422 invalid_transition`.
- Valid states, transitions, and fields are served by `GET /api/schema`; don't hardcode them.

### 5. Release

```sh
curl -s -XPOST -H "$H" -H "$J" -d '{}' "$TT/nodes/$ID/release"
```

Only the holder can release (`force` is for humans). Releasing a node with no live claim is a `422`.

### 6. Read the history

```sh
curl -s -H "$H" "$TT/nodes/$ID/events"          # one node, oldest first
curl -s -H "$H" "$TT/events?since=$LAST_SEQ"     # global feed; use last_seq as the next since
```

Each event has `actor`, `op`, and a `payload` with the changed attributes as `before` / `after`.

## Creating structure

```sh
curl -s -XPOST -H "$H" -H "$J" -d '{"title": "Subtask", "parent_id": "'$PARENT'", "tags": ["x"]}' "$TT/nodes"
curl -s -XPOST -H "$H" -H "$J" -d '{"from_id": "'$A'", "to_id": "'$B'", "kind": "blocks"}' "$TT/edges"   # A blocks B
curl -s -XDELETE -H "$H" "$TT/edges/$EDGE_ID"
curl -s -H "$H" "$TT/tree?root=$ID&depth=3"
```

A `blocks` edge that would create a cycle, or moving a node under its own descendant, is `422 cycle`.

## Error codes

| HTTP | `code` | Meaning |
|---|---|---|
| 401 | `unauthorized` | Missing or unknown token |
| 404 | `not_found` | No such node or edge |
| 409 | `claimed` | Held by another actor (`details`: holder, expiry) |
| 409 | `version_conflict` | Stale `If-Match` (`details.current`: current node) |
| 422 | `validation_failed` | Bad input, unknown field, missing required field (`details`: per-field messages) |
| 422 | `invalid_transition` | Not allowed from the current state |
| 422 | `cycle` | Would create a `blocks` or parent cycle |
| 428 | `precondition_required` | Missing `If-Match` |
