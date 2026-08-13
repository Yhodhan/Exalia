defmodule Exalia.KRPC do
  alias Bencoder.Encoder

  @id_size_bytes 20

  def ping(id, tid) do
    hex = generate_binary_id(id)

    q = %{"t" => tid, "y" => "q", "q" => "ping", "a" => %{"id" => hex}}
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
