defmodule Tasktree.Nodes do
  @moduledoc """
  The only writer of nodes and (with `Tasktree.Edges`) events.

  Every mutation runs in one transaction that locks the node row (`FOR UPDATE`),
  applies the change, bumps `version`, and appends its event(s).

  Inputs are string-keyed maps as decoded from JSON. Errors are `{:error, reason}`:

    * `:not_found`
    * `{:validation_failed, %{key => message}}`
    * `{:invalid_transition, %{"from" => _, "to" => _}}`
    * `:cycle`
    * `{:version_conflict, %Node{}}` (the current node)
    * `{:claimed, %{"claimed_by" => _, "claim_expires_at" => _}}`

  A mutation that changes nothing returns the node untouched: no event, no version bump.
  A missing `If-Match` (HTTP 428) is a controller concern; `version` here is always an integer.
  """

  import Ecto.Query

  alias Tasktree.{Events, Position, Repo, Workflow}
  alias Tasktree.Nodes.Node

  @default_ttl 900
  @max_ttl 86_400
  @tree_lock 4201

  @type error :: :not_found | :cycle | {atom(), term()}

  @spec get(String.t()) :: {:ok, %Node{}} | {:error, :not_found}
  def get(id) when is_binary(id) do
    case Repo.get(Node, id) do
      nil -> {:error, :not_found}
      node -> {:ok, node}
    end
  end

  ## Create

  @create_keys ~w(parent_id title body fields tags after_id)

  @spec create(String.t(), map()) :: {:ok, %Node{}} | {:error, error()}
  def create(actor, attrs) when is_binary(actor) and is_map(attrs) do
    wf = Workflow.for_node(nil)

    tx(fn ->
      with :ok <- allowed_keys(attrs, @create_keys),
           {:ok, title} <- required_title(attrs),
           {:ok, body} <- optional(attrs, "body", "", &string_ok/2),
           {:ok, tags} <- optional(attrs, "tags", [], &tags_ok/2),
           {:ok, fields} <- optional(attrs, "fields", %{}, &new_fields_ok(&1, &2, wf)),
           {:ok, parent_id} <- existing_parent(attrs["parent_id"]),
           anchor = if(attrs["after_id"], do: {:after, attrs["after_id"]}, else: :append),
           {:ok, position} <- position_for(parent_id, anchor, nil) do
        node =
          Repo.insert!(%Node{
            parent_id: parent_id,
            position: position,
            title: title,
            body: body,
            state: wf.initial,
            fields: fields,
            tags: tags
          })

        after_attrs =
          Map.new(
            ~w(parent_id position title body state fields tags)a,
            &{Atom.to_string(&1), Map.fetch!(node, &1)}
          )

        Events.append!(actor, node.id, :create, %{"before" => %{}, "after" => after_attrs})
        {:ok, node}
      end
    end)
  end

  ## Update

  @update_keys ~w(title body fields tags)

  @spec update(String.t(), String.t(), integer(), map()) :: {:ok, %Node{}} | {:error, error()}
  def update(actor, id, version, attrs)
      when is_binary(actor) and is_binary(id) and is_integer(version) and is_map(attrs) do
    mutate(actor, id, :update,
      version: version,
      claim_gate: true,
      fun: fn node, _now ->
        wf = Workflow.for_node(node)

        with :ok <- allowed_keys(attrs, @update_keys),
             :ok <- non_empty(attrs),
             {:ok, title} <- optional(attrs, "title", node.title, fn _k, v -> title_ok(v) end),
             {:ok, body} <- optional(attrs, "body", node.body, &string_ok/2),
             {:ok, tags} <- optional(attrs, "tags", node.tags, &tags_ok/2),
             {:ok, fields} <- patch_fields(attrs, node, wf) do
          {:ok, %{title: title, body: body, tags: tags, fields: fields}}
        end
      end
    )
  end

  defp patch_fields(attrs, node, wf) do
    case Map.fetch(attrs, "fields") do
      :error ->
        {:ok, node.fields}

      {:ok, patch} when is_map(patch) ->
        {removed, set} = Enum.split_with(patch, fn {_k, v} -> is_nil(v) end)

        with :ok <- fields_result(Workflow.validate_fields(wf, Map.new(set))) do
          merged =
            node.fields |> Map.drop(Enum.map(removed, &elem(&1, 0))) |> Map.merge(Map.new(set))

          required = wf.states |> Map.get(node.state, %{}) |> Map.get(:require_fields, [])

          case Enum.reject(required, &Map.has_key?(merged, &1)) do
            [] ->
              {:ok, merged}

            missing ->
              invalid("fields", "required by state #{node.state}: #{Enum.join(missing, ", ")}")
          end
        end

      {:ok, _} ->
        invalid("fields", "must be an object")
    end
  end

  ## Transition

  @spec transition(String.t(), String.t(), integer(), map()) :: {:ok, %Node{}} | {:error, error()}
  def transition(actor, id, version, attrs)
      when is_binary(actor) and is_binary(id) and is_integer(version) and is_map(attrs) do
    mutate(actor, id, :transition,
      version: version,
      claim_gate: true,
      fun: fn node, _now ->
        wf = Workflow.for_node(node)

        with :ok <- allowed_keys(attrs, ~w(to fields)),
             {:ok, to} <- required_string(attrs, "to"),
             {:ok, req_fields} <- optional(attrs, "fields", %{}, &new_fields_ok(&1, &2, wf)),
             merged = Map.merge(node.fields, req_fields),
             :ok <- check_transition(wf, node.state, to, merged) do
          {:ok, %{state: to, fields: merged}}
        end
      end
    )
  end

  defp check_transition(wf, from, to, fields) do
    case Workflow.check_transition(wf, from, to, fields) do
      :ok ->
        :ok

      {:error, {:unknown_state, ^to}} ->
        invalid("to", "unknown state #{inspect(to)}")

      {:error, {:unknown_state, s}} ->
        invalid("state", "node is in unknown state #{inspect(s)}")

      {:error, {:illegal_transition, f, t}} ->
        {:error, {:invalid_transition, %{"from" => f, "to" => t}}}

      {:error, {:missing_fields, m}} ->
        invalid("fields", "required: #{Enum.join(m, ", ")}")
    end
  end

  ## Move

  @spec move(String.t(), String.t(), integer(), map()) :: {:ok, %Node{}} | {:error, error()}
  def move(actor, id, version, attrs)
      when is_binary(actor) and is_binary(id) and is_integer(version) and is_map(attrs) do
    mutate(actor, id, :move,
      version: version,
      claim_gate: true,
      lock_tree: true,
      fun: fn node, _now ->
        with :ok <- allowed_keys(attrs, ~w(parent_id after_id before_id)),
             :ok <-
               if(Map.has_key?(attrs, "parent_id"),
                 do: :ok,
                 else: invalid("parent_id", "is required (null for root)")
               ),
             {:ok, anchor} <- move_anchor(attrs),
             {:ok, parent_id} <- existing_parent(attrs["parent_id"]),
             :ok <- check_no_cycle(node.id, parent_id),
             {:ok, position} <- position_for(parent_id, anchor, node.id) do
          {:ok, %{parent_id: parent_id, position: position}}
        end
      end
    )
  end

  defp move_anchor(%{"after_id" => a, "before_id" => b}) when not is_nil(a) and not is_nil(b),
    do: invalid("after_id", "cannot be combined with before_id")

  defp move_anchor(%{"after_id" => a}) when not is_nil(a), do: {:ok, {:after, a}}
  defp move_anchor(%{"before_id" => b}) when not is_nil(b), do: {:ok, {:before, b}}
  defp move_anchor(_), do: {:ok, :append}

  # The node may not become its own parent or a child of one of its descendants,
  # i.e. it must not be an ancestor-or-self of the new parent.
  defp check_no_cycle(_id, nil), do: :ok

  defp check_no_cycle(id, new_parent_id) do
    %{rows: rows} =
      Repo.query!(
        """
        WITH RECURSIVE up AS (
          SELECT id, parent_id FROM nodes WHERE id = $1
          UNION ALL
          SELECT n.id, n.parent_id FROM nodes n JOIN up ON n.id = up.parent_id
        )
        SELECT 1 FROM up WHERE id = $2 LIMIT 1
        """,
        [new_parent_id, id]
      )

    if rows == [], do: :ok, else: {:error, :cycle}
  end

  ## Claim / release

  @spec claim(String.t(), String.t(), map()) :: {:ok, %Node{}} | {:error, error()}
  def claim(actor, id, attrs) when is_binary(actor) and is_binary(id) and is_map(attrs) do
    mutate(actor, id, :claim,
      fun: fn node, now ->
        with :ok <- allowed_keys(attrs, ["ttl_seconds"]),
             {:ok, ttl} <- ttl(attrs),
             :ok <- not_held_by_other(node, actor) do
          {:ok, %{claimed_by: actor, claim_expires_at: DateTime.add(now, ttl, :second)}}
        end
      end
    )
  end

  defp ttl(attrs) do
    case Map.get(attrs, "ttl_seconds", @default_ttl) do
      t when is_integer(t) and t >= 1 and t <= @max_ttl -> {:ok, t}
      _ -> invalid("ttl_seconds", "must be an integer between 1 and #{@max_ttl}")
    end
  end

  @spec release(String.t(), String.t(), map()) :: {:ok, %Node{}} | {:error, error()}
  def release(actor, id, attrs) when is_binary(actor) and is_binary(id) and is_map(attrs) do
    mutate(actor, id, :release,
      fun: fn node, _now ->
        with :ok <- allowed_keys(attrs, ["force"]),
             {:ok, force} <- boolean(attrs, "force"),
             :ok <- if(node.claimed_by, do: :ok, else: invalid("claim", "node is not claimed")),
             :ok <- release_allowed(node, actor, force) do
          {:ok, %{claimed_by: nil, claim_expires_at: nil}}
        end
      end
    )
  end

  defp release_allowed(%{claimed_by: actor}, actor, _force), do: :ok

  defp release_allowed(_node, actor, true) do
    if String.starts_with?(actor, "human:"),
      do: :ok,
      else: invalid("force", "only human actors may force a release")
  end

  defp release_allowed(node, _actor, false), do: not_held_by_other(node, nil)

  defp boolean(attrs, key) do
    case Map.get(attrs, key, false) do
      v when is_boolean(v) -> {:ok, v}
      _ -> invalid(key, "must be a boolean")
    end
  end

  # `node` here is the post-expiry view, so a non-nil holder is a live claim.
  defp not_held_by_other(%{claimed_by: nil}, _actor), do: :ok
  defp not_held_by_other(%{claimed_by: actor}, actor), do: :ok
  defp not_held_by_other(node, _actor), do: {:error, claimed_error(node)}

  defp claimed_error(node),
    do:
      {:claimed, %{"claimed_by" => node.claimed_by, "claim_expires_at" => node.claim_expires_at}}

  ## Mutation core

  # Locks the node, treats an expired claim as absent (recording `claim_expired`
  # lazily if the mutation proceeds), checks the claim gate and version, runs
  # `fun.(node_view, now)` for `{:ok, changes}`, then writes node + event(s).
  defp mutate(actor, id, op, opts) do
    fun = Keyword.fetch!(opts, :fun)

    tx(fn ->
      if opts[:lock_tree], do: Repo.query!("SELECT pg_advisory_xact_lock($1)", [@tree_lock])

      with {:ok, node} <- lock(id),
           now = DateTime.utc_now(),
           {view, expired?} = expire_view(node, now),
           :ok <- if(opts[:claim_gate], do: not_held_by_other(view, actor), else: :ok),
           :ok <- check_version(node, opts[:version]),
           {:ok, changes} <- fun.(view, now) do
        diff = diff(view, changes)

        if diff.after == %{} do
          {:ok, node}
        else
          if expired? do
            Events.append!(actor, id, :claim_expired, %{
              "before" => %{
                "claimed_by" => node.claimed_by,
                "claim_expires_at" => node.claim_expires_at
              },
              "after" => %{"claimed_by" => nil, "claim_expires_at" => nil}
            })
          end

          changed =
            Map.filter(changes, fn {k, _} -> Map.has_key?(diff.after, Atom.to_string(k)) end)

          cleared = if expired?, do: %{claimed_by: nil, claim_expires_at: nil}, else: %{}
          db_changes = cleared |> Map.merge(changed) |> Map.put(:version, node.version + 1)

          updated = node |> Ecto.Changeset.change(db_changes) |> Repo.update!()
          Events.append!(actor, id, op, %{"before" => diff.before, "after" => diff.after})
          {:ok, updated}
        end
      end
    end)
  end

  defp lock(id) do
    case Repo.one(from n in Node, where: n.id == ^id, lock: "FOR UPDATE") do
      nil -> {:error, :not_found}
      node -> {:ok, node}
    end
  end

  defp expire_view(%{claimed_by: nil} = node, _now), do: {node, false}

  defp expire_view(node, now) do
    if DateTime.compare(node.claim_expires_at, now) == :gt,
      do: {node, false},
      else: {%{node | claimed_by: nil, claim_expires_at: nil}, true}
  end

  defp check_version(_node, nil), do: :ok
  defp check_version(%{version: v}, v), do: :ok
  defp check_version(node, _), do: {:error, {:version_conflict, node}}

  defp diff(view, changes) do
    changed = Enum.reject(changes, fn {k, v} -> Map.fetch!(view, k) == v end)

    %{
      before: Map.new(changed, fn {k, _} -> {Atom.to_string(k), Map.fetch!(view, k)} end),
      after: Map.new(changed, fn {k, v} -> {Atom.to_string(k), v} end)
    }
  end

  defp tx(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  ## Positioning

  defp existing_parent(nil), do: {:ok, nil}

  defp existing_parent(id) when is_binary(id) do
    if Repo.exists?(from n in Node, where: n.id == ^id),
      do: {:ok, id},
      else: invalid("parent_id", "no such node")
  end

  defp existing_parent(_), do: invalid("parent_id", "must be a string or null")

  defp position_for(parent_id, :append, exclude_id) do
    last = Repo.one(from n in siblings(parent_id, exclude_id), select: max(n.position))
    {:ok, Position.between(last, nil)}
  end

  defp position_for(parent_id, {side, anchor_id}, exclude_id) do
    with {:ok, anchor} <- sibling_anchor(parent_id, anchor_id, exclude_id) do
      # Ties on `position` (concurrent writers) are ordered by id; we step to the
      # nearest strictly different key so `between/2` always has room.
      case side do
        :after ->
          upper =
            Repo.one(
              from n in siblings(parent_id, exclude_id),
                where: n.position > ^anchor.position,
                select: min(n.position)
            )

          {:ok, Position.between(anchor.position, upper)}

        :before ->
          lower =
            Repo.one(
              from n in siblings(parent_id, exclude_id),
                where: n.position < ^anchor.position,
                select: max(n.position)
            )

          {:ok, Position.between(lower, anchor.position)}
      end
    end
  end

  defp sibling_anchor(parent_id, anchor_id, exclude_id) when is_binary(anchor_id) do
    case Repo.one(from n in siblings(parent_id, exclude_id), where: n.id == ^anchor_id) do
      nil -> invalid("after_id/before_id", "must be another child of the target parent")
      anchor -> {:ok, anchor}
    end
  end

  defp sibling_anchor(_, _, _), do: invalid("after_id/before_id", "must be a string")

  defp siblings(parent_id, exclude_id) do
    q =
      if parent_id,
        do: from(n in Node, where: n.parent_id == ^parent_id),
        else: from(n in Node, where: is_nil(n.parent_id))

    if exclude_id, do: where(q, [n], n.id != ^exclude_id), else: q
  end

  ## Validation helpers

  defp invalid(key, message), do: {:error, {:validation_failed, %{key => message}}}

  defp allowed_keys(attrs, allowed) do
    case Map.keys(attrs) -- allowed do
      [] ->
        :ok

      unknown ->
        {:error, {:validation_failed, Map.new(unknown, &{to_string(&1), "unknown field"})}}
    end
  end

  defp non_empty(attrs),
    do: if(attrs == %{}, do: invalid("attrs", "no attributes given"), else: :ok)

  defp required_title(attrs) do
    case Map.fetch(attrs, "title") do
      {:ok, v} -> title_ok(v)
      :error -> invalid("title", "is required")
    end
  end

  defp title_ok(v) when is_binary(v) and v != "", do: {:ok, v}
  defp title_ok(_), do: invalid("title", "must be a non-empty string")

  defp required_string(attrs, key) do
    case Map.get(attrs, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> invalid(key, "is required and must be a non-empty string")
    end
  end

  defp optional(attrs, key, default, validator) do
    case Map.fetch(attrs, key) do
      :error -> {:ok, default}
      {:ok, v} -> validator.(key, v)
    end
  end

  defp string_ok(_key, v) when is_binary(v), do: {:ok, v}
  defp string_ok(key, _), do: invalid(key, "must be a string")

  defp tags_ok(_key, v) when is_list(v) do
    if Enum.all?(v, &is_binary/1),
      do: {:ok, Enum.uniq(v)},
      else: invalid("tags", "must be a list of strings")
  end

  defp tags_ok(key, _), do: invalid(key, "must be a list of strings")

  defp new_fields_ok(_key, v, wf) when is_map(v) do
    with :ok <- fields_result(Workflow.validate_fields(wf, v)), do: {:ok, v}
  end

  defp new_fields_ok(key, _, _), do: invalid(key, "must be an object")

  defp fields_result(:ok), do: :ok
  defp fields_result({:error, {:unknown_field, n}}), do: invalid("fields.#{n}", "unknown field")
  defp fields_result({:error, {:invalid_field, n}}), do: invalid("fields.#{n}", "invalid value")
end
