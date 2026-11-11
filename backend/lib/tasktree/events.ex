defmodule Tasktree.Events do
  @moduledoc """
  Append-only event log. `append!/4` is internal: only `Tasktree.Nodes` and
  `Tasktree.Edges` call it, inside the transaction that performs the mutation.
  """

  import Ecto.Query

  alias Tasktree.Events.Event
  alias Tasktree.Repo

  @doc false
  @spec append!(String.t(), String.t(), atom(), map()) :: %Event{}
  def append!(actor, node_id, op, payload)
      when is_binary(actor) and is_binary(node_id) and is_atom(op) and is_map(payload) do
    Repo.insert!(%Event{actor: actor, node_id: node_id, op: op, payload: payload})
  end

  @doc "Events for a node, oldest first."
  @spec list_for_node(String.t()) :: [%Event{}]
  def list_for_node(node_id) do
    Repo.all(from e in Event, where: e.node_id == ^node_id, order_by: e.seq)
  end

  @doc "Up to `limit` events with `seq > since`, oldest first, plus the last seq seen (`since` if none)."
  @spec list_since(non_neg_integer(), pos_integer()) :: {[%Event{}], non_neg_integer()}
  def list_since(since, limit) when is_integer(since) and is_integer(limit) and limit > 0 do
    events = Repo.all(from e in Event, where: e.seq > ^since, order_by: e.seq, limit: ^limit)
    {events, if(events == [], do: since, else: List.last(events).seq)}
  end

  @default_page 100
  @max_page 1000

  @doc """
  Feed page from raw query params: `since` (seq, default 0) and `limit` (default #{@default_page}, max #{@max_page}).
  """
  @spec page(map()) ::
          {:ok, %{data: [%Event{}], last_seq: non_neg_integer()}}
          | {:error, {:validation_failed, map()}}
  def page(params) when is_map(params) do
    with :ok <- known(params),
         {:ok, since} <- int(params, "since", 0, 0..9_223_372_036_854_775_807),
         {:ok, limit} <- int(params, "limit", @default_page, 1..@max_page) do
      {events, last_seq} = list_since(since, limit)
      {:ok, %{data: events, last_seq: last_seq}}
    end
  end

  defp known(params) do
    case Map.keys(params) -- ~w(since limit) do
      [] -> :ok
      unknown -> {:error, {:validation_failed, Map.new(unknown, &{&1, "unknown parameter"})}}
    end
  end

  defp int(params, key, default, range) do
    value =
      case Map.get(params, key, default) do
        s when is_binary(s) -> with {n, ""} <- Integer.parse(s), do: n
        other -> other
      end

    if is_integer(value) and value in range, do: {:ok, value}, else: bad(key, range)
  end

  defp bad(key, range),
    do:
      {:error,
       {:validation_failed,
        %{key => "must be an integer between #{range.first} and #{range.last}"}}}
end
