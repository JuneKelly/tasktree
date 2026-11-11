defmodule TasktreeWeb.SchemaController do
  use TasktreeWeb, :controller

  def show(conn, _params), do: render(conn, :show, workflow: Tasktree.Workflow.for_node(nil))
end
