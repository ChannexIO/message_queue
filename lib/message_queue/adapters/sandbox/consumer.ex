defmodule MessageQueue.Adapters.Sandbox.Consumer do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use GenServer

      @impl true
      def init(state), do: {:ok, state}

      defp ack(_state, _meta, _options \\ []), do: :ok
      defp reject(_state, _meta, _options \\ []), do: :ok
    end
  end
end
