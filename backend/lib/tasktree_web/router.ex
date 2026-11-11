defmodule TasktreeWeb.Router do
  use TasktreeWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TasktreeWeb do
    pipe_through :api
  end
end
