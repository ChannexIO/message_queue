defmodule MessageQueue.RPCServer do
  @moduledoc """
    Module for getting reply from remote server
  """

  def child_spec(opts) do
    %{
      id: MessageQueue.rpc_server(),
      start: {MessageQueue.rpc_server(), :start_link, [opts]}
    }
  end
end
