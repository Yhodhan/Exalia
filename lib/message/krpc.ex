defmodule Exalia.KRPC do
  alias Bencoder.Encoder

  @id_size_bytes 20

  # -------------------------------
  #            Responses
  # -------------------------------

  def ping(tid, id) do
    id = generate_binary_id(id)

    q = %{"t" => tid, "y" => "q", "q" => "ping", "a" => %{"id" => id}}
    Encoder.encode(q)
  end

  def find_node(tid, id, target) do
    id = generate_binary_id(id)
    t = generate_binary_id(target)

    q = %{"t" => tid, "y" => "q", "q" => "find_node", "a" => %{"id" => id, "target" => t}}
    Encoder.encode(q)
  end

  def get_peers(tid, id, infohash) do
    id = generate_binary_id(id)

    q = %{
      "t" => tid,
      "y" => "q",
      "q" => "get_peers",
      "a" => %{"id" => id, "info_hash" => infohash}
    }

    Encoder.encode(q)
  end

  def announce_peer(tid, id, infohash, port, token),
    do: announce_peer(tid, id, infohash, port, token, _implied_port = 0)

  def announce_peer(tid, id, infohash, port, token, implied_port) do
    id = generate_binary_id(id)

    q = %{
      "t" => tid,
      "y" => "q",
      "q" => "announce_peer",
      "a" => %{
        "id" => id,
        "implied_port" => implied_port,
        "info_hash" => infohash,
        "port" => port,
        "token" => token
      }
    }

    Encoder.encode(q)
  end

  # -------------------------------
  #            Responses
  # -------------------------------
  def ping_query(tid, id) do
    id = generate_binary_id(id)

    q = %{"t" => tid, "y" => "r", "r" => %{"id" => id}}
    Encoder.encode(q)
  end

  def find_node_query(tid, id, value) do
    id = generate_binary_id(id)

    q = %{"t" => tid, "y" => "r", "r" => %{"id" => id, "nodes" => value}}

    Encoder.encode(q)
  end

  # ------------------
  # Private functions
  # ------------------

  defp generate_binary_id(id) do
    hex = :binary.encode_unsigned(id)
    pad = @id_size_bytes - byte_size(hex)
    if pad > 0, do: <<0::size(pad), hex::binary>>, else: hex
  end
end
