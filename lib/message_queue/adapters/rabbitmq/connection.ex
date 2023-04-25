defmodule MessageQueue.Adapters.RabbitMQ.Connection do
  @moduledoc false

  @behaviour MessageQueue.Adapters.Connection

  alias AMQP.Connection
  use GenServer
  require Logger

  @reconnect_interval 10_000
  @call_limit 2_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def get do
    GenServer.call(__MODULE__, :get)
  end

  # Callbacks

  @impl true
  def init(_) do
    {:ok, [], {:continue, :add_connect}}
  end

  @impl true
  def handle_call(:get, _from, [%{connection: conn, call_count: call_count} | tail_connections])
      when call_count + 1 >= @call_limit do
    {:reply, {:ok, conn}, [%{connection: conn, call_count: call_count + 1} | tail_connections],
     {:continue, :add_connect}}
  end

  @impl true
  def handle_call(:get, _from, [%{connection: conn, call_count: call_count} | tail_connections]) do
    {:reply, {:ok, conn}, [%{connection: conn, call_count: call_count + 1} | tail_connections]}
  end

  @impl true
  def handle_call(:get, _from, []) do
    {:reply, {:ok, nil}, [], {:continue, :add_connect}}
  end

  @impl true
  def handle_continue(:add_connect, state) do
    case MessageQueue.connection_details() do
      nil -> {:noreply, state}
      connection_details -> connect(connection_details, state)
    end
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, reason}, connections) do
    case Enum.reject(connections, &(&1.connection.pid == pid)) do
      [] ->
        {:stop, {:connection_lost, reason}, nil}

      connections ->
        {:noreply, connections}
    end
  end

  defp connect(connection_details, connections) do
    case Connection.open(connection_details) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        {:noreply, [%{connection: conn, call_count: 0} | connections]}

      _error ->
        Logger.error("[Connection] Failed to connect RabbitMQ. Reconnecting later...")
        Process.sleep(@reconnect_interval)
        {:noreply, connections, {:continue, :add_connect}}
    end
  catch
    :exit, error ->
      Logger.error("[Connection] RabbitMQ error: #{inspect(error)} Reconnecting later...")
      Process.sleep(@reconnect_interval)
      {:noreply, connections, {:continue, :add_connect}}
  end
end
