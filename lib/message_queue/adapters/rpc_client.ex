defmodule MessageQueue.Adapters.RPCClient do
  @moduledoc """
    Behaviour for creating MessageQueue RPC clients
  """

  @callback call(module :: module | binary(), function :: binary() | atom, args :: list()) :: :ok
end
