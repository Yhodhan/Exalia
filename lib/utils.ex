defmodule Exalia.Utils do
  import Bitwise

  def conversion(value) when is_binary(value),
    do: :binary.decode_unsigned(value)

  def conversion(value), do: value

  def xor_distance(a, b) do
    a = conversion(a)
    b = conversion(b)

    bxor(a, b)
  end

  def generate_token(ip, secret) do
    ip_bin = ip |> Tuple.to_list() |> :erlang.list_to_binary()
    :crypto.hash(:sha, ip_bin <> secret)
  end

  def random_id_bucket(id, index) do
    flip_bit = 1 <<< index

    # random bits below `index`, to randomize within the bucket's range
    random_low_bits = :rand.uniform(1 <<< index) - 1

    id
    |> bxor(flip_bit)
    # clear the low bits inherited from own_id
    |> then(&(&1 &&& bnot((1 <<< index) - 1)))
    |> bor(random_low_bits)
  end
end
