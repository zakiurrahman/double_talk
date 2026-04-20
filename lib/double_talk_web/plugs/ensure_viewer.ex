defmodule DoubleTalkWeb.Plugs.EnsureViewer do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "viewer_id") do
      nil -> put_session(conn, "viewer_id", new_viewer_id())
      _viewer_id -> conn
    end
  end

  defp new_viewer_id do
    12
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
