defmodule Indexer.Fetcher.Optimism do
  @moduledoc """
  Contains common functions for Optimism* fetchers.
  """

  require Logger

  import EthereumJSONRPC,
    only: [fetch_block_number_by_tag: 2, json_rpc: 2, integer_to_quantity: 1, quantity_to_integer: 1, request: 1]

  alias ABI.TypeDecoder
  alias EthereumJSONRPC.Block.ByNumber
  alias Explorer.Chain.Data

  @eth_get_logs_range_size 1000

  def get_block_number_by_tag(tag, json_rpc_named_arguments, retries_left \\ 3) do
    case fetch_block_number_by_tag(tag, json_rpc_named_arguments) do
      {:ok, block_number} ->
        {:ok, block_number}

      {:error, message} ->
        retries_left = retries_left - 1

        error_message = "Cannot fetch #{tag} block number. Error: #{inspect(message)}"

        if retries_left <= 0 do
          Logger.error(error_message)
          {:error, message}
        else
          Logger.error("#{error_message} Retrying...")
          :timer.sleep(3000)
          get_block_number_by_tag(tag, json_rpc_named_arguments, retries_left)
        end
    end
  end

  def get_block_timestamp_by_number(number, json_rpc_named_arguments, retries_left \\ 3) do
    result =
      %{id: 0, number: number}
      |> ByNumber.request(false)
      |> json_rpc(json_rpc_named_arguments)

    return =
      with {:ok, block} <- result,
           false <- is_nil(block),
           timestamp <- Map.get(block, "timestamp"),
           false <- is_nil(timestamp) do
        {:ok, quantity_to_integer(timestamp)}
      else
        {:error, message} ->
          {:error, message}

        true ->
          {:error, "RPC returned nil."}
      end

    case return do
      {:ok, timestamp} ->
        {:ok, timestamp}

      {:error, message} ->
        retries_left = retries_left - 1

        error_message = "Cannot fetch block ##{number} or its timestamp. Error: #{inspect(message)}"

        if retries_left <= 0 do
          Logger.error(error_message)
          {:error, message}
        else
          Logger.error("#{error_message} Retrying...")
          :timer.sleep(3000)
          get_block_timestamp_by_number(number, json_rpc_named_arguments, retries_left)
        end
    end
  end

  def get_logs(from_block, to_block, address, topic0, json_rpc_named_arguments, retries_left) do
    req =
      request(%{
        id: 0,
        method: "eth_getLogs",
        params: [
          %{
            :fromBlock => integer_to_quantity(from_block),
            :toBlock => integer_to_quantity(to_block),
            :addresses => address,
            :topics => [topic0]
          }
        ]
      })

    case json_rpc(req, json_rpc_named_arguments) do
      {:ok, results} ->
        {:ok, results}

      {:error, message} ->
        retries_left = retries_left - 1

        error_message = "Cannot fetch logs for the block range #{from_block}..#{to_block}. Error: #{inspect(message)}"

        if retries_left <= 0 do
          Logger.error(error_message)
          {:error, message}
        else
          Logger.error("#{error_message} Retrying...")
          :timer.sleep(3000)
          get_logs(from_block, to_block, address, topic0, json_rpc_named_arguments, retries_left)
        end
    end
  end

  def get_transaction_by_hash(hash, json_rpc_named_arguments, retries_left \\ 3)

  def get_transaction_by_hash(hash, _json_rpc_named_arguments, _retries_left) when is_nil(hash), do: {:ok, nil}

  def get_transaction_by_hash(hash, json_rpc_named_arguments, retries_left) do
    req =
      request(%{
        id: 0,
        method: "eth_getTransactionByHash",
        params: [hash]
      })

    case json_rpc(req, json_rpc_named_arguments) do
      {:ok, tx} ->
        {:ok, tx}

      {:error, message} ->
        retries_left = retries_left - 1

        if retries_left <= 0 do
          {:error, message}
        else
          :timer.sleep(3000)
          get_transaction_by_hash(hash, json_rpc_named_arguments, retries_left)
        end
    end
  end

  def get_new_filter(from_block, to_block, address, topic0, json_rpc_named_arguments, retries_left \\ 3) do
    processed_from_block = if is_integer(from_block), do: integer_to_quantity(from_block), else: from_block
    processed_to_block = if is_integer(to_block), do: integer_to_quantity(to_block), else: to_block

    req =
      request(%{
        id: 0,
        method: "eth_newFilter",
        params: [
          %{
            :fromBlock => processed_from_block,
            :toBlock => processed_to_block,
            :addresses => address,
            :topics => [topic0]
          }
        ]
      })

    error_message = &"Cannot create new log filter. Error: #{inspect(&1)}"

    repeated_request(req, error_message, json_rpc_named_arguments, retries_left)
  end

  def get_filter_changes(filter_id, json_rpc_named_arguments, retries_left \\ 3) do
    req =
      request(%{
        id: 0,
        method: "eth_getFilterChanges",
        params: [filter_id]
      })

    error_message = &"Cannot fetch filter changes. Error: #{inspect(&1)}"

    repeated_request(req, error_message, json_rpc_named_arguments, retries_left)
  end

  defp repeated_request(req, error_message, json_rpc_named_arguments, retries_left) do
    case json_rpc(req, json_rpc_named_arguments) do
      {:ok, _results} = res ->
        res

      {:error, error} = err ->
        retries_left = retries_left - 1

        if retries_left <= 0 do
          Logger.error(error_message.(error))
          err
        else
          Logger.error("#{error_message.(error)} Retrying...")
          :timer.sleep(3000)
          repeated_request(req, error_message, json_rpc_named_arguments, retries_left)
        end
    end
  end

  def decode_data("0x", types) do
    for _ <- types, do: nil
  end

  def decode_data("0x" <> encoded_data, types) do
    encoded_data
    |> Base.decode16!(case: :mixed)
    |> TypeDecoder.decode_raw(types)
  end

  def decode_data(%Data{} = data, types) do
    data
    |> Data.to_string()
    |> decode_data(types)
  end

  def get_logs_range_size do
    @eth_get_logs_range_size
  end

  def parse_integer(integer_string) when is_binary(integer_string) do
    case Integer.parse(integer_string) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  def parse_integer(_integer_string), do: nil

  def json_rpc_named_arguments(optimism_rpc_l1) do
    [
      transport: EthereumJSONRPC.HTTP,
      transport_options: [
        http: EthereumJSONRPC.HTTP.HTTPoison,
        url: optimism_rpc_l1,
        http_options: [
          recv_timeout: :timer.minutes(10),
          timeout: :timer.minutes(10),
          hackney: [pool: :ethereum_jsonrpc]
        ]
      ]
    ]
  end
end
