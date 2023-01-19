defmodule MessageQueue.Adapters.Sandbox.RPCClient do
  @moduledoc false

  @behaviour MessageQueue.Adapters.RPCClient

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def call(_module, _function, _args, _opts), do: :ok

  @impl true
  def cast(_module, _function, _args), do: :ok
end
