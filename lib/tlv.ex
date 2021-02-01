defmodule Eqmi.Tlv do
  def decode_tlv(%{"format" => "guint8"}, data) do
    <<val::unsigned-integer-size(8), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "guint16"}, data) do
    <<val::unsigned-integer-size(16), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "guint32"}, data) do
    <<val::unsigned-integer-size(32), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "guint64"}, data) do
    <<val::unsigned-integer-size(64), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "gfloat"}, data) do
    <<val::float-size(32), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "gdouble"}, data) do
    <<val::float-size(64), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "gint8"}, data) do
    <<val::integer-size(8), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "gint16"}, data) do
    <<val::integer-size(16), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "gint32"}, data) do
    <<val::integer-size(32), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "guint-sized"} = obj, data) do
    s =
      obj["guint-size"]
      |> String.to_integer()

    bit_number = s * 8

    <<val::unsigned-integer-size(bit_number), rest::binary>> = data
    {val, rest}
  end

  def decode_tlv(%{"format" => "sequence"} = obj, data) do
    obj["contents"]
    |> Enum.reduce(
      {%{}, data},
      fn x, {params, bin} ->
        {v, rest} = Eqmi.Tlv.decode_tlv(x, bin)
        {Map.put(params, x["name"], v), rest}
      end
    )
  end

  def decode_tlv(%{"format" => "string"} = obj, data) do
    prefix_size = Map.get(obj, "size-prefix-format", "guint8")
    {len, payload} = decode_tlv(%{"format" => prefix_size}, data)

    <<val::binary-size(len), rest::binary>> = payload
    {val, rest}
  end

  def decode_tlv(%{"format" => "struct"} = obj, data) do
    obj["contents"]
    |> Enum.reduce(
      {%{}, data},
      fn x, {params, bin} ->
        {v, rest} = Eqmi.Tlv.decode_tlv(x, bin)
        {Map.put(params, x["name"], v), rest}
      end
    )
  end

  def decode_tlv(%{"format" => "array"} = obj, data) do
    prefix_size = Map.get(obj, "size-prefix-format", "guint8")
    {len, payload} = decode_tlv(%{"format" => prefix_size}, data)

    elements_number = Map.get(obj, "fixed-size", Integer.to_string(len)) |> String.to_integer()
    build_array(elements_number, payload, obj["array-element"], [])
  end

  def encode_tlv(obj, data) do
    type = encode_type(obj["id"])

    val =
      data
      |> Keyword.get(obj["name"])

    {len, content} = encode_value(obj, val)
    l = <<len::little-unsigned-integer-size(16)>>

    msg =
      [type, l, content]
      |> :erlang.list_to_binary()

    {3 + len, msg}
  end

  defp encode_value(%{"format" => "guint8"}, data) do
    encode_unsigned(8, data)
  end

  defp encode_value(%{"format" => "guint16"}, data) do
    encode_unsigned(16, data)
  end

  defp encode_value(%{"format" => "guint32"}, data) do
    encode_unsigned(32, data)
  end

  defp encode_value(%{"format" => "guint64"}, data) do
    encode_unsigned(64, data)
  end

  defp encode_value(%{"format" => "gint8"}, data) do
    encode_int(8, data)
  end

  defp encode_value(%{"format" => "gint16"}, data) do
    encode_int(16, data)
  end

  defp encode_value(%{"format" => "gint32"}, data) do
    encode_int(32, data)
  end

  defp encode_value(%{"format" => "gfloat"}, data) do
    encode_float(32, data)
  end

  defp encode_value(%{"format" => "gdouble"}, data) do
    encode_float(64, data)
  end

  defp encode_value(%{"format" => "guint-sized"} = obj, val) do
    len =
      obj["guint-size"]
      |> String.to_integer()

    bit_number = len * 8

    content = <<val::unsigned-integer-size(bit_number)>>
    {len, content}
  end

  defp encode_value(%{"format" => "string"}, data) do
    val =
      data
      |> to_charlist()

    len = length(val)

    content = :binary.list_to_bin(val)

    {len, content}
  end

  defp encode_value(%{"format" => "array"} = obj, data) do
    prefix_size = Map.get(obj, "size-prefix-format", "guint8")
    array_size = length(data)
    {l, c} = encode_value(%{"format" => prefix_size}, array_size)
    len = l + array_size

    payload =
      data
      |> Enum.map(fn x -> encode_value(obj["array-element"], x) end)

    content =
      [c | payload]
      |> :binary.list_to_bin()

    {len, content}
  end

  defp encode_value(%{"format" => "sequence"} = obj, data) do
    {len, content_list} =
      obj["contents"]
      |> Enum.map(fn x ->
        payload = Keyword.get(data, obj["name"])
        encode_value(x, payload)
      end)
      |> Enum.reduce(
        {0, []},
        fn {l, b}, {acc_len, bin_list} ->
          {l + acc_len, [b | bin_list]}
        end
      )

    content =
      content_list
      |> Enum.reverse()
      |> :binary.list_to_bin()

    {len, content}
  end

  defp encode_unsigned(uint_size, val) do
    content = <<val::unsigned-integer-size(uint_size)>>

    len = div(uint_size, 8)
    {len, content}
  end

  defp encode_int(uint_size, val) do
    len = div(uint_size, 8)

    content = <<val::integer-size(uint_size)>>

    {len, content}
  end

  defp encode_float(uint_size, val) do
    len = div(uint_size, 8)

    content = <<val::float-size(uint_size)>>

    {len, content}
  end

  defp encode_type(id) do
    id
    |> Eqmi.Builder.id_from_str()
  end

  defp build_array(0, rest, _, acc) do
    {Enum.reverse(acc), rest}
  end

  defp build_array(n, payload, obj, acc) do
    {element, rest} = decode_tlv(obj, payload)
    build_array(n - 1, rest, obj, [element | acc])
  end
end
