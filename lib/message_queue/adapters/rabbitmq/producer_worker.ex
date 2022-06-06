defmodule MessageQueue.Adapters.RabbitMQ.ProducerWorker do
  @moduledoc false

  @reconnect_interval :timer.seconds(10)

  use AMQP
  use GenServer

  require Logger

  alias MessageQueue.Adapters.RabbitMQ.ProcessRegistry
  alias MessageQueue.{Message, Utils}

  @doc false
  def request(pid, request) do
    GenServer.call(pid, request, Utils.call_timeout())
  end

  @doc false
  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, hibernate_after: 15_000)
  end

  @impl GenServer
  def init(state) do
    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    with {:ok, conn} <- MessageQueue.get_connection(),
         {:ok, chan} <- Channel.open(conn),
         :ok <- Basic.return(chan, self()),
         :ok <- Confirm.select(chan) do
      ProcessRegistry.register(:producer_workers, nil)
      Process.monitor(conn.pid)
      Process.monitor(chan.pid)
      {:noreply, %{conn: conn, chan: chan}}
    else
      {:error, _} ->
        Logger.error("Failed to connect RabbitMQ. Reconnecting later...")
        Process.sleep(@reconnect_interval)
        {:noreply, state, {:continue, :connect}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{chan: %{pid: pid}, conn: conn}) do
    case Channel.open(conn) do
      {:ok, chan} -> {:noreply, %{conn: conn, chan: chan}}
      _ -> {:stop, {:connection_lost, reason}, nil}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, _state) do
    {:stop, {:connection_lost, reason}, nil}
  end

  def handle_info({:basic_return, payload, %{reply_text: "NO_ROUTE"} = meta}, state) do
    options = Enum.reject(meta, &(elem(&1, 1) == :undefined))
    declare_and_publish(state.chan, payload, options)
    {:noreply, state}
  end

  def handle_info({_ref, {:ok, _connection}}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:publish, message, queue, options}, _, state) do
    exchange = get_exchange_name(queue, options)
    routing_key = get_routing_key(exchange, queue, options)
    options = Keyword.put_new(options, :mandatory, true)
    response = publish_message(state.chan, message, exchange, routing_key, options)
    {:reply, response, state}
  end

  @impl true
  def handle_call({:delete_queue, queue, options}, _, state) do
    case Queue.delete(state.chan, queue, options) do
      {:ok, _} -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  defp publish_message(channel, message, exchange, routing_key, options) do
    with {:ok, encoded_message} <- encode_message(message, options),
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
    exchange_type
  end

  defp get_exchange_name(queue, options) do
    {exchange_name, _exchange_type} = get_exchange(queue, options)
    exchange_name
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

  defp get_exchange(queue, options) do
    exchange_type = options[:exchange_type] || :direct
    exchange_name = options[:exchange]
    routing_key = get_routing_key(exchange_name, queue, options)

    exchange_name =
      cond do
        queue == routing_key -> ""
        exchange_name -> exchange_name
        true -> "amq.#{exchange_type}"
      end

    {exchange_name, exchange_type}
  end

  defp get_routing_key("amq.headers", _queue, _options), do: ""

  defp get_routing_key(_exchange, queues, options) when is_list(queues) do
    Keyword.get(options, :routing_key, "")
  end

  defp get_routing_key(_exchange, queue, options) do
    if match?([_ | _], options[:headers]), do: "", else: Keyword.get(options, :routing_key, queue)
  end

  defp declare_and_publish(channel, message, options) do
    routing_key = options[:reply_to] || options[:routing_key] || ""
    exchange = options[:exchange]
    exchange_type = get_exchange_type(routing_key, options)

    with :ok <- declare_exchange(channel, exchange, exchange_type, options),
         {:ok, queue} <- declare_and_bind(channel, exchange, routing_key, options),
         :ok <- bind_queue(channel, queue, exchange, routing_key: routing_key) do
      publish_message(channel, message, exchange, routing_key, options)
    end
  end

  # The default exchange is a direct exchange with no name (empty string)
  # pre-declared by the broker...
  defp declare_exchange(_channel, "", _exchange_type, _options), do: :ok

  defp declare_exchange(channel, exchange, exchange_type, options) do
    Exchange.declare(channel, exchange, exchange_type, [{:durable, true} | options])
  end

  defp declare_and_bind(channel, exchange, queues, options) when is_list(queues) do
    Enum.reduce_while(queues, {:ok, %{routing_key: ""}}, fn queue, _acc ->
      case declare_and_bind(exchange, channel, queue, options) do
        {:ok, _} = result -> {:cont, result}
        error -> {:halt, error}
      end
    end)
  end

  defp declare_and_bind(channel, exchange, queue, options) do
    with {:ok, %{queue: queue}} <- Queue.declare(channel, queue, options),
         routing_key <- Keyword.get(options, :routing_key, queue),
         :ok <- bind_queue(channel, queue, exchange, routing_key: routing_key) do
      {:ok, queue}
    else
      error -> error
    end
  end

  # ...every queue that is created is automatically bound to it with a routing
  # key which is the same as the queue name.
  defp bind_queue(_channel, _queue, "", _options), do: :ok

  defp bind_queue(channel, queue, exchange, options) do
    Queue.bind(channel, queue, exchange, options)
  end

  defp encode_message(message, opts) do
    Message.encode(message,
      type: opts[:message_type],
      parser_opts: opts[:message_parser_opts] || []
    )
  end
end
