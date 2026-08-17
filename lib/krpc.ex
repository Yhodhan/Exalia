defmodule Exalia.KRPC do
  alias Bencoder.Encoder

  @id_size_bytes 20

  def ping(tid, id) do
    id = generate_binary_id(id)

    q = %{"t" => tid, "y" => "q", "q" => "ping", "a" => %{"id" => id}}
    Encoder.encode(q)
  end

  def find_node(tid, query_id, target) do
    hex = generate_binary_id(query_id)
    hex_t = generate_binary_id(target)

    q = %{"t" => tid, "y" => "q", "q" => "find_node", "a" => %{"id" => hex, "target" => hex_t}}
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
