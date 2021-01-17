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

    <<val::unsigned-integer-size(s), rest::binary>> = data
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

  def encode_tlv(%{"format" => "guint8"} = obj, data) do
    v =
      data
      |> Keyword.get(obj["name"])

    if v != nil do
      len = <<1::little-unsigned-integer-size(16)>>

      type =
        obj["id"]
        |> Eqmi.Builder.id_from_str()

      content = <<v::unsigned-integer-size(8)>>

      msg =
        [<<type::little-unsigned-integer-size(8)>>, len, content]
        |> :erlang.list_to_binary()

      {4, msg}
    else
      {:error, not_found_err(obj["name"])}
    end
  end

  def encode_tlv(%{"format" => "guint16"} = obj, data) do
    v =
      data
      |> Keyword.get(obj["name"])

    if v != nil do
      len = <<2::little-unsigned-integer-size(16)>>

      type =
        obj["id"]
        |> Eqmi.Builder.id_from_str()

      content = <<v::unsigned-integer-size(16)>>

      msg =
        [<<type::little-unsigned-integer-size(8)>>, len, content]
        |> :erlang.list_to_binary()

      {5, msg}
    else
      {:error, not_found_err(obj["name"])}
    end
  end

  def encode_tlv(%{"format" => "guint32"} = obj, data) do
    v =
      data
      |> Keyword.get(obj["name"])

    if v != nil do
      {4, <<v::unsigned-integer-size(32)>>}
    else
      {:error, not_found_err(obj["name"])}
    end
  end

  defp build_array(0, rest, _, acc) do
    {Enum.reverse(acc), rest}
  end

  defp build_array(n, payload, obj, acc) do
    {element, rest} = decode_tlv(obj, payload)
    build_array(n - 1, rest, obj, [element | acc])
  end

  defp not_found_err(atom) do
    "param " <> Atom.to_string(atom) <> "not found"
  end
end
