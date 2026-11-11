defmodule TasktreeWeb.MeController do
  use TasktreeWeb, :controller

  def show(conn, _params), do: json(conn, %{actor: conn.assigns.actor})
end
