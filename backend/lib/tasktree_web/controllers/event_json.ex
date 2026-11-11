defmodule TasktreeWeb.EventJSON do
  def index(%{page: %{data: events, last_seq: last_seq}}),
    do: %{data: Enum.map(events, &data/1), last_seq: last_seq}

  def data(e),
    do: %{seq: e.seq, node_id: e.node_id, actor: e.actor, op: e.op, payload: e.payload, at: e.at}
end
