defmodule Bencoder.Decoder do
  @moduledoc """
  Documentation for `Decoder`.
  """
  def decode(bencode) do
    {:ok, data, _} = decode_bencode(bencode)
    {:ok, data}
  end

  def decode_bencode(bencode) when is_list(bencode) do
    bencode
    |> :binary.list_to_bin()
    |> decode_bencode()
  end

  def decode_bencode(<<?d, dic::binary>>),
    do: decode_dictionary(dic)

  def decode_bencode(<<?l, list::binary>>),
    do: decode_list(list)

  def decode_bencode(<<?i, int::binary>>),
    do: decode_integer(int)

  def decode_bencode(<<str::binary>>),
    do: decode_string(str)

  # ----------------------
  #       Dictionary
  # ----------------------
  def decode_dictionary(bencode, map \\ %{})

  def decode_dictionary(<<?e, rest::binary>>, map),
    do: {:ok, map, rest}

  def decode_dictionary(bencode, map) do
    {:ok, key, rest} = decode_bencode(bencode)
    {:ok, value, rest} = decode_bencode(rest)

    decode_dictionary(rest, Map.put(map, key, value))
  end

  # ----------------------
  #        List
  # ----------------------
  def decode_list(bencode, list \\ [])

  def decode_list(<<?e, rest::binary>>, list),
    do: {:ok, list, rest}

  def decode_list(bencode, list) do
    {:ok, result, rem} = decode_bencode(bencode)
    list = list ++ [result]
    decode_list(rem, list)
  end

  # ----------------------
  #        Integer
  # ----------------------
  def decode_integer(bencode) do
    {digits, <<rest::binary>>} = split_until(bencode, ?e)
    num = String.to_integer(digits)

    {:ok, num, rest}
  end

  # ----------------------
  #        String
  # ----------------------
  def decode_string(bencode) do
    {len_str, <<str::binary>>} = split_until(bencode, ?:)
    len = String.to_integer(len_str)

    <<string::binary-size(^len), rest::binary>> = str
    {:ok, string, rest}
  end

  # ----------------------
  #   Private functions
  # ----------------------
  defp split_until(bencode, char) do
    case :binary.split(bencode, <<char>>) do
      [head, tail] -> {head, tail}
    end
  end
end
