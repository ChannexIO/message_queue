# MessageQueue

## Usage

### Configuration

```elixir
# in config/config.exs

config :message_queue,
  app_name: my_app,
  adapter: :rabbitmq,
  rpc_modules: [SampleModule]
```

* `app_name` - name of your application
* `adapter` - kind of adapter. Possible values: `:rabbitmq`, `:sandbox`
* `rpc_modules` - modules are available for remote call

### Using Adapters

An adapter is a set of instructions for how to communicate with a specific service.

MessageQueue provides adapters for use RabbitMQ and for testing. To use these adapters, declare them in the environment configuration.

You can create new adapters for any environment by implementing the `MessageQueue.Adapters.Producer`, `MessageQueue.Adapters.Consumer`, `MessageQueue.Adapters.RPCServer` or `MessageQueue.Adapters.RPCCclient` behaviour.

```elixir
config :message_queue,
  adapter: MessageQueue.CustomLocalAdapter
```

In that case you must define module(s) for specific logic. 

**Follow the naming convention!**

For example:

```
MessageQueue.CustomLocalAdapter.Producer
MessageQueue.CustomLocalAdapter.Consumer
MessageQueue.CustomLocalAdapter.RPCServer
MessageQueue.CustomLocalAdapter.RPCClient
```

### Consumer

```elixir
use MessageQueue.Consumer

def start_link(_opts) do
  GenServer.start_link(__MODULE__, %{queue: "queue", prefetch_count: 1}, name: __MODULE__)
end

def handle_message(payload, meta, state) do
  ...
end
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `message_queue` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:message_queue, github: "ChannexIO/message_queue"}
  ]
end
```
