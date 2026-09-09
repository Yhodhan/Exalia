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
end
