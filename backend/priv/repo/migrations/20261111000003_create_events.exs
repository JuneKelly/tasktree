defmodule Tasktree.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def up do
    create table(:events, primary_key: false) do
      add :seq, :bigserial, primary_key: true
      add :node_id, :string, null: false
      add :actor, :string, null: false
      add :op, :string, null: false
      add :payload, :map, null: false
      add :at, :utc_datetime_usec, null: false
    end

    create index(:events, [:node_id, :seq])

    create constraint(:events, :valid_op,
             check:
               "op IN ('create','update','transition','move','claim','release','claim_expired','edge_add','edge_remove')"
           )

    execute """
    CREATE FUNCTION events_reject_mutation() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'events is append-only (% rejected)', TG_OP
        USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER events_append_only
    BEFORE UPDATE OR DELETE ON events
    FOR EACH ROW EXECUTE FUNCTION events_reject_mutation()
    """

    execute """
    CREATE TRIGGER events_no_truncate
    BEFORE TRUNCATE ON events
    FOR EACH STATEMENT EXECUTE FUNCTION events_reject_mutation()
    """
  end

  def down do
    execute "DROP TRIGGER events_no_truncate ON events"
    execute "DROP TRIGGER events_append_only ON events"
    execute "DROP FUNCTION events_reject_mutation()"
    drop table(:events)
  end
end
