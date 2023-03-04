defmodule BlockScoutWeb.API.APILogger do
  @moduledoc """
  Logger for API endpoints usage
  """
  require Logger

  @params [application: :api]

  def log(conn) do
    endpoint =
      if conn.query_string do
        "#{conn.request_path}?#{conn.query_string}"
      else
        conn.request_path
      end

    Logger.debug(endpoint, @params)
  end

  def message(text) do
    Logger.debug(text, @params)
  end

  def error(error) do
    Logger.error(error, @params)
  end
end
