defmodule MessageQueue.Adapters.Sandbox.RPCServer do
  @moduledoc false

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(state), do: {:ok, state}
end
