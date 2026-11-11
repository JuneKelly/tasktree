defmodule Tasktree.SchemaConstraintsTest do
  use Tasktree.DataCase, async: true

  alias Tasktree.Edges.Edge
  alias Tasktree.Events.Event
  alias Tasktree.Nodes.Node
  alias Tasktree.Repo

  defp new_node(attrs \\ %{}) do
    struct!(Node, Map.merge(%{position: "a", title: "t", state: "TODO"}, attrs))
  end

  defp insert_nodes do
    {Repo.insert!(new_node()), Repo.insert!(new_node())}
  end

  test "node insert applies documented defaults and ULID id" do
    n = Repo.insert!(new_node())
    assert byte_size(n.id) == 26
    assert %{body: "", fields: %{}, tags: [], version: 1} = Repo.get!(Node, n.id)
  end

  test "ULIDs sort by creation time" do
    a = Tasktree.ULID.generate()
    Process.sleep(2)
    assert a < Tasktree.ULID.generate()
  end

  test "claimed_by without claim_expires_at is rejected" do
    assert_raise Ecto.ConstraintError, ~r/claim_both_or_neither/, fn ->
      Repo.insert!(new_node(%{claimed_by: "agent:x"}))
    end
  end

  test "claim_expires_at without claimed_by is rejected" do
    assert_raise Ecto.ConstraintError, ~r/claim_both_or_neither/, fn ->
      Repo.insert!(new_node(%{claim_expires_at: DateTime.utc_now()}))
    end
  end

  test "both claim columns set is accepted" do
    Repo.insert!(new_node(%{claimed_by: "agent:x", claim_expires_at: DateTime.utc_now()}))
  end

  test "title and state are required" do
    assert_raise Postgrex.Error, ~r/not_null_violation|null value/, fn ->
      Repo.insert!(new_node(%{title: nil}))
    end

    assert_raise Postgrex.Error, ~r/not_null_violation|null value/, fn ->
      Repo.insert!(new_node(%{state: nil}))
    end
  end

  test "parent_id must reference an existing node" do
    assert_raise Ecto.ConstraintError, ~r/nodes_parent_id_fkey/, fn ->
      Repo.insert!(new_node(%{parent_id: Tasktree.ULID.generate()}))
    end
  end

  test "edge happy path" do
    {a, b} = insert_nodes()
    e = Repo.insert!(%Edge{from_id: a.id, to_id: b.id, kind: :blocks})
    assert %Edge{kind: :blocks} = Repo.get!(Edge, e.id)
  end

  test "duplicate edge is rejected, same pair with other kind is allowed" do
    {a, b} = insert_nodes()
    Repo.insert!(%Edge{from_id: a.id, to_id: b.id, kind: :blocks})
    Repo.insert!(%Edge{from_id: a.id, to_id: b.id, kind: :relates})

    assert_raise Ecto.ConstraintError, ~r/edges_from_id_to_id_kind_index/, fn ->
      Repo.insert!(%Edge{from_id: a.id, to_id: b.id, kind: :blocks})
    end
  end

  test "self edge is rejected" do
    {a, _} = insert_nodes()

    assert_raise Ecto.ConstraintError, ~r/no_self_edge/, fn ->
      Repo.insert!(%Edge{from_id: a.id, to_id: a.id, kind: :blocks})
    end
  end

  test "unknown edge kind is rejected at the DB" do
    {a, b} = insert_nodes()

    assert_raise Postgrex.Error, ~r/valid_kind/, fn ->
      Repo.query!(
        "INSERT INTO edges (id, from_id, to_id, kind, inserted_at) VALUES ($1,$2,$3,'bogus',now())",
        [Tasktree.ULID.generate(), a.id, b.id]
      )
    end
  end

  defp event do
    Repo.insert!(%Event{
      node_id: "n1",
      actor: "human:dev",
      op: :create,
      payload: %{"after" => %{}}
    })
  end

  test "event insert assigns increasing seq" do
    e1 = event()
    e2 = event()
    assert e2.seq > e1.seq
  end

  test "event node_id has no FK" do
    assert %Event{} = event()
  end

  test "UPDATE on events fails at the DB level" do
    e = event()

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.query!("UPDATE events SET actor = 'x' WHERE seq = $1", [e.seq])
    end
  end

  test "DELETE on events fails at the DB level" do
    e = event()

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.query!("DELETE FROM events WHERE seq = $1", [e.seq])
    end
  end

  test "TRUNCATE on events fails at the DB level" do
    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.query!("TRUNCATE events")
    end
  end
end
