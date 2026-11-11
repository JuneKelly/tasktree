defmodule TasktreeWeb.EventController do
  use TasktreeWeb, :controller

  alias Tasktree.Events

  action_fallback TasktreeWeb.FallbackController

  def index(conn, _params) do
    with {:ok, page} <- Events.page(TasktreeWeb.QueryParams.decode(conn)) do
      render(conn, :index, page: page)
    end
  end
end
