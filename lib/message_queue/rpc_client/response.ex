defmodule MessageQueue.RPCClient.Response do
  @moduledoc """
    Module for prepare response form remote client
  """

  @spec prepare!(payload :: binary) :: term()
  def prepare!(payload) do
    payload
    |> Jason.decode!()
    |> case do
      ["ok" | tail] -> response_tuple(:ok, tail)
      ["error" | tail] -> response_tuple(:error, tail)
      value -> value
    end
  end

  defp response_tuple(resolution, tail) do
    List.to_tuple(tail) |> Tuple.insert_at(0, resolution)
  end
end
