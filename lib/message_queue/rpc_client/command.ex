defmodule MessageQueue.RPCClient.Command do
  @moduledoc """
    Module for calling function of module with given args from rpc message
  """

  require Logger

  @spec run(payload :: binary()) ::
          term() | {:error, :internal_error} | {:error, :not_supported_method}
  def run(payload) do
    payload
    |> execute()
    |> encode()
  end

  defp execute(payload) do
    try do
      with {:ok, %{"module" => module, "function" => function, "args" => args}} <-
             Jason.decode(payload),
           {:ok, module} <- get_module_name(module),
           {:ok, function} <- get_function_name(function),
           true <- module in MessageQueue.rpc_modules(),
           true <- Code.ensure_loaded?(module),
           true <- function_exported?(module, function, length(args)) do
        apply(module, function, args)
      else
        _ -> {:error, :not_supported_method}
      end
    rescue
      error ->
        Logger.error(inspect(error))
        {:error, :internal_error}
    end
  end

  defp encode(msg) do
    with {:ok, encoded_msg} <- Jason.encode(msg) do
      encoded_msg
    else
      {:error, error} ->
        Logger.warn("JSON Encode error #{inspect(error)}")
        {:error, :encode_error}
    end
  end

  defp get_module_name(module) do
    {:ok, Module.concat([module])}
  end

  defp get_function_name(function) do
    try do
      {:ok, String.to_existing_atom(function)}
    rescue
      _ -> :error
    end
  end
end
