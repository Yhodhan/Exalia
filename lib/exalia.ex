defmodule Exalia do

  @moduledoc """
  Documentation for `Exalia`.
  """

  @id_size_bytes 20 

  def generate_id() do
    :crypto.strong_rand_bytes(@id_size_bytes)
    |> :binary.decode_unsigned()
  end

end
