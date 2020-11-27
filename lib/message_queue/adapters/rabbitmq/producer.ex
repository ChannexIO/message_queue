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
    case Channel.open(conn) do
      {:ok, channel} ->
        with {:ok, exchange} <- get_exchange_name(queue, options),
             {:ok, routing_key} <- declare_and_bind_queue(exchange, channel, queue, options),
             :ok <- Confirm.select(channel),
             {:ok, encoded_message} <- Jason.encode(message),
             :ok <- Basic.publish(channel, exchange, routing_key, encoded_message, options),
             {:published, true} <- {:published, Confirm.wait_for_confirms(channel)} do
          spawn(fn -> close_channel(channel) end)
          {:reply, :ok, conn}
        else
          {:published, _} ->
            spawn(fn -> close_channel(channel) end)
            {:reply, {:error, :not_published}, conn}

          error ->
            spawn(fn -> close_channel(channel) end)
            {:reply, error, conn}
        end

      {:error, error} ->
        {:reply, error, conn}
    end
  end

  defp get_exchange_name(queues, option) when is_list(queues), do: {:ok, "amq.fanout"}

  defp get_exchange_name("" = queue, options) do
    if match?([_ | _], options[:headers]), do: {:ok, "amq.headers"}, else: {:ok, "amq.direct"}
  end

  defp get_exchange_name(_queue, _options), do: {:ok, "amq.direct"}

  defp declare_and_bind_queue("amq.headers", _channel, _queue, _options), do: {:ok, ""}

  defp declare_and_bind_queue(exchange, channel, queues, options) when is_list(queues) do
    Enum.reduce_while(queues, {:ok, ""}, fn queue, acc ->
      case declare_and_bind_queue(exchange, channel, queue, options) do
        {:ok, _routing_key} -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp declare_and_bind_queue(exchange, channel, queue, options) do
    options = Keyword.put_new(options, :durable, true)

    with {:ok, %{queue: queue}} <- Queue.declare(channel, queue, [{:passive, true} | options]),
         routing_key <- Keyword.get(options, :routing_key, queue),
         :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key) do
      {:ok, routing_key}
    end
  catch
    :exit, _ ->
      with {:ok, channel} <- Channel.open(channel.conn),
           {:ok, %{queue: queue}} <- Queue.declare(channel, queue, options),
           routing_key <- Keyword.get(options, :routing_key, queue),
           :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key) do
        {:ok, routing_key}
      end
  end

  defp close_channel(channel) do
    Channel.close(channel)
  end
end
