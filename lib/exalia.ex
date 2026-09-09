defmodule Exalia do
  alias Exalia.KNode
  alias Exalia.Config
  alias Exalia.RoutingTable
  alias Exalia.Utils

  require Logger

  @alpha 6
  @k 8

  def bootstrap() do
    {:ok, pid, id} = new_node()

    # ping initial nodes
    Config.bootstrap_nodes()
    |> Task.async_stream(
      fn {ip, port} -> ping(pid, ip, port) end,
      timeout: 2000,
      on_timeout: :kill_task
    )
    |> Enum.to_list()

    # find nodes closer to Exalia
    Logger.info("=== INIT LOOKUP ===")

    lookup(pid, id)

    Logger.info("=== SUCCESSFUL BOOTSTRAPPING ===")

    {:ok, pid, id}
  end

  # -----------------
  #   Main API calls
  # -----------------

  def ping(pid, host, port),
    do: KNode.ping(pid, host, port)

  def find_nodes(pid, contact, target),
    do: KNode.find_node(pid, contact, target)

  def get_peers(pid, infohash) do
    # 4 - join all answers
    contacts = get_contacts(pid)

    lookup_peers(
      pid,
      infohash,
      contacts,
      MapSet.new(),
      MapSet.new(),
      4
    )
  end

  def announce_peer(pid, infohash, port) do
    # fetch list of contacts and one by one send the request
    table = KNode.get_routing_table(pid)
    tokens = KNode.get_tokens(pid)

    tokens
    |> Enum.map(fn {id, token} -> {RoutingTable.fetch_candidate(table, id), token} end)
    |> Enum.reject(fn {candidate, _token} -> is_nil(candidate) end)
    |> Task.async_stream(
      fn {c, token} -> KNode.announce_peer(pid, c, infohash, port, token) end,
      timeout: 2000,
      on_timeout: :kill_task
    )
    |> Enum.to_list()
  end

  # ------------------
  #  Helper functions
  # ------------------

  def new_node(),
    do: KNode.new()

  def get_contacts(pid),
    do: KNode.contacs(pid)

  @spec node_id(atom() | pid() | {atom(), any()} | {:via, atom(), any()}) :: any()
  def node_id(pid),
    do: KNode.get_node_id(pid)

  def routing_table(pid),
    do: KNode.get_routing_table(pid)

  # ----------------------------
  #     Lookup algorithms
  # ---------------------------

  def lookup(pid, target) do
    initial_nodes = closest_nodes(pid, target, @alpha)
    do_lookup(pid, target, initial_nodes, _queried = MapSet.new(), _best = [], _round = 8)
  end

  def do_lookup(_pid, _target, _to_query, _queried, best, 0), do: best

  def do_lookup(pid, target, to_query, queried, best, rounds) do
    new_candidates =
      to_query
      |> Task.async_stream(
        fn n -> find_nodes(pid, n, target) end,
        timeout: 2000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, candidates} when is_list(candidates) -> candidates
        _ -> []
      end)

    queried = Enum.reduce(to_query, queried, fn n, acc -> MapSet.put(acc, n.id) end)

    best =
      (best ++ new_candidates)
      |> Enum.sort_by(fn c -> Utils.xor_distance(c.id, target) end)
      |> Enum.take(@k)

    next_to_query =
      best
      |> Enum.reject(fn c -> MapSet.member?(queried, c.id) end)
      |> Enum.take(@alpha)

    if Enum.empty?(next_to_query),
      do: best,
      else: do_lookup(pid, target, next_to_query, queried, best, rounds - 1)
  end

  def lookup_peers(_pid, _infohash, _to_query, _queried, peers, 0),
    do: peers

  def lookup_peers(pid, infohash, to_query, queried, peers, rounds) do
    # - get the contacts
    # - loop on them calling get_peers(p, c, i)
    responses =
      to_query
      |> Task.async_stream(
        fn c -> KNode.get_peers(pid, c, infohash) end,
        timeout: 2000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, result} -> [result]
        _ -> []
      end)

    queried = Enum.reduce(to_query, queried, fn c, acc -> MapSet.put(acc, c.id) end)

    # - for those that return :peers, store them in return value
    peers =
      Enum.reduce(responses, peers, fn
        {:peers, val}, acc -> MapSet.union(acc, MapSet.new(val))
        _, acc -> acc
      end)

    # - for those that return :nodes, store them in pending
    # - reject those already asked
    pending =
      Enum.reduce(responses, [], fn
        {:nodes, val}, acc -> acc ++ val
        _, acc -> acc
      end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.reject(&MapSet.member?(queried, &1.id))

    if MapSet.size(peers) > 4 or Enum.empty?(pending),
      do: peers,
      else: lookup_peers(pid, infohash, pending, queried, peers, rounds - 1)
  end

  # -------------------
  #  Private functions
  # -------------------

  defp closest_nodes(pid, target, alpha) do
    routing_table(pid).kbuckets
    |> Map.values()
    |> List.flatten()
    |> Enum.sort_by(fn c -> Utils.xor_distance(c.id, target) end)
    |> Enum.take(alpha)
  end
end
