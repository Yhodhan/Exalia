defmodule Exalia do
  alias Exalia.KNode
  alias Exalia.Config

  require Logger

  def bootstrap() do
    {:ok, pid, id} = new_node()

    # ping initial nodes
    Config.bootstrap_nodes()
    |> Enum.each(fn {ip, port} -> ping(pid, ip, port) end)

    # find nodes closer to Exalia
    contacts(pid)
    |> Enum.each(fn n -> find_nodes(pid, id, n.id) end)

    Logger.info("=== Succesful Bootstrapping ===")
    pid
  end

  def new_node(),
    do: KNode.new()

  def ping(pid, host, port),
    do: KNode.ping(pid, host, port)

  def find_nodes(pid, id, target),
    do: KNode.find_node(pid, id, target)

  def contacts(pid),
    do: KNode.contacs(pid)

  def node_id(pid),
    do: KNode.get_node_id(pid)

  def routing_table(pid),
    do: KNode.get_routing_table(pid)
end
