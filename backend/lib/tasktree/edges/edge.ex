defmodule Tasktree.Edges.Edge do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: {Tasktree.ULID, :generate, []}}
  @foreign_key_type :string

  schema "edges" do
    field :from_id, :string
    field :to_id, :string
    field :kind, Ecto.Enum, values: [:blocks, :relates]

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
