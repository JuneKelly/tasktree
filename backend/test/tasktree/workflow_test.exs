defmodule Tasktree.WorkflowTest do
  use ExUnit.Case, async: true

  alias Tasktree.Workflow

  defp valid do
    {c, _} = Code.eval_file(Application.fetch_env!(:tasktree, :workflow_path))
    c
  end

  defp wf, do: Workflow.current()

  test "shipped config loads at boot" do
    assert %{initial: "TODO"} = wf()
    assert Workflow.for_node(%{}) == wf()
  end

  test "load!/1 raises on a missing file and on syntax errors" do
    tmp = Path.join(System.tmp_dir!(), "wf_#{System.unique_integer([:positive])}.exs")
    assert_raise ArgumentError, ~r/cannot load/, fn -> Workflow.load!(tmp) end
    File.write!(tmp, "%{")
    on_exit(fn -> File.rm(tmp) end)
    assert_raise ArgumentError, ~r/cannot load/, fn -> Workflow.load!(tmp) end
  end

  test "load!/1 raises on a malformed config" do
    tmp = Path.join(System.tmp_dir!(), "wf_#{System.unique_integer([:positive])}.exs")
    File.write!(tmp, "%{initial: \"X\"}")
    on_exit(fn -> File.rm(tmp) end)
    assert_raise ArgumentError, ~r/invalid workflow config/, fn -> Workflow.load!(tmp) end
  end

  describe "validate/1" do
    test "accepts the shipped config" do
      assert {:ok, _} = Workflow.validate(valid())
    end

    test "rejects non-maps, missing and unknown top-level keys" do
      assert {:error, _} = Workflow.validate([])
      assert {:error, _} = Workflow.validate(Map.delete(valid(), :actionable))
      assert {:error, _} = Workflow.validate(Map.put(valid(), :extra, 1))
    end

    test "rejects unknown initial / actionable / next / require_fields" do
      assert {:error, _} = Workflow.validate(%{valid() | initial: "NOPE"})
      assert {:error, _} = Workflow.validate(%{valid() | actionable: ["NOPE"]})

      bad_next = put_in(valid(), [:states, "TODO", :next], ["NOPE"])
      assert {:error, _} = Workflow.validate(bad_next)

      bad_req = put_in(valid(), [:states, "DONE", :require_fields], ["nope"])
      assert {:error, _} = Workflow.validate(bad_req)
    end

    test "rejects bad state shapes" do
      assert {:error, _} = Workflow.validate(put_in(valid(), [:states, "TODO", :terminal], "no"))
      assert {:error, _} = Workflow.validate(put_in(valid(), [:states, "TODO", :bogus], 1))
      assert {:error, _} = Workflow.validate(%{valid() | states: %{}})
    end

    test "rejects bad field defs" do
      assert {:error, _} = Workflow.validate(put_in(valid(), [:fields, "x"], %{type: "float"}))
      assert {:error, _} = Workflow.validate(put_in(valid(), [:fields, "x"], %{type: "enum"}))

      assert {:error, _} =
               Workflow.validate(put_in(valid(), [:fields, "x"], %{type: "enum", values: []}))

      assert {:error, _} =
               Workflow.validate(
                 put_in(valid(), [:fields, "x"], %{type: "string", values: ["a"]})
               )

      assert {:error, _} = Workflow.validate(%{valid() | fields: %{}})
    end
  end

  describe "check_transition/4" do
    test "allowed transition" do
      assert :ok = Workflow.check_transition(wf(), "TODO", "DOING", %{})
    end

    test "illegal transition" do
      assert {:error, {:illegal_transition, "TODO", "DONE"}} =
               Workflow.check_transition(wf(), "TODO", "DONE", %{"outcome" => "x"})
    end

    test "unknown states" do
      assert {:error, {:unknown_state, "X"}} = Workflow.check_transition(wf(), "X", "TODO", %{})
      assert {:error, {:unknown_state, "X"}} = Workflow.check_transition(wf(), "TODO", "X", %{})
    end

    test "required fields" do
      assert {:error, {:missing_fields, ["outcome"]}} =
               Workflow.check_transition(wf(), "DOING", "DONE", %{})

      assert :ok = Workflow.check_transition(wf(), "DOING", "DONE", %{"outcome" => "ok"})
    end
  end

  test "terminal?/2" do
    assert Workflow.terminal?(wf(), "DONE")
    refute Workflow.terminal?(wf(), "TODO")
  end

  describe "validate_fields/2" do
    test "accepts valid values" do
      f = %{"outcome" => "x", "effort" => 5, "deadline" => "2026-01-02", "priority" => "A"}
      assert :ok = Workflow.validate_fields(wf(), f)
    end

    test "rejects unknown fields" do
      assert {:error, {:unknown_field, "nope"}} = Workflow.validate_fields(wf(), %{"nope" => 1})
    end

    test "rejects wrong types" do
      for {k, v} <- [
            {"outcome", 1},
            {"effort", "5"},
            {"deadline", "not-a-date"},
            {"deadline", 5},
            {"priority", "Z"}
          ] do
        assert {:error, {:invalid_field, ^k}} = Workflow.validate_fields(wf(), %{k => v})
      end
    end
  end
end
