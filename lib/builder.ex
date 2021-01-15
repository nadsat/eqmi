defmodule Eqmi.Builder do
  defmacro create_decoder(payload, param_id) do
    quote do
      {res, _} =
        unquote(Macro.escape(payload))
        |> Eqmi.Tlv.decode_tlv(var!(msg))

      %{unquote(payload["name"]) => res, :param_id => unquote(param_id)}
    end
  end

  defmacro create_encoder(payload, msg_id) do
    quote do
      {len, content} =
        unquote(Macro.escape(payload))
        |> Enum.map(fn x ->
          x
          |> Eqmi.Tlv.encode_tlv(var!(params))
        end)
        |> Enum.reverse()
        |> Enum.reduce({0, []}, fn {l, b}, {size, list} ->
          {l + size, [b | list]}
        end)

      id = <<unquote(msg_id)::little-unsigned-integer-size(16)>>

      [id, <<len::little-unsigned-integer-size(16)>>, content]
      |> :erlang.list_to_binary()
    end
  end

  def id_from_str(str_id) do
    str_id
    |> String.split("x")
    |> Enum.drop(1)
    |> hd
    |> Base.decode16!()
    |> :binary.decode_unsigned()
  end

  def replace_common(elements, common_def) do
    elements
    |> Enum.map(fn x ->
      if Map.has_key?(x, "input") do
        %{x | "input" => replace_list(x["input"], common_def)}
      else
        x
      end
    end)
    |> Enum.map(fn x ->
      if Map.has_key?(x, "output") do
        %{x | "output" => replace_list(x["output"], common_def)}
      else
        x
      end
    end)
    |> Enum.map(fn x ->
      if Map.has_key?(x, "indication") do
        %{x | "indication" => replace_list(x["indication"], common_def)}
      else
        x
      end
    end)
  end

  defp replace_list(content, common_def) do
    content
    |> Enum.map(fn x -> Map.get(common_def, x["common-ref"], x) end)
  end

  def transform_name(content) do
    transform_name_list(content, [])
  end

  defp transform_name_list([], acc) do
    acc
    |> Enum.reverse()
  end

  defp transform_name_list([h | t], acc) do
    new_obj = rename_obj(h)
    transform_name_list(t, [new_obj | acc])
  end

  defp rename_obj(%{"format" => "sequence"} = obj) do
    name = name_to_atom(obj["name"])
    %{obj | "name" => name, "contents" => transform_name_list(obj["contents"], [])}
  end

  defp rename_obj(%{"format" => "struct"} = obj) do
    name = name_to_atom(obj["name"])

    %{obj | "name" => name, "contents" => transform_name_list(obj["contents"], [])}
  end

  defp rename_obj(%{"format" => "array"} = obj) do
    name = name_to_atom(obj["name"])

    %{obj | "name" => name, "array-element" => rename_obj(obj["array-element"])}
  end

  defp rename_obj(obj) do
    name = name_to_atom(obj["name"])

    %{obj | "name" => name}
  end

  def name_to_atom(name) do
    name |> String.replace(" ", "_") |> String.downcase() |> String.to_atom()
  end
end
