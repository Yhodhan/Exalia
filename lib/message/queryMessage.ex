defmodule Message.QueryMessage do
  alias Exalia.KRPC
  alias Exalia.RoutingTable
  alias Exalia.Candidate
  alias Exalia.Utils

  require Logger

  def ping(state, query, {ip, port}) do
    Logger.info("=== Ping query received ===")
    tid = query["t"]
    own_id = state.id

    {:ok, msg} = KRPC.ping_query(tid, own_id)
    :gen_udp.send(state.socket, ip, port, msg)

    # store contact
    %{"id" => id} = query["a"]
    id = :binary.decode_unsigned(id)
    candidate = Candidate.new(id, ip, port)
    table = RoutingTable.insert(state.routing_table, candidate)
    %{state | routing_table: table}
  end

  def find_node(state, query, {ip, port}) do
    Logger.info("=== find node query received ===")
    tid = query["t"]
    own_id = state.id

    # check if knows it
    target_id = Utils.conversion(query["a"]["target"])

    {:ok, msg} =
      if RoutingTable.has_candidate?(state.table, target_id) do
        candidate =
          state.table
          |> RoutingTable.fetch_candidate(target_id)
          |> encode_candidate()

        KRPC.find_node_query(tid, own_id, candidate)
      else
        nodes =
          state
          |> get_closest_candidates(target_id)
          |> encode_candidates()

        KRPC.find_node_query(tid, own_id, nodes)
      end

    :gen_udp.send(state.socket, ip, port, msg)
    state
  end

  # -------------------
  #  Private functions
  # -------------------
  defp get_closest_candidates(state, target_id),
    do: RoutingTable.get_closest_candidates(state.table, target_id)

  # TODO: function to encode the candidates

  defp encode_candidates([]), do: <<>>

  defp encode_candidates([candidate | rest]) do
    encode_candidate(candidate) <> encode_candidates(rest)
  end

  defp encode_candidate(%Candidate{ip: ip, port: port} = _c) do
    {a, b, c, d} = ip
    <<a, b, c, d, port::binary>>
  end
end
