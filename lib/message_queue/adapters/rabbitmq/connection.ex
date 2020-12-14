defmodule MessageQueue.Adapters.RabbitMQ.Connection do
  @moduledoc false

  alias AMQP.Connection
  use GenServer
  require Logger

  @reconnect_interval 10_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def get do
    GenServer.call(__MODULE__, :get)
  end

  # Callbacks

  @impl true
  def init(_) do
    {:ok, %{connection: nil}, {:continue, :connect}}
  end

  @impl true
  def handle_call(:get, _from, %{connection: conn} = state) do
    {:reply, {:ok, conn}, state}
  end

  @impl true
  def handle_continue(:connect, state) do
    case MessageQueue.connection_details() do
      nil -> {:noreply, state}
      connection_details -> connect(connection_details, state)
    end
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    {:stop, {:connection_lost, reason}, nil}
  end

  defp connect(connection_details, state) do
    with {:ok, conn} <- Connection.open(connection_details) do
      Process.monitor(conn.pid)
      {:noreply, %{connection: conn}}
    else
      _error ->
        Logger.error("Failed to connect RabbitMQ. Reconnecting later...")
        Process.sleep(@reconnect_interval)
        {:noreply, state, {:continue, :connect}}
    end
  catch
    :exit, error ->
      Logger.error("RabbitMQ error: #{inspect(error)} Reconnecting later...")
      Process.sleep(@reconnect_interval)
      {:noreply, state, {:continue, :connect}}
  end
end
