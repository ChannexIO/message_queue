defmodule MessageQueue.Adapters.RabbitMQ.ProducerWorkerTest do
  use ExUnit.Case, async: false

  alias MessageQueue.Adapters.RabbitMQ.ProducerWorker

  defmodule TestBasic do
    @moduledoc false
    def return(_channel, _pid), do: :ok

    def publish(channel, exchange, routing_key, payload, options) do
      send(self(), {:publish, channel, exchange, routing_key, payload, options})
      Application.get_env(:message_queue, :test_basic_publish_result, :ok)
    end
  end

  defmodule TestConfirm do
    @moduledoc false
    def select(_channel), do: :ok

    def wait_for_confirms(_channel),
      do: Application.get_env(:message_queue, :test_confirm_result, true)
  end

  defmodule TestQueue do
    @moduledoc false
    def delete(_channel, _queue, _options), do: {:ok, %{}}

    def declare(channel, queue, options) do
      send(self(), {:declare, channel, queue, options})
      {:ok, %{queue: queue}}
    end

    def bind(channel, queue, exchange, options) do
      send(self(), {:bind, channel, queue, exchange, options})
      :ok
    end
  end

  defmodule TestExchange do
    @moduledoc false
    def declare(channel, exchange, exchange_type, options) do
      send(self(), {:exchange_declare, channel, exchange, exchange_type, options})
      :ok
    end
  end

  setup do
    previous_modules = Application.get_env(:message_queue, :amqp_modules)
    previous_confirm_result = Application.get_env(:message_queue, :test_confirm_result)
    previous_publish_result = Application.get_env(:message_queue, :test_basic_publish_result)

    Application.put_env(:message_queue, :amqp_modules, %{
      basic: TestBasic,
      confirm: TestConfirm,
      queue: TestQueue,
      exchange: TestExchange
    })

    Application.put_env(:message_queue, :test_confirm_result, true)
    Application.put_env(:message_queue, :test_basic_publish_result, :ok)

    on_exit(fn ->
      restore_env(:amqp_modules, previous_modules)
      restore_env(:test_confirm_result, previous_confirm_result)
      restore_env(:test_basic_publish_result, previous_publish_result)
    end)

    :ok
  end

  test "request publish encodes fresh messages and sets mandatory by default" do
    assert :ok =
             ProducerWorker.request(:test_channel, {
               :publish,
               %{id: 42},
               "known.queue",
               [message_type: :json]
             })

    assert_received {:publish, :test_channel, "", "known.queue", payload, options}
    assert payload == ~s({"id":42})
    assert options[:mandatory] == true
  end

  test "request publish with no message_type defaults to compressed_json" do
    assert :ok =
             ProducerWorker.request(:test_channel, {
               :publish,
               %{id: 42},
               "known.queue",
               []
             })

    assert_received {:publish, :test_channel, "", "known.queue", payload, _options}
    assert <<120, 156, _rest::binary>> = payload
    assert {:ok, %{"id" => 42}} = MessageQueue.decode_data(payload)
  end

  test "request publish with message_type :compressed_json produces zlib-compressed JSON" do
    assert :ok =
             ProducerWorker.request(:test_channel, {
               :publish,
               %{id: 42},
               "known.queue",
               [message_type: :compressed_json]
             })

    assert_received {:publish, :test_channel, "", "known.queue", payload, _options}
    assert <<120, 156, _rest::binary>> = payload
    assert {:ok, %{"id" => 42}} = MessageQueue.decode_data(payload)
  end

  test "request publish with message_type :ext_binary produces Erlang binary" do
    assert :ok =
             ProducerWorker.request(:test_channel, {
               :publish,
               %{id: 42},
               "known.queue",
               [message_type: :ext_binary]
             })

    assert_received {:publish, :test_channel, "", "known.queue", payload, _options}
    assert <<131, _rest::binary>> = payload
    assert {:ok, %{id: 42}} = MessageQueue.decode_data(payload)
  end

  test "request publish with message_type :raw passes the binary through unchanged" do
    uuid = "550e8400-e29b-41d4-a716-446655440000"

    assert :ok =
             ProducerWorker.request(:test_channel, {
               :publish,
               uuid,
               "known.queue",
               [message_type: :raw]
             })

    assert_received {:publish, :test_channel, "", "known.queue", payload, _options}
    assert payload == uuid
  end

  test "request publish with message_type :raw rejects non-binary payloads" do
    assert {:error, _} =
             ProducerWorker.request(:test_channel, {
               :publish,
               %{id: 42},
               "known.queue",
               [message_type: :raw]
             })

    refute_received {:publish, _, _, _, _, _}
  end

  test "request publish returns error when confirm fails" do
    Application.put_env(:message_queue, :test_confirm_result, false)

    assert {:error, :not_published} =
             ProducerWorker.request(:test_channel, {
               :publish,
               %{id: 42},
               "known.queue",
               [message_type: :json]
             })

    assert_received {:publish, :test_channel, "", "known.queue", ~s({"id":42}), _options}
  end

  test "NO_ROUTE republish reuses returned payload without re-encoding" do
    payload = <<120, 156, 83, 178, 176, 180, 76, 51, 73, 51, 76, 209, 77, 51, 54, 54>>

    meta = %{
      reply_text: "NO_ROUTE",
      exchange: "",
      routing_key: "missing.queue",
      headers: :undefined,
      reply_to: :undefined
    }

    assert {:noreply, %{chan: :test_channel}} =
             ProducerWorker.handle_info({:basic_return, payload, meta}, %{chan: :test_channel})

    assert_received {:declare, :test_channel, "missing.queue", declare_options}
    assert declare_options[:routing_key] == "missing.queue"

    assert_received {:publish, :test_channel, "", "missing.queue", ^payload, publish_options}
    assert publish_options[:routing_key] == "missing.queue"
    refute_received {:publish, _, _, _, _, _}
  end

  test "NO_ROUTE declare flow keeps channel and exchange order for list routing keys" do
    payload = <<120, 156, 83, 178, 176, 180>>

    meta = %{
      reply_text: "NO_ROUTE",
      exchange: "amq.fanout",
      routing_key: ["queue.one", "queue.two"]
    }

    assert {:noreply, %{chan: :test_channel}} =
             ProducerWorker.handle_info({:basic_return, payload, meta}, %{chan: :test_channel})

    assert_received {:exchange_declare, :test_channel, "amq.fanout", :fanout, _}
    assert_received {:declare, :test_channel, "queue.one", declare_options_one}
    assert_received {:bind, :test_channel, "queue.one", "amq.fanout", bind_options_one}
    assert_received {:declare, :test_channel, "queue.two", declare_options_two}
    assert_received {:bind, :test_channel, "queue.two", "amq.fanout", bind_options_two}

    assert_received {:publish, :test_channel, "amq.fanout", ["queue.one", "queue.two"], ^payload, publish_options}

    assert declare_options_one[:routing_key] == ["queue.one", "queue.two"]
    assert bind_options_one[:routing_key] == ["queue.one", "queue.two"]
    assert declare_options_two[:routing_key] == ["queue.one", "queue.two"]
    assert bind_options_two[:routing_key] == ["queue.one", "queue.two"]
    assert publish_options[:routing_key] == ["queue.one", "queue.two"]
  end

  test "NO_ROUTE uses reply_to before routing_key when redeclaring, binding, and republishing" do
    payload = <<120, 156, 83, 178, 176, 180>>

    meta = %{
      reply_text: "NO_ROUTE",
      exchange: "amq.direct",
      routing_key: "missing.queue",
      reply_to: "reply.queue"
    }

    assert {:noreply, %{chan: :test_channel}} =
             ProducerWorker.handle_info({:basic_return, payload, meta}, %{chan: :test_channel})

    assert_received {:exchange_declare, :test_channel, "amq.direct", :direct, _}
    assert_received {:declare, :test_channel, "reply.queue", declare_options}
    assert declare_options[:routing_key] == "reply.queue"

    assert_received {:bind, :test_channel, "reply.queue", "amq.direct", bind_options}
    assert bind_options[:routing_key] == "reply.queue"

    assert_received {:publish, :test_channel, "amq.direct", "reply.queue", ^payload, publish_options}

    assert publish_options[:routing_key] == "missing.queue"
    assert publish_options[:reply_to] == "reply.queue"
  end

  defp restore_env(key, nil), do: Application.delete_env(:message_queue, key)
  defp restore_env(key, value), do: Application.put_env(:message_queue, key, value)
end
