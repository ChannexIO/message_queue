defmodule MessageQueue.RPCClient.Request do
  @moduledoc """
    Module for construct payload for remote call
  """

  @spec prepare(tuple) :: {:ok, map()} | {:error, term()}
  def prepare({module, function, args} = _command) do
    %{
      payload:
        encode_command(%{
          module: module,
          function: function,
          args: args
        }),
      correlation_id: get_correlation_id()
    }
  end

  defp encode_command(command) do
    Jason.encode!(command)
  end

  defp get_correlation_id do
    :erlang.unique_integer()
    |> :erlang.integer_to_binary()
    |> Base.encode64()
  end
end
