defmodule TasktreeWeb.MiscControllerTest do
  use TasktreeWeb.ConnCase, async: false

  import TasktreeWeb.ApiHelpers

  defp edge(a, b, kind \\ "blocks"),
    do: %{"from_id" => a["id"], "to_id" => b["id"], "kind" => kind}

  describe "edges" do
    test "create 201, show reflects edges and blocked, delete 204" do
      a = create_node()
      b = create_node()
      e = json!(api(:post, "/api/edges", edge(a, b)), 201)
      assert %{"kind" => "blocks", "from_id" => _, "to_id" => _} = e

      assert %{"edges" => %{"out" => [%{"id" => id}]}} =
               json!(api(:get, "/api/nodes/#{a["id"]}"), 200)

      assert id == e["id"]

      assert %{"blocked" => true, "claimable" => false} =
               json!(api(:get, "/api/nodes/#{b["id"]}"), 200)

      assert response(api(:delete, "/api/edges/#{e["id"]}"), 204) == ""
      assert %{"blocked" => false} = json!(api(:get, "/api/nodes/#{b["id"]}"), 200)
    end

    test "error contract: 422 cycle, 422 validation_failed, 404 not_found" do
      a = create_node()
      b = create_node()
      json!(api(:post, "/api/edges", edge(a, b)), 201)
      error!(api(:post, "/api/edges", edge(b, a)), 422, "cycle")
      error!(api(:post, "/api/edges", edge(a, b)), 422, "validation_failed")
      error!(api(:post, "/api/edges", edge(a, a)), 422, "validation_failed")

      error!(
        api(:post, "/api/edges", Map.put(edge(a, b), "actor", "x")),
        422,
        "validation_failed"
      )

      error!(api(:delete, "/api/edges/nope"), 404, "not_found")
    end

    test "edge events attribute the token's actor" do
      a = create_node()
      b = create_node()
      json!(api(:post, "/api/edges", edge(a, b), token: agent()), 201)
      assert %{"data" => evs} = json!(api(:get, "/api/nodes/#{a["id"]}/events"), 200)
      assert %{"op" => "edge_add", "actor" => "agent:test"} = List.last(evs)
    end
  end

  describe "tree" do
    test "nested outline with depth and root" do
      r = create_node()
      c = create_node(%{"parent_id" => r["id"]})
      g = create_node(%{"parent_id" => c["id"]})

      assert %{"data" => roots} = json!(api(:get, "/api/tree"), 200)
      root = Enum.find(roots, &(&1["id"] == r["id"]))
      assert [%{"id" => cid, "children" => [%{"id" => gid, "children" => []}]}] = root["children"]
      assert {cid, gid} == {c["id"], g["id"]}

      assert %{"data" => [%{"children" => [%{"children" => []}]}]} =
               json!(api(:get, "/api/tree?root=#{r["id"]}&depth=2"), 200)

      error!(api(:get, "/api/tree?root=nope"), 404, "not_found")
      error!(api(:get, "/api/tree?depth=0"), 422, "validation_failed")
    end
  end

  describe "schema" do
    test "is driven by the workflow config" do
      s = json!(api(:get, "/api/schema"), 200)
      assert s["initial"] == "TODO"
      assert s["actionable"] == ["NEXT", "TODO"]
      assert s["transitions"]["DOING"] == ["TODO", "NEXT", "DONE", "CANCELLED"]

      assert %{"name" => "DONE", "terminal" => true, "require_fields" => ["outcome"]} =
               Enum.find(s["states"], &(&1["name"] == "DONE"))

      assert %{"type" => "enum", "values" => ["A", "B", "C"]} = s["fields"]["priority"]
    end
  end
end
