defmodule Exalia.Utils do
  def conversion(value) when is_binary(value),
    do: :binary.decode_unsigned(value)

  def conversion(value), do: value
end
