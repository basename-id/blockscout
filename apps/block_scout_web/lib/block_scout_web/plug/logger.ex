defmodule BlockScoutWeb.Plug.Logger do
  @moduledoc """
    Extended version of Plug.Logger from https://github.com/elixir-plug/plug/blob/v1.14.0/lib/plug/logger.ex
    Added parameters to log API requests separately
    Usage example:
      `plug(BlockScoutWeb.Plug.Logger, application: :api_v2)`
  """

  require Logger
  alias Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts) do
    opts
  end

  @impl true
  def call(conn, opts) do
    level = Keyword.get(opts, :log, :info)

    Logger.log(
      level,
      fn ->
        [conn.method, ?\s, conn.request_path]
      end,
      opts
    )

    start = System.monotonic_time()

    Conn.register_before_send(conn, fn conn ->
      Logger.log(
        level,
        fn ->
          stop = System.monotonic_time()
          diff = System.convert_time_unit(stop - start, :native, :microsecond)
          status = Integer.to_string(conn.status)

          [connection_type(conn), ?\s, status, " in ", formatted_diff(diff)]
        end,
        opts
      )

      conn
    end)
  end

  defp formatted_diff(diff) when diff > 1000, do: [diff |> div(1000) |> Integer.to_string(), "ms"]
  defp formatted_diff(diff), do: [Integer.to_string(diff), "µs"]

  defp connection_type(%{state: :set_chunked}), do: "Chunked"
  defp connection_type(_), do: "Sent"
end
