defmodule Exalia do
  import Bitwise

  @moduledoc """
  Documentation for `Exalia`.
  """

  @doc """
    Calculates the xor distance between two IDs
  """

  def xor_distance(a, b) do
    a = convertion(a)
    b = convertion(b)

    bxor(a, b)
  end

  # ------------------
  # Private functions
  # ------------------

  defp convertion(value) when is_binary(value),
    do: :binary.decode_unsigned(value)

  defp convertion(value), do: value
end
