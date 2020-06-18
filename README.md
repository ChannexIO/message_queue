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
