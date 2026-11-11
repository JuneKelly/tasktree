defmodule Tasktree.Events.Event do
  use Ecto.Schema

  @ops [
    :create,
    :update,
    :transition,
    :move,
    :claim,
    :release,
    :claim_expired,
    :edge_add,
    :edge_remove
  ]

  @primary_key {:seq, :id, autogenerate: true}

  schema "events" do
    field :node_id, :string
    field :actor, :string
    field :op, Ecto.Enum, values: @ops
    field :payload, :map
    field :at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end
end
