defmodule MessageQueue.RPCClient.Request do
  @moduledoc """
    Module for construct payload for remote call
  """

  @spec prepare_call(tuple) :: {:ok, map()}
  def prepare_call(command) do
    command = prepare_command(command)

    with {:ok, payload} <- encode_command(command) do
      {:ok, %{payload: payload, correlation_id: get_correlation_id()}}
    end
  end

  @spec prepare_cast(tuple) :: {:ok, map()}
  def prepare_cast(command) do
    command = prepare_command(command)

    with {:ok, payload} <- encode_command(command) do
      {:ok, %{payload: payload}}
    end
  end

  defp prepare_command({service_name, function, args}) do
    %{service_name: service_name, function: function, args: args}
  end

  defp encode_command(command) do
    {:ok, :erlang.term_to_binary(command)}
  end

  defp get_correlation_id do
    :erlang.unique_integer()
    |> :erlang.integer_to_binary()
    |> Base.encode64()
  end
end
