defmodule MessageQueue.Adapters.RabbitMQ.Producer do
  @moduledoc false

  @reconnect_interval 10_000

  use AMQP
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def publish(message, queue, options) do
    GenServer.call(__MODULE__, {:publish, message, queue, options})
  end

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    connection = MessageQueue.connection()

    case Connection.open(connection) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        {:noreply, conn}

      {:error, _} ->
        Logger.error("Failed to connect RabbitMQ. Reconnecting later...")
        Process.sleep(@reconnect_interval)
        {:noreply, state, {:continue, :connect}}
    end
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    {:stop, {:connection_lost, reason}, nil}
  end

  @impl true
  def handle_call({:publish, message, queue, options}, _, conn) do
    with {:ok, channel} <- Channel.open(conn),
         {:ok, routing_key} <- get_routing_key(queue),
         {:ok, %{exchange: exchange, channel: channel}} <- get_exchange_name(channel, queue),
         :ok <- Confirm.select(channel),
         {:ok, encoded_message} <- Jason.encode(message),
         :ok <-
           Basic.publish(
             channel,
             exchange,
             routing_key,
             encoded_message,
             options
           ),
         {:published, true} <- {:published, Confirm.wait_for_confirms(channel)} do
      spawn(fn -> close_channel(channel) end)
      {:reply, :ok, conn}
    else
      {:published, _} -> {:reply, {:error, :not_published}, conn}
      error -> {:reply, error, conn}
    end
  end

  defp get_routing_key(queues) when is_list(queues), do: {:ok, ""}
  defp get_routing_key(queue), do: {:ok, queue}

  defp get_exchange_name(channel, queues) when is_list(queues) do
    exchange = "amq.fanout"

    Enum.reduce_while(queues, channel, fn queue, channel ->
      case queue_declare_and_bind(channel, queue, exchange, "") do
        {:ok, %{channel: channel}} -> {:cont, channel}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, channel} -> {:ok, %{channel: channel, exchange: exchange}}
      error -> error
    end
  end

  defp get_exchange_name(channel, queue) do
    exchange = "amq.direct"

    queue_declare_and_bind(channel, queue, exchange, queue)
  end

  defp queue_declare_and_bind(%{conn: conn} = channel, queue, exchange, routing_key) do
    with {:ok, _} <- Queue.declare(channel, queue, durable: true, passive: true),
         :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key) do
      {:ok, %{exchange: exchange, channel: channel}}
    end
  catch
    :exit, _ ->
      with {:ok, channel} <- Channel.open(conn),
           {:ok, _} <- Queue.declare(channel, queue, durable: true),
           :ok <- Queue.bind(channel, queue, exchange, routing_key: queue) do
        {:ok, %{exchange: exchange, channel: channel}}
      end
  end

  defp close_channel(channel) do
    Channel.close(channel)
  end
end
