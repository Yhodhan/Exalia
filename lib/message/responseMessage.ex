defmodule Message.ResponseMessage do
  alias Exalia.RoutingTable
  alias Exalia.Candidate

  require Logger
  # ----------------------------------------------------
  #                       PING
  # ----------------------------------------------------

  def handle_ping(state, response, {ip, port}) do
    Logger.info("=== Ping received ===")
    %{"id" => id} = response["r"]
    # store the node in the routing table
    id = :binary.decode_unsigned(id)
    candidate = Candidate.new(id, ip, port)
    table = RoutingTable.insert(state.routing_table, candidate)

    {:pong, %{state | routing_table: table}}
  end

  # ----------------------------------------------------
  #                     FIND NODE
  # ----------------------------------------------------

  def handle_find_node(state, response) do
    Logger.info("=== Find Nodes received ===")
    %{"id" => _id, "nodes" => nodes} = response["r"]

    {decoded_nodes, table} = fill_routing_table(state, nodes)

    {decoded_nodes, %{state | routing_table: table}}
  end

  # ----------------------------------------------------
  #                     GET PEERS
  # ----------------------------------------------------

  def handle_get_peers(state, response) do
    case response["r"] do
      %{"id" => id, "token" => token, "nodes" => nodes} ->
        Logger.info("=== Get Peers Received: Nodes ===")
        id = :binary.decode_unsigned(id)
        tokens = Map.put(state.tokens, id, token)

        {decoded_nodes, table} = fill_routing_table(state, nodes)

        {{:nodes, decoded_nodes}, %{state | routing_table: table, tokens: tokens}}

      %{"id" => id, "token" => token, "values" => values} ->
        Logger.info("=== Get Peers Received: Peers ===")
        id = :binary.decode_unsigned(id)
        tokens = Map.put(state.tokens, id, token)

        peers = Enum.map(values, fn v -> decode_peer(v) end)

        {{:peers, peers}, %{state | tokens: tokens}}

      _ ->
        Logger.warning("Unexpected get_peers response shape: #{inspect(response)}")
        {{:error, :unexpected_response}, state}
    end
  end

  # ----------------------------------------------------
  #                    ANNOUNCE PEERS
  # ----------------------------------------------------

  def handle_announce_peer(state, _response) do
    # nothing to store — just acknowledge success to the caller
    {:announced, state}
  end

  def fill_routing_table(state, nodes) do
    decoded_nodes =
      parse_nodes(nodes)
      |> Enum.uniq_by(& &1.id)

    {decoded_nodes,
     decoded_nodes
     |> Enum.reject(&(&1.id == state.id))
     |> Enum.reduce(state.routing_table, fn n, table ->
       RoutingTable.insert(table, n)
     end)}
  end

  # ----------------------------------------------------
  #                   PRIVATE FUNCTIONS
  # ----------------------------------------------------

  defp parse_nodes(bytes) do
    case bytes do
      <<>> ->
        []

      <<id::binary-size(20), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, a, b, c, d,
        port::binary-size(2), rest::binary>> ->
        build_candidate(id, {a, b, c, d}, port) ++ parse_nodes(rest)

      <<id::binary-size(20), a, b, c, d, port::binary-size(2), rest::binary>> ->
        build_candidate(id, {a, b, c, d}, port) ++ parse_nodes(rest)

      leftover ->
        Logger.warning(
          "=== Unparseable trailing node bytes (#{byte_size(leftover)} bytes), dropping ==="
        )

        []
    end
  end

  defp build_candidate(id, ip, port) do
    id = :binary.decode_unsigned(id)
    port = :binary.decode_unsigned(port)
    candidate = Candidate.new(id, ip, port)
    [candidate]
  end

  defp decode_peer(<<a, b, c, d, port::16>>),
    do: {{a, b, c, d}, port}
end
