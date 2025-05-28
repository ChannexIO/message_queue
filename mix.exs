defmodule MessageQueue.MixProject do
  use Mix.Project

  @name "MessageQueue"
  @version "0.8.3"
  @repo_url "https://github.com/ChannexIO/message_queue"

  def project do
    [
      app: :message_queue,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      name: @name,
      source_url: @repo_url,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MessageQueue.Application, []}
    ]
  end

  defp deps do
    [
      {:amqp, "~> 3.3"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 0.4 or ~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false}
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
