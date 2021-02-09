defmodule Eqmi.Builder.Decoder do
  defmacro create(payload, param_id) do
    quote do
      {res, _} =
        unquote(Macro.escape(payload))
        |> Eqmi.Tlv.decode_tlv(var!(msg))

      %{unquote(payload["name"]) => res, :param_id => unquote(param_id)}
    end
  end
end
