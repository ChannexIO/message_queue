defmodule MessageQueue.Adapters.Sandbox.Producer do
  @moduledoc false

  @behaviour MessageQueue.Adapters.Producer

  use GenServer

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def publish(_message, _queue, _options), do: :ok

  @impl true
  def delete_queue(_queue, _options), do: :ok
end
