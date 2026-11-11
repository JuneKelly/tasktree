defmodule Tasktree.Repo.Migrations.NodesPositionBytewiseCollation do
  use Ecto.Migration

  # Position keys are ordered bytewise (0-9 < A-Z < a-z, see Tasktree.Position);
  # the database default collation would order them case-insensitively.
  def up do
    execute ~s|ALTER TABLE nodes ALTER COLUMN position TYPE varchar(255) COLLATE "C"|
  end

  def down do
    execute ~s|ALTER TABLE nodes ALTER COLUMN position TYPE varchar(255) COLLATE "default"|
  end
end
