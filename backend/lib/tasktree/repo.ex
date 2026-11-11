defmodule Tasktree.Repo do
  use Ecto.Repo,
    otp_app: :tasktree,
    adapter: Ecto.Adapters.Postgres
end
