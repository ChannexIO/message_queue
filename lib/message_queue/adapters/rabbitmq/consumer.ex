defmodule MessageQueue.Adapters.RabbitMQ.Consumer do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      @reconnect_interval 10_000

      alias AMQP.{Channel, Connection, Exchange, Queue, Basic}
      use GenServer
      require Logger

      @impl true
      def init(options) do
        {:ok, %{options: options}, {:continue, :connect}}
      end

      @impl true
      def handle_continue(:connect, %{options: options} = state) do
        host = System.fetch_env!("AMQP_CONNECTION_URL")
        prefetch_count = Map.get(options, :prefetch_count, 1)
        queue = Map.get(options, :queue)
        queue_options = Map.get(options, :queue_options, [])

        with {:ok, conn} <- Connection.open(host),
             {:ok, channel} <- Channel.open(conn),
             :ok <- Basic.qos(channel, prefetch_count: prefetch_count),
             {:ok, _} <- Queue.declare(channel, queue, queue_options ++ [durable: true]),
             {:ok, _} <- Basic.consume(channel, queue) do
          Process.monitor(channel.pid)
          {:noreply, %{channel: channel, options: options}}
        else
          {:error, _} ->
            Logger.error("Failed to connect #{host}. Reconnecting later...")
            Process.sleep(@reconnect_interval)
            {:noreply, state, {:continue, :connect}}
        end
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
      def handle_info({:basic_consume_ok, %{consumer_tag: _}}, state) do
        {:noreply, state, :hibernate}
      end

      @impl true
      def handle_info({:basic_cancel, %{consumer_tag: _}}, state) do
        {:stop, :normal, state, :hibernate}
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

      def handle_message(payload, meta, state), do: :ok

      defp ack(%{channel: channel} = state, %{delivery_tag: tag} = _meta, options \\ []) do
        Basic.ack(channel, tag, options)
      end

      defp reject(%{channel: channel} = state, %{delivery_tag: tag} = _meta, options \\ []) do
        Basic.reject(channel, tag, options)
      end

      defoverridable handle_message: 3
    end
  end
end
