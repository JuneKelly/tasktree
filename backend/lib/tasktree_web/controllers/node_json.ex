defmodule TasktreeWeb.NodeJSON do
  alias Tasktree.Workflow

  def index(%{result: %{data: nodes, next_cursor: cursor}}),
    do: %{data: Enum.map(nodes, &data/1), next_cursor: cursor}

  def show(%{detail: %{node: node, children: children, edges: edges}}) do
    node
    |> data()
    |> Map.merge(%{
      children: children,
      edges: %{out: Enum.map(edges.out, &edge/1), in: Enum.map(edges.in, &edge/1)}
    })
  end

  def node(%{node: node}), do: data(node)

  def events(%{events: events}), do: %{data: Enum.map(events, &TasktreeWeb.EventJSON.data/1)}

  @doc """
  Node as JSON. An expired claim is treated as absent. `blocked`/`claimable` are included
  only when the node came from `Tasktree.Queries` (which computes them in SQL).
  """
  def data(node) do
    wf = Workflow.for_node(node)

    live? =
      node.claimed_by != nil and
        DateTime.compare(node.claim_expires_at, DateTime.utc_now()) == :gt

    base = %{
      id: node.id,
      parent_id: node.parent_id,
      position: node.position,
      title: node.title,
      body: node.body,
      state: node.state,
      fields: node.fields,
      tags: node.tags,
      claimed_by: if(live?, do: node.claimed_by),
      claim_expires_at: if(live?, do: node.claim_expires_at),
      version: node.version,
      inserted_at: node.inserted_at,
      updated_at: node.updated_at,
      allowed_transitions: Map.fetch!(wf.states, node.state).next
    }

    for {k, v} <- [blocked: node.blocked, claimable: node.claimable],
        v != nil,
        into: base,
        do: {k, v}
  end

  def edge(e),
    do: %{id: e.id, from_id: e.from_id, to_id: e.to_id, kind: e.kind, inserted_at: e.inserted_at}
end
