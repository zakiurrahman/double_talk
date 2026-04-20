defmodule DoubleTalk.Repo do
  use Ecto.Repo,
    otp_app: :double_talk,
    adapter: Ecto.Adapters.Postgres
end
