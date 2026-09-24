defmodule Message.QueryMessage do
  alias Exalia.KRPC
  alias Exalia.RoutingTable
  alias Exalia.Candidate
  alias Exalia.Utils
  alias Exalia.Storage

  def ping(state, query, {ip, port}) do
    tid = query["t"]
    own_id = state.id

    {:ok, msg} = KRPC.ping_response(tid, own_id)
    :gen_udp.send(state.socket, ip, port, msg)

    # store contact
    %{"id" => id} = query["a"]
    id = :binary.decode_unsigned(id)
    candidate = Candidate.new(id, ip, port)
    table = RoutingTable.insert(state.routing_table, candidate)
    %{state | routing_table: table}
  end

  def find_node(state, query, {ip, port}) do
    tid = query["t"]
    own_id = state.id

    # check if knows it
    target_id = Utils.conversion(query["a"]["target"])

    {:ok, msg} =
      if RoutingTable.has_candidate?(state.routing_table, target_id) do
        candidate =
          state.routing_table
          |> RoutingTable.fetch_candidate(target_id)
          |> encode_candidate()

        KRPC.find_node_response(tid, own_id, candidate)
      else
        nodes =
          state
          |> get_closest_candidates(target_id)
          |> encode_candidates()

        KRPC.find_node_response(tid, own_id, nodes)
      end

    :gen_udp.send(state.socket, ip, port, msg)
    state
  end

  def get_peers(state, query, {ip, port}) do
    tid = query["t"]
    own_id = state.id

    querying_id = Utils.conversion(query["a"]["id"])
    info_hash = Utils.conversion(query["a"]["info_hash"])

    # check if the Node has downloaders
    {nodes, type} = get_nodes(state, info_hash)

    token = Utils.generate_token(ip, state.token_secret)
    {:ok, msg} = KRPC.get_peers_response(tid, own_id, nodes, token, type)

    :gen_udp.send(state.socket, ip, port, msg)

    candidate = Candidate.new(querying_id, ip, port)
    table = RoutingTable.insert(state.routing_table, candidate)
    %{state | routing_table: table}
  end

  def announce_peer(state, query, {ip, port}) do
    tid = query["t"]
    peer_port = get_port(query, port)

    %{"id" => raw_id, "info_hash" => raw_infohash, "token" => token} =
      query["a"]

    id = Utils.conversion(raw_id)
    info_hash = Utils.conversion(raw_infohash)

    if valid_token?(state, ip, token) do
      candidate = Candidate.new(id, ip, peer_port)
      Storage.store_node(info_hash, candidate)

      {:ok, msg} = KRPC.announce_peer_response(tid, state.id)
      # careful: reply to the querier's actual UDP source port, not their announced peer port
      :gen_udp.send(state.socket, ip, port, msg)

      candidate = Candidate.new(id, ip, peer_port)
      table = RoutingTable.insert(state.routing_table, candidate)
      %{state | routing_table: table}
    else
      {:ok, msg} = KRPC.error_response(tid, 203, "Bad token")
      :gen_udp.send(state.socket, ip, port, msg)
      state
    end
  end

  # -------------------
  #  Private functions
  # -------------------

  defp valid_token?(state, ip, token) do
    regen_token = Utils.generate_token(ip, state.token_secret)
    regen_old_token = Utils.generate_token(ip, state.old_token_secret)

    token == regen_token or token == regen_old_token
  end

  defp get_port(query, port) do
    case query["a"]["implied_port"] do
      1 -> port
      _ -> query["a"]["port"]
    end
  end

  defp get_nodes(state, info_hash) do
    if Storage.has_infohash?(info_hash) do
      peers =
        info_hash
        |> Storage.get_nodes()
        |> Enum.map(fn p -> encode_peer(p) end)

      {peers, :values}
    else
      nodes =
        state
        |> get_closest_candidates(info_hash)
        |> encode_candidates()

      {nodes, :nodes}
    end
  end

  defp get_closest_candidates(state, target_id),
    do: RoutingTable.get_closest_candidates(state.routing_table, target_id)

  defp encode_candidates([]),
    do: <<>>

  defp encode_candidates([candidate | rest]),
    do: encode_candidate(candidate) <> encode_candidates(rest)

  defp encode_candidate(%Candidate{id: id, ip: ip, port: port} = _c) do
    {a, b, c, d} = ip
    <<id::size(160)-big, a, b, c, d, port::size(16)-big>>
  end

  defp encode_peer(%Candidate{ip: ip, port: port} = _c) do
    {a, b, c, d} = ip
    <<a, b, c, d, port::size(16)-big>>
  end
end
