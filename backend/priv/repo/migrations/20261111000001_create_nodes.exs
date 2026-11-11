defmodule Tasktree.Repo.Migrations.CreateNodes do
  use Ecto.Migration

  def change do
    create table(:nodes, primary_key: false) do
      add :id, :string, primary_key: true
      add :parent_id, references(:nodes, type: :string, on_delete: :restrict)
      add :position, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false, default: ""
      add :state, :string, null: false
      add :fields, :map, null: false, default: %{}
      add :tags, {:array, :text}, null: false, default: []
      add :claimed_by, :string
      add :claim_expires_at, :utc_datetime_usec
      add :version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:nodes, :claim_both_or_neither,
             check: "(claimed_by IS NULL) = (claim_expires_at IS NULL)"
           )

    create constraint(:nodes, :fields_is_object, check: "jsonb_typeof(fields) = 'object'")

    create index(:nodes, [:parent_id, :position])
    create index(:nodes, [:state])
    create index(:nodes, [:tags], using: :gin)
    create index(:nodes, [:fields], using: :gin)
  end
end
