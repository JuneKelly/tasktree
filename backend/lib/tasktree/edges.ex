defmodule Tasktree.Edges do
  @moduledoc """
  Adds and removes edges (the only writer of `edges`).

  Each add/remove writes one event per endpoint node (`edge_add` / `edge_remove`,
  payload `%{"edge" => %{...}}`) in the same transaction, so both nodes' histories
  show it. Edge changes do not bump node versions.

  Errors: `{:validation_failed, %{key => message}}`, `:cycle` (a `blocks` edge that
  would close a cycle), `:not_found` (remove only).
  """

  import Ecto.Query

  alias Tasktree.{Events, Repo}
  alias Tasktree.Edges.Edge
  alias Tasktree.Nodes.Node

  @blocks_lock 4202
  @keys ~w(from_id to_id kind)

  @spec add(String.t(), map()) :: {:ok, %Edge{}} | {:error, :cycle | {:validation_failed, map()}}
  def add(actor, attrs) when is_binary(actor) and is_map(attrs) do
    tx(fn ->
      with :ok <- allowed_keys(attrs),
           {:ok, from_id} <- node_id(attrs, "from_id"),
           {:ok, to_id} <- node_id(attrs, "to_id"),
           {:ok, kind} <- kind(attrs),
           :ok <-
             if(from_id == to_id, do: invalid("to_id", "must differ from from_id"), else: :ok),
           :ok <- lock_for(kind),
           :ok <- check_acyclic(kind, from_id, to_id),
           {:ok, edge} <- insert(from_id, to_id, kind) do
        append_events(actor, :edge_add, edge)
        {:ok, edge}
      end
    end)
  end

  @spec remove(String.t(), String.t()) :: {:ok, %Edge{}} | {:error, :not_found}
  def remove(actor, id) when is_binary(actor) and is_binary(id) do
    tx(fn ->
      case Repo.one(from e in Edge, where: e.id == ^id, lock: "FOR UPDATE") do
        nil ->
          {:error, :not_found}

        edge ->
          Repo.delete!(edge)
          append_events(actor, :edge_remove, edge)
          {:ok, edge}
      end
    end)
  end

  defp insert(from_id, to_id, kind) do
    %Edge{from_id: from_id, to_id: to_id, kind: kind}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:from_id, name: :edges_from_id_to_id_kind_index)
    |> Repo.insert()
    |> case do
      {:ok, edge} -> {:ok, edge}
      {:error, _changeset} -> invalid("kind", "edge already exists")
    end
  end

  defp append_events(actor, op, edge) do
    payload = %{
      "edge" => %{
        "id" => edge.id,
        "from_id" => edge.from_id,
        "to_id" => edge.to_id,
        "kind" => Atom.to_string(edge.kind)
      }
    }

    for node_id <- [edge.from_id, edge.to_id], do: Events.append!(actor, node_id, op, payload)
  end

  # Serializes `blocks` additions so two concurrent adds cannot jointly close a cycle.
  defp lock_for(:blocks) do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@blocks_lock])
    :ok
  end

  defp lock_for(_), do: :ok

  # `from blocks to` closes a cycle iff `from` is already reachable from `to`
  # by following `blocks` edges.
  defp check_acyclic(:blocks, from_id, to_id) do
    %{rows: rows} =
      Repo.query!(
        """
        WITH RECURSIVE reach(id) AS (
          SELECT $1::varchar
          UNION
          SELECT e.to_id FROM edges e JOIN reach r ON e.from_id = r.id WHERE e.kind = 'blocks'
        )
        SELECT 1 FROM reach WHERE id = $2 LIMIT 1
        """,
        [to_id, from_id]
      )

    if rows == [], do: :ok, else: {:error, :cycle}
  end

  defp check_acyclic(_, _, _), do: :ok

  defp allowed_keys(attrs) do
    case Map.keys(attrs) -- @keys do
      [] ->
        :ok

      unknown ->
        {:error, {:validation_failed, Map.new(unknown, &{to_string(&1), "unknown field"})}}
    end
  end

  defp node_id(attrs, key) do
    case Map.get(attrs, key) do
      id when is_binary(id) and id != "" ->
        if Repo.exists?(from n in Node, where: n.id == ^id),
          do: {:ok, id},
          else: invalid(key, "no such node")

      _ ->
        invalid(key, "is required and must be a node id")
    end
  end

  defp kind(attrs) do
    case Map.get(attrs, "kind") do
      "blocks" -> {:ok, :blocks}
      "relates" -> {:ok, :relates}
      _ -> invalid("kind", "must be \"blocks\" or \"relates\"")
    end
  end

  defp invalid(key, message), do: {:error, {:validation_failed, %{key => message}}}

  defp tx(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
