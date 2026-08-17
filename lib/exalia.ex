defmodule Exalia do
  alias Exalia.KNode

  def new_node(),
    do: KNode.new()

  def ping(pid, host, port),
    do: KNode.ping(pid, host, port)

  def contacts(pid),
    do: KNode.contacs(pid)

end
