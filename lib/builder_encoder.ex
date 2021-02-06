defmodule Eqmi.Builder.Encoder do
  defmacro create(payload, msg_id) do
    quote do
      {len, content} =
        unquote(Macro.escape(payload))
        |> Enum.filter(fn x -> Keyword.has_key?(var!(params), x["name"]) end)
        |> Enum.map(fn x ->
          x
          |> Eqmi.Tlv.encode_tlv(var!(params))
        end)
        |> Enum.reduce({0, []}, fn {l, b}, {size, list} ->
          {l + size, [b | list]}
        end)

      id = <<unquote(msg_id)::little-unsigned-integer-size(16)>>

      [id, <<len::little-unsigned-integer-size(16)>>, content]
      |> :erlang.list_to_binary()
    end
  end
end
