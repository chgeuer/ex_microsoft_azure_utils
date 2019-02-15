defmodule Fiddler do
  @spec enable() :: :ok
  def enable(), do: "http_proxy" |> System.put_env("127.0.0.1:8888")

  @spec enable() :: :ok
  def disable(), do: "http_proxy" |> System.delete_env()
end
