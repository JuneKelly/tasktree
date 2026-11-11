defmodule TasktreeWeb.Router do
  use TasktreeWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug TasktreeWeb.AuthPlug
  end

  scope "/api", TasktreeWeb do
    pipe_through [:api, :authenticated]

    get "/me", MeController, :show
    get "/schema", SchemaController, :show
    get "/tree", TreeController, :show
    get "/events", EventController, :index

    get "/nodes", NodeController, :index
    post "/nodes", NodeController, :create
    get "/nodes/:id", NodeController, :show
    patch "/nodes/:id", NodeController, :update
    post "/nodes/:id/transition", NodeController, :transition
    post "/nodes/:id/move", NodeController, :move
    post "/nodes/:id/claim", NodeController, :claim
    post "/nodes/:id/release", NodeController, :release
    get "/nodes/:id/events", NodeController, :events

    post "/edges", EdgeController, :create
    delete "/edges/:id", EdgeController, :delete
  end
end
