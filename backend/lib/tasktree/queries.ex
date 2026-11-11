defmodule Tasktree.Queries do
  @moduledoc """
  Read side: list/filter, single-node detail, and tree. Derived predicates
  (`blocked`, `claimable`; DESIGN.md 3.7) are computed in SQL and returned on the
  virtual `Node` fields of the same names.

  `list/1` takes the raw (string-keyed) query params, so controllers hold no parsing
  logic. Invalid input is `{:error, {:validation_failed, %{param => message}}}`.
  """

  import Ecto.Query

  alias Tasktree.{Repo, Workflow}
  alias Tasktree.Edges.Edge
  alias Tasktree.Nodes.Node

  @default_limit 50
  @max_limit 200
  @default_depth 3
  @list_keys ~w(state tag under claimable blocked claimed_by limit cursor)

  ## Derived predicates

  defp base(wf, now) do
    terminal = for {name, %{terminal: true}} <- wf.states, do: name
    blocked = blocked_dyn(terminal)
    claimable = claimable_dyn(wf.actionable, blocked, now)

    query =
      from(n in Node, as: :node)
      |> select_merge(^%{blocked: blocked, claimable: claimable})

    {query, blocked, claimable}
  end

  defp blocked_dyn(terminal) do
    dynamic(
      [node: n],
      exists(
        from(e in Edge,
          join: b in Node,
          on: b.id == e.from_id,
          where:
            e.to_id == parent_as(:node).id and e.kind == :blocks and b.state not in ^terminal,
          select: 1
        )
      )
    )
  end

  defp claimable_dyn(actionable, blocked, now) do
    dynamic(
      [node: n],
      n.state in ^actionable and not (^blocked) and
        (is_nil(n.claimed_by) or n.claim_expires_at <= ^now)
    )
  end

  ## Detail

  @spec get(String.t()) ::
          {:ok, %{node: %Node{}, children: [String.t()], edges: %{out: [%Edge{}], in: [%Edge{}]}}}
          | {:error, :not_found}
  def get(id) when is_binary(id) do
    {query, _, _} = base(Workflow.for_node(nil), DateTime.utc_now())

    case Repo.one(where(query, [node: n], n.id == ^id)) do
      nil ->
        {:error, :not_found}

      node ->
        children =
          Repo.all(
            from c in Node, where: c.parent_id == ^id, order_by: [c.position, c.id], select: c.id
          )

        out = Repo.all(from e in Edge, where: e.from_id == ^id, order_by: e.id)
        inn = Repo.all(from e in Edge, where: e.to_id == ^id, order_by: e.id)
        {:ok, %{node: node, children: children, edges: %{out: out, in: inn}}}
    end
  end

  ## List

  @spec list(map()) :: {:ok, %{data: [%Node{}], next_cursor: String.t() | nil}} | {:error, term()}
  def list(params) when is_map(params) do
    wf = Workflow.for_node(nil)
    now = DateTime.utc_now()
    {query, blocked, claimable} = base(wf, now)

    with :ok <- known_params(params),
         {:ok, limit} <- limit(params),
         {:ok, filters} <- filters(params, wf, now, blocked, claimable),
         {:ok, query} <- apply_under(query, params["under"]),
         {:ok, cursor} <- cursor(params["cursor"]) do
      query =
        Enum.reduce(filters, query, fn f, q -> where(q, [node: n], ^f) end)

      query = if cursor, do: where(query, [node: n], n.id > ^cursor), else: query
      rows = Repo.all(from [node: n] in query, order_by: n.id, limit: ^(limit + 1))
      {page, rest} = Enum.split(rows, limit)
      {:ok, %{data: page, next_cursor: if(rest == [], do: nil, else: List.last(page).id)}}
    end
  end

  defp known_params(params) do
    case Enum.reject(Map.keys(params), &(&1 in @list_keys or String.starts_with?(&1, "field."))) do
      [] -> :ok
      unknown -> {:error, {:validation_failed, Map.new(unknown, &{&1, "unknown parameter"})}}
    end
  end

  defp limit(params) do
    case Map.get(params, "limit", @default_limit) do
      n when is_integer(n) and n in 1..@max_limit -> {:ok, n}
      s when is_binary(s) -> with_int(s, "limit", 1..@max_limit)
      _ -> invalid("limit", "must be an integer between 1 and #{@max_limit}")
    end
  end

  defp with_int(s, key, range) do
    case Integer.parse(s) do
      {n, ""} ->
        if n in range,
          do: {:ok, n},
          else: invalid(key, "must be between #{range.first} and #{range.last}")

      _ ->
        invalid(key, "must be an integer")
    end
  end

  defp cursor(nil), do: {:ok, nil}
  defp cursor(c) when is_binary(c) and c != "", do: {:ok, c}
  defp cursor(_), do: invalid("cursor", "must be a non-empty string")

  defp filters(params, wf, now, blocked, claimable) do
    steps = [
      fn -> list_param(params, "state", fn vs -> dynamic([node: n], n.state in ^vs) end) end,
      fn ->
        list_param(params, "tag", fn vs ->
          dynamic([node: n], fragment("? @> ?::text[]", n.tags, ^vs))
        end)
      end,
      fn -> bool_param(params, "claimable", claimable) end,
      fn -> bool_param(params, "blocked", blocked) end,
      fn -> claimed_by(params, now) end,
      fn -> field_filters(params, wf) end
    ]

    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      case step.() do
        {:ok, dyns} -> {:cont, {:ok, acc ++ dyns}}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  defp list_param(params, key, build) do
    case Map.fetch(params, key) do
      :error ->
        {:ok, []}

      {:ok, v} when is_binary(v) ->
        {:ok, [build.([v])]}

      {:ok, vs} when is_list(vs) and vs != [] ->
        if Enum.all?(vs, &is_binary/1),
          do: {:ok, [build.(vs)]},
          else: invalid(key, "must be strings")

      {:ok, _} ->
        invalid(key, "must be a string or list of strings")
    end
  end

  defp bool_param(params, key, predicate) do
    case Map.fetch(params, key) do
      :error -> {:ok, []}
      {:ok, v} when v in [true, "true"] -> {:ok, [predicate]}
      {:ok, v} when v in [false, "false"] -> {:ok, [dynamic(not (^predicate))]}
      {:ok, _} -> invalid(key, "must be true or false")
    end
  end

  defp claimed_by(params, now) do
    case Map.fetch(params, "claimed_by") do
      :error ->
        {:ok, []}

      {:ok, a} when is_binary(a) and a != "" ->
        {:ok, [dynamic([node: n], n.claimed_by == ^a and n.claim_expires_at > ^now)]}

      {:ok, _} ->
        invalid("claimed_by", "must be a non-empty string")
    end
  end

  defp field_filters(params, wf) do
    params
    |> Enum.filter(fn {k, _} -> String.starts_with?(k, "field.") end)
    |> Enum.reduce_while({:ok, []}, fn {"field." <> name = key, raw}, {:ok, acc} ->
      with {:ok, def} <- field_def(wf, name, key),
           {:ok, value} <- field_value(def, raw, key) do
        d = dynamic([node: n], fragment("? @> ?", n.fields, type(^%{name => value}, :map)))
        {:cont, {:ok, [d | acc]}}
      else
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  defp field_def(wf, name, key) do
    case wf.fields do
      %{^name => def} -> {:ok, def}
      _ -> invalid(key, "unknown field")
    end
  end

  defp field_value(%{type: "int"}, raw, key) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} -> {:ok, n}
      _ -> invalid(key, "must be an integer")
    end
  end

  defp field_value(%{type: "date"}, raw, key) when is_binary(raw) do
    case Date.from_iso8601(raw) do
      {:ok, _} -> {:ok, raw}
      _ -> invalid(key, "must be YYYY-MM-DD")
    end
  end

  defp field_value(%{type: "enum", values: vs}, raw, key) when is_binary(raw) do
    if raw in vs, do: {:ok, raw}, else: invalid(key, "must be one of #{Enum.join(vs, ", ")}")
  end

  defp field_value(%{type: "string"}, raw, _key) when is_binary(raw), do: {:ok, raw}
  defp field_value(_, _, key), do: invalid(key, "must be a single string value")

  # Descendants of `under` (excluding itself) via recursive CTE.
  defp apply_under(query, nil), do: {:ok, query}

  defp apply_under(query, id) when is_binary(id) do
    if Repo.exists?(from n in Node, where: n.id == ^id) do
      seed = from(n in Node, where: n.parent_id == ^id, select: %{id: n.id})

      step =
        from(n in Node, join: d in "descendants", on: n.parent_id == d.id, select: %{id: n.id})

      query =
        query
        |> recursive_ctes(true)
        |> with_cte("descendants", as: ^union_all(seed, ^step))
        |> join(:inner, [node: n], d in "descendants", on: d.id == n.id)

      {:ok, query}
    else
      invalid("under", "no such node")
    end
  end

  defp apply_under(_, _), do: invalid("under", "must be a node id")

  ## Tree

  @doc """
  Nested outline. `opts`: `"root"` (node id; default all roots) and `"depth"` (levels
  returned including the top level; default #{@default_depth}). Children are ordered by
  `(position, id)`. Returns `[%{node: %Node{}, children: [...]}]`.
  """
  @spec tree(map()) :: {:ok, [map()]} | {:error, :not_found | {:validation_failed, map()}}
  def tree(opts) when is_map(opts) do
    with :ok <- known_tree_params(opts),
         {:ok, depth} <- depth(opts),
         {:ok, seed} <- tree_seed(opts["root"]) do
      {query, _, _} = base(Workflow.for_node(nil), DateTime.utc_now())

      step =
        from(n in Node,
          join: t in "tree",
          on: n.parent_id == t.id,
          where: t.depth < ^depth,
          select: %{id: n.id, depth: t.depth + 1}
        )

      rows =
        query
        |> recursive_ctes(true)
        |> with_cte("tree", as: ^union_all(seed, ^step))
        |> join(:inner, [node: n], t in "tree", on: t.id == n.id)
        |> order_by([node: n], [n.position, n.id])
        |> Repo.all()

      {:ok, nest(rows, opts["root"])}
    end
  end

  defp known_tree_params(opts) do
    case Map.keys(opts) -- ~w(root depth) do
      [] -> :ok
      unknown -> {:error, {:validation_failed, Map.new(unknown, &{&1, "unknown parameter"})}}
    end
  end

  defp depth(opts) do
    case Map.get(opts, "depth", @default_depth) do
      n when is_integer(n) and n >= 1 -> {:ok, n}
      s when is_binary(s) -> with_int(s, "depth", 1..1000)
      _ -> invalid("depth", "must be a positive integer")
    end
  end

  defp tree_seed(nil),
    do: {:ok, from(n in Node, where: is_nil(n.parent_id), select: %{id: n.id, depth: 1})}

  defp tree_seed(id) when is_binary(id) do
    if Repo.exists?(from n in Node, where: n.id == ^id),
      do: {:ok, from(n in Node, where: n.id == ^id, select: %{id: n.id, depth: 1})},
      else: {:error, :not_found}
  end

  defp tree_seed(_), do: invalid("root", "must be a node id")

  # Rows arrive ordered by (position, id), so siblings stay ordered after grouping.
  defp nest(rows, root_id) do
    by_parent = Enum.group_by(rows, & &1.parent_id)

    build = fn build, node ->
      %{node: node, children: Enum.map(Map.get(by_parent, node.id, []), &build.(build, &1))}
    end

    tops =
      if root_id, do: Enum.filter(rows, &(&1.id == root_id)), else: Map.get(by_parent, nil, [])

    Enum.map(tops, &build.(build, &1))
  end

  defp invalid(key, message), do: {:error, {:validation_failed, %{key => message}}}
end
