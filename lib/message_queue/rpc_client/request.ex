defmodule MessageQueue.RPCClient.Request do
  @moduledoc """
    Module for construct payload for remote call
  """

  @spec prepare(tuple) :: {:ok, map()} | {:error, term()}
  def prepare({service_name, function, args} = _command) do
    command = %{service_name: service_name, function: function, args: args}

    with {:ok, payload} <- encode_command(command) do
      {:ok, %{payload: payload, correlation_id: get_correlation_id()}}
    end
  end

  defp encode_command(command) do
    Jason.encode(command)
  end

  defp get_correlation_id do
    :erlang.unique_integer()
    |> :erlang.integer_to_binary()
    |> Base.encode64()
  end
end
