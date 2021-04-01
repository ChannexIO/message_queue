defmodule MessageQueue.RPCClient.Response do
  @moduledoc """
    Module for prepare response form remote client
  """

  @spec prepare!(payload :: binary) :: term()
  def prepare!(payload) do
    :erlang.binary_to_term(payload, [:safe])
  end
end
