defmodule Message.QueryMessage do
  alias Exalia.KRPC
  alias Exalia.RoutingTable
  alias Exalia.Candidate

  require Logger

  def response_ping(state, query, {ip, port}) do
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
    {:ping, %{state | routing_table: table}}
  end
end
