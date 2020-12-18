defmodule MessageQueue.Adapters.RabbitMQ.Producer do
  @moduledoc false

  @reconnect_interval 10_000

  use AMQP
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def initialize(queue, options) do
    GenServer.call(__MODULE__, {:initialize, queue, options})
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
  def handle_call({:initialize, queue, options}, _, conn) do
    case prepare_publish(conn, queue, options) do
      {:ok, %{channel: channel}} ->
        spawn(fn -> close_channel(channel) end)
        {:reply, :ok, conn}

      error ->
        {:reply, error, conn}
    end
  end

  @impl true
  def handle_call({:publish, message, queue, options}, _, conn) do
    case prepare_publish(conn, queue, options) do
      {:ok, %{channel: channel, routing_key: routing_key, exchange: exchange}} ->
        result = publish_message(channel, message, exchange, routing_key, options)
        spawn(fn -> close_channel(channel) end)

        {:reply, result, conn}

      error ->
        {:reply, error, conn}
    end
  end

  defp prepare_publish(conn, queue, options) do
    with {:ok, channel} <- Channel.open(conn),
         {:ok, exchange} <- get_exchange_name(queue, options),
         {:ok, %{channel: channel, routing_key: routing_key}} <-
           declare_and_bind_queue(exchange, channel, queue, options) do
      {:ok, %{channel: channel, routing_key: routing_key, exchange: exchange}}
    end
  end

  defp publish_message(channel, message, exchange, routing_key, options) do
    with :ok <- Confirm.select(channel),
         {:ok, encoded_message} <- Jason.encode(message),
         :ok <- Basic.publish(channel, exchange, routing_key, encoded_message, options),
         {:published, true} <- {:published, Confirm.wait_for_confirms(channel)} do
      :ok
    else
      {:published, _} -> {:error, :not_published}
      error -> error
    end
  end

  defp get_exchange_type(queue, options) do
    {_exchange_name, exchange_type} = get_exchange(queue, options)
    {:ok, exchange_type}
  end

  defp get_exchange_name(queue, options) do
    {exchange_name, _exchange_type} = get_exchange(queue, options)
    {:ok, exchange_name}
  end

  defp get_exchange(queues, options) when is_list(queues) do
    exchange_type = options[:exchange_type] || :fanout
    exchange_name = options[:exchange] || "amq.#{exchange_type}"
    {exchange_name, exchange_type}
  end

  defp get_exchange("" = _queue, options) do
    default_type = if match?([_ | _], options[:headers]), do: :headers, else: :direct
    exchange_type = options[:exchange_type] || default_type
    exchange_name = options[:exchange] || "amq.#{exchange_type}"
    {exchange_name, exchange_type}
  end

  defp get_exchange(_queue, options) do
    exchange_type = options[:exchange_type] || :direct
    exchange_name = options[:exchange] || "amq.#{exchange_type}"
    {exchange_name, exchange_type}
  end

  defp declare_and_bind_queue("amq.headers", channel, _queue, _options) do
    {:ok, %{routing_key: "", channel: channel}}
  end

  defp declare_and_bind_queue(exchange, channel, queues, options) do
    if match?([_ | _], options[:headers]) do
      {:ok, %{routing_key: "", channel: channel}}
    else
      declare_and_bind(exchange, channel, queues, options)
    end
  end

  defp declare_and_bind(exchange, channel, queues, options) when is_list(queues) do
    Enum.reduce_while(queues, {:ok, %{routing_key: "", channel: channel}}, fn queue, _acc ->
      case declare_and_bind(exchange, channel, queue, options) do
        {:ok, _} = result -> {:cont, result}
        error -> {:halt, error}
      end
    end)
  end

  defp declare_and_bind(exchange, channel, queue, options) do
    with {:ok, %{queue: queue}} <- Queue.declare(channel, queue, [{:passive, true} | options]),
         routing_key <- Keyword.get(options, :routing_key, queue),
         :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key) do
      {:ok, %{routing_key: routing_key, channel: channel}}
    else
      error ->
        spawn(fn -> close_channel(channel) end)
        error
    end
  catch
    :exit, {{:shutdown, {:server_initiated_close, 404, "NOT_FOUND - no queue" <> _}}, _} ->
      redeclare_and_bind_queue(exchange, channel, queue, options)
  end

  defp redeclare_and_bind_queue(exchange, channel, queue, options) do
    case Channel.open(channel.conn) do
      {:ok, channel} ->
        with {:ok, exchange_type} <- get_exchange_type(queue, options),
             :ok <- Exchange.declare(channel, exchange, exchange_type, options),
             {:ok, %{queue: queue}} <- Queue.declare(channel, queue, options),
             routing_key <- Keyword.get(options, :routing_key, queue),
             :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key) do
          {:ok, %{routing_key: routing_key, channel: channel}}
        else
          error ->
            spawn(fn -> close_channel(channel) end)
            error
        end

      error ->
        error
    end
  end

  defp close_channel(channel) do
    Channel.close(channel)
  end
end
