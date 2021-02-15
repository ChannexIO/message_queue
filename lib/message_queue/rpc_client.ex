defmodule MessageQueue.RPCClient do
  @moduledoc """
    Module for remote procedure calling
  """

  @behaviour MessageQueue.Adapters.RPCClient

  def child_spec(opts) do
    %{
      id: MessageQueue.rpc_client(),
      start: {MessageQueue.rpc_client(), :start_link, [opts]}
    }
  end

  def call(module, function, args) do
    MessageQueue.rpc_client().call(module, function, args)
  end
end
