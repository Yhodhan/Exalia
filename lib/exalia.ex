defmodule Exalia do
  import Bitwise

  @moduledoc """
  Documentation for `Exalia`.
  """

  @id_size_bytes 20 
  @k_buckets_num 20

  def generate_id() do
    :crypto.strong_rand_bytes(@id_size_bytes)
    |> :binary.decode_unsigned()
  end

  def xor_distance(a, b) do
    a = conversion(a)
    b = conversion(b)

    bxor(a, b)
  end

  @doc """
  Obtains the first not 0 bit of the distance between two nodes
  """
  def bucket_index(distance) when distance > 0, do: bucket_index(distance, -1)
  def bucket_index(0, index), do: index

  def bucket_index(distance, index),
    do: bucket_index(distance >>> 1, index + 1)

  # ------------------
  # Private functions
  # ------------------

  defp conversion(value) when is_binary(value),
    do: :binary.decode_unsigned(value)

  defp conversion(value), do: value
end
