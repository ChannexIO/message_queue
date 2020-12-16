defmodule MessageQueue.MixProject do
  use Mix.Project

  @name "MessageQueue"
  @version "0.2.0"
  @repo_url "https://github.com/ChannexIO/message_queue"

  def project do
    [
      app: :message_queue,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      name: @name,
      source_url: @repo_url,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:lager, :logger],
      mod: {MessageQueue.Application, []}
    ]
  end

  defp deps do
    [
      {:amqp, "~> 1.6"},
      {:jason, "~> 1.2"}
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      source_url: @repo_url,
      main: @name
    ]
  end
end
