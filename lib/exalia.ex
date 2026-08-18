defmodule Exalia do
  alias Exalia.KNode
  alias Exalia.Config
  alias Exalia.RoutingTable

  require Logger

  @alpha 3
  @k 8

  def bootstrap() do
    {:ok, pid, id} = new_node()

    # ping initial nodes
    Config.bootstrap_nodes()
    |> Task.async_stream(
      fn {ip, port} -> ping(pid, ip, port) end,
      timeout: 6000,
      on_timeout: :kill_task
    )
    |> Enum.to_list()

    # find nodes closer to Exalia
    Logger.info("=== INIT ITERATIVE LOOKUP ===")

    iterative_lookup(pid, id)

    Logger.info("=== SUCCESSFUL BOOTSTRAPPING ===")

    {:ok, pid}
  end

  def get_peers(pid, infohash) do
    # 1 - get the contacts
    # 2 - loop on them calling get_peers(p, c, i)
    # 3 - for those that return :peers, store them. If not call lookup iteratively
    # 4 - join all answers 
  end

  # -----------------
  #   Main API calls
  # -----------------

  def ping(pid, host, port),
    do: KNode.ping(pid, host, port)

  def find_nodes(pid, contact, target),
    do: KNode.find_node(pid, contact, target)

  def get_peers(pid, contact, infohash),
    do: KNode.get_peers(pid, contact, infohash)

  # ------------------
  #  Helper functions
  # ------------------

  def new_node(),
    do: KNode.new()

  def get_contacts(pid),
    do: KNode.contacs(pid)

  def node_id(pid),
    do: KNode.get_node_id(pid)

  def routing_table(pid),
    do: KNode.get_routing_table(pid)

  # -------------------
  #  Private functions
  # -------------------

  defp closest_nodes(pid, target, alpha) do
    routing_table(pid).kbuckets
    |> Map.values()
    |> List.flatten()
    |> Enum.sort_by(fn c -> RoutingTable.xor_distance(c.id, target) end)
    |> Enum.take(alpha)
  end

  def iterative_lookup(pid, target) do
    initial_nodes = closest_nodes(pid, target, @alpha)
    do_lookup(pid, target, initial_nodes, _queried = MapSet.new(), _best = [], _round = 8)
  end

  def do_lookup(_pid, _target, _to_query, _queried, best, 0), do: best

  def do_lookup(pid, target, to_query, queried, best, rounds) do
    new_candidates =
      to_query
      |> Task.async_stream(
        fn n -> find_nodes(pid, n, target) end,
        timeout: 6000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, candidates} when is_list(candidates) -> candidates
        _ -> []
      end)

    queried = Enum.reduce(to_query, queried, fn n, acc -> MapSet.put(acc, n.id) end)

    best =
      (best ++ new_candidates)
      |> Enum.sort_by(fn c -> RoutingTable.xor_distance(c.id, target) end)
      |> Enum.take(@k)

    next_to_query =
      best
      |> Enum.reject(fn c -> MapSet.member?(queried, c.id) end)
      |> Enum.take(@alpha)

    if Enum.empty?(next_to_query),
      do: best,
      else: do_lookup(pid, target, next_to_query, queried, best, rounds - 1)
  end
end
