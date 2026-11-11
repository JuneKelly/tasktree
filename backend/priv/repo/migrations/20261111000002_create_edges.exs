defmodule Tasktree.Repo.Migrations.CreateEdges do
  use Ecto.Migration

  def change do
    create table(:edges, primary_key: false) do
      add :id, :string, primary_key: true
      add :from_id, references(:nodes, type: :string, on_delete: :restrict), null: false
      add :to_id, references(:nodes, type: :string, on_delete: :restrict), null: false
      add :kind, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:edges, [:from_id, :to_id, :kind])
    create index(:edges, [:to_id])
    create constraint(:edges, :no_self_edge, check: "from_id <> to_id")
    create constraint(:edges, :valid_kind, check: "kind IN ('blocks', 'relates')")
  end
end
