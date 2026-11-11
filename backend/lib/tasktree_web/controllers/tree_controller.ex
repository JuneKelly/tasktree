defmodule TasktreeWeb.TreeController do
  use TasktreeWeb, :controller

  alias Tasktree.Queries
  alias TasktreeWeb.QueryParams

  action_fallback TasktreeWeb.FallbackController

  def show(conn, _params) do
    with {:ok, tree} <- Queries.tree(QueryParams.decode(conn)) do
      render(conn, :show, tree: tree)
    end
  end
end
