defmodule MessageQueue.Adapters.Sandbox.Connection do
  @moduledoc false

  @behaviour MessageQueue.Adapters.Connection

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def get, do: {:ok, self()}
end
