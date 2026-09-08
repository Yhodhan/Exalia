defmodule Exalia.Config do
  def bootstrap_nodes(),
    do: Application.get_env(:exalia, :bootstrap_nodes)

  def dht_port(),
    do: Application.get_env(:exalia, :dht_port)
end
