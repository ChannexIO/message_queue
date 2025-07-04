defmodule MessageQueue.Adapters.RabbitMQ.Consumer do
  @moduledoc """
  A RabbitMQ consumer for MessageQueue.

  ## Options

  * `:queue` - Required. The name of the queue
  * `:prefetch_count` - Optional. Prefetch options used by the RabbitMQ client. By default is 1
  * `:queue_options` - Optional. Queue options used by RabbitMQ client. For example:
    %{queue_options: [
      durable: false, arguments: [
        {"x-dead-letter-exchange", :longstr, ""},
        {"x-dead-letter-routing-key", :longstr, "tasks.errors"}
      ]
    ]

    `durable: true` will be added automatically.
  * `:bindings. Optional. a list of bindings for the `:queue`. This option
    allows you to bind the queue to one or more exchanges. Each binding is a tuple
    `{exchange_name, binding_options}` where so that the queue will be bound
    to `exchange_name` through `AMQP.Queue.bind/4` using `binding_options` as
    the options. Bindings are idempotent so you can bind the same queue to the
    same exchange multiple times.
  * `:after_connect` - a function that takes the AMQP channel that the consumer is
    connected to and can run arbitrary setup. This is useful for declaring complex
    RabbitMQ topologies with possibly multiple queues, bindings, or exchanges. This
    function can return `:ok` if everything went well or `{:error, reason}`.
  """

  defmacro __using__(_opts) do
    quote do
      @reconnect_interval 10_000

      alias AMQP.{Basic, Channel, Connection, Exchange, Queue}
      use GenServer
      require Logger

      @module_name inspect(__MODULE__)

      @impl true
      def init(options) do
        Process.flag(:trap_exit, true)
        {:ok, %{options: options}, {:continue, :connect}}
      end

      @impl true
      def handle_continue(:connect, %{options: options} = state) do
        prefetch_count = Map.get(options, :prefetch_count, 1)
        queue = Map.get(options, :queue)
        queue_options = Map.get(options, :queue_options, [])
        binding_options = Map.get(options, :bindings, [])
        after_connect = Map.get(options, :after_connect, fn _channel -> :ok end)
        consumer_tag = Map.get(options, :consumer_tag, "")

        with {:ok, conn} <- MessageQueue.get_connection(),
             {:ok, channel} <- Channel.open(conn),
             :ok <- call_after_connect(after_connect, channel),
             :ok <- Basic.qos(channel, prefetch_count: prefetch_count),
             {:ok, _} <- Queue.declare(channel, queue, queue_options ++ [durable: true]),
             :ok <- binding_if_needs(channel, queue, binding_options),
             {:ok, _} <- Basic.consume(channel, queue, nil, consumer_tag: consumer_tag) do
          Logger.info("[#{@module_name}] Connected to RabbitMQ. Consumer started.")
          Process.monitor(channel.pid)
          {:noreply, %{channel: channel, options: options}}
        else
          error ->
            Logger.error("[#{@module_name}] Failed to connect RabbitMQ. Reconnecting later...")

            Process.sleep(@reconnect_interval)
            {:noreply, state, {:continue, :connect}}
        end
      catch
        :exit, error ->
          Logger.error(
            "[#{@module_name}] RabbitMQ error: #{inspect(error)} Reconnecting later..."
          )

          Process.sleep(@reconnect_interval)
          {:noreply, state, {:continue, :connect}}
      end

      @impl true
      def handle_info({:DOWN, _, :process, _pid, reason}, _) do
        {:stop, {:connection_lost, reason}, nil}
      end

      @impl true
      def handle_info({:EXIT, _, :normal}, _state) do
        {:stop, :normal, nil}
      end

      @impl true
      def handle_info({_ref, {:ok, _connection}}, state) do
        {:noreply, state}
      end

      @impl true
      def handle_info({:basic_consume_ok, %{consumer_tag: _}}, state) do
        {:noreply, state, :hibernate}
      end

      @impl true
      def handle_info({:basic_cancel, %{consumer_tag: _}}, state) do
        {:stop, :normal, state}
      end

      @impl true
      def handle_info({:basic_cancel_ok, %{consumer_tag: _}}, state) do
        {:noreply, state, :hibernate}
      end

      @impl true
      def handle_info({:basic_deliver, payload, meta}, state) do
        handle_message(payload, meta, state)
        {:noreply, state, :hibernate}
      end

      @impl true
      def terminate(_, %{channel: channel} = _state) do
        if is_pid(channel.pid) and Process.alive?(channel.pid) do
          Channel.close(channel)
        end

        :normal
      end

      @impl true
      def terminate(_, _), do: :normal

      def handle_message(payload, meta, state), do: :ok

      defp ack(%{channel: channel} = state, %{delivery_tag: tag} = _meta, options \\ []) do
        Basic.ack(channel, tag, options)
      end

      defp reject(%{channel: channel} = state, %{delivery_tag: tag} = _meta, options \\ []) do
        Basic.reject(channel, tag, options)
      end

      defp binding_if_needs(_, _, []), do: :ok

      defp binding_if_needs(channel, queue, bindings) do
        Enum.reduce_while(bindings, :ok, fn {exchange, options}, result ->
          case Queue.bind(channel, queue, exchange, options) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
      end

      defp call_after_connect(after_connect, channel) do
        case after_connect.(channel) do
          :ok ->
            :ok

          {:error, reason} ->
            {:error, reason}

          other ->
            raise "unexpected return value from the :after_connect function: #{inspect(other)}"
        end
      end

      defoverridable handle_message: 3
    end
  end
end
