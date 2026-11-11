defmodule Tasktree.Nodes.Node do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: {Tasktree.ULID, :generate, []}}
  @foreign_key_type :string
  @timestamps_opts [type: :utc_datetime_usec]

  schema "nodes" do
    field :parent_id, :string
    field :position, :string
    field :title, :string
    field :body, :string, default: ""
    field :state, :string
    field :fields, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :claimed_by, :string
    field :claim_expires_at, :utc_datetime_usec
    field :version, :integer, default: 1

    # Derived predicates, populated only by Tasktree.Queries (SQL, DESIGN.md 3.7).
    field :blocked, :boolean, virtual: true
    field :claimable, :boolean, virtual: true

    timestamps()
  end
end
