# Benchmark: MessageQueue.publish/3 vs MessageQueue.publish_all/2
#
# Requires a running RabbitMQ on localhost:5672 (default guest/guest).
#
#   mix run bench/publish_vs_publish_all.exs
#
# Override batch sizes:
#   BATCH_SIZES=10,100,500 mix run bench/publish_vs_publish_all.exs

Application.put_env(:message_queue, :adapter, :rabbitmq)
Application.put_env(:message_queue, :app_name, "bench")
Application.put_env(:message_queue, :producer_workers_count, 1)

Application.put_env(:message_queue, :connection,
  host: System.get_env("RABBITMQ_HOST", "localhost"),
  port: String.to_integer(System.get_env("RABBITMQ_PORT", "5672")),
  username: System.get_env("RABBITMQ_USER", "guest"),
  password: System.get_env("RABBITMQ_PASS", "guest"),
  virtual_host: System.get_env("RABBITMQ_VHOST", "/")
)

{:ok, _} = Application.ensure_all_started(:message_queue)

# Give the producer worker a moment to open its channel against the broker.
Process.sleep(500)

queue = "bench.publish_all"

# Declare a transient queue once so messages have somewhere to land.
{:ok, conn} = MessageQueue.get_connection()
{:ok, chan} = AMQP.Channel.open(conn)
{:ok, _} = AMQP.Queue.declare(chan, queue, durable: false, auto_delete: true)
:ok = AMQP.Queue.purge(chan, queue) |> case do
  {:ok, _} -> :ok
  other -> other
end
AMQP.Channel.close(chan)

batch_sizes =
  System.get_env("BATCH_SIZES", "10,100,500")
  |> String.split(",", trim: true)
  |> Enum.map(&String.to_integer/1)

build_messages = fn n ->
  for i <- 1..n, do: %{id: i, payload: "msg-#{i}"}
end

inputs =
  batch_sizes
  |> Enum.map(fn n -> {"#{n} messages", build_messages.(n)} end)
  |> Map.new()

Benchee.run(
  %{
    "publish (sequential)" => fn messages ->
      Enum.each(messages, fn msg ->
        :ok = MessageQueue.publish(msg, queue, message_type: :json)
      end)
    end,
    "publish_all (batch)" => fn messages ->
      tuples = Enum.map(messages, &{&1, queue, [message_type: :json]})
      :ok = MessageQueue.publish_all(tuples)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 5,
  memory_time: 0,
  print: [configuration: false]
)

# Drain so the queue doesn't fill up between runs.
{:ok, conn} = MessageQueue.get_connection()
{:ok, chan} = AMQP.Channel.open(conn)
AMQP.Queue.purge(chan, queue)
AMQP.Channel.close(chan)
