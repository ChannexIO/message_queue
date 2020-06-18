defmodule MessageQueue.RPCClient do
  @moduledoc """
    Module for remote procedure calling
  """

  def child_spec(opts) do
    %{
      id: MessageQueue.rpc_client(),
      start: {MessageQueue.rpc_client(), :start_link, [opts]}
    }
  end

  @spec call(module :: module | binary(), function :: binary() | atom, args :: list()) :: :ok
  def call(module, function, args) do
    MessageQueue.rpc_client().call(module, function, args)
  end
end
