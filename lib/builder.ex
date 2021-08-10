defmodule Eqmi.Builder do
  alias Eqmi.Types

  common_base =
    File.read!("priv/qmi-common.json")
    |> Jason.decode!()

  {:ok, flist} = File.ls("priv")

  svc_list =
    flist
    |> Enum.filter(fn x -> String.contains?(x, "service") end)
    |> Enum.map(fn x -> Path.join("priv", x) end)

  for svc_file_name <- svc_list do
    svc_data =
      File.stream!(svc_file_name)
      |> Stream.filter(fn line -> !(line |> String.trim() |> String.starts_with?("//")) end)
      |> Enum.join()
      |> Jason.decode!()

    [module | ctl] = svc_data

    common_defs =
      ctl
      |> Enum.drop(3)
      |> Enum.filter(fn x -> Map.has_key?(x, "common-ref") end)
      |> Enum.concat(common_base)
      |> Enum.reduce(%{}, fn x, acc ->
        Map.put(acc, x["common-ref"], Map.delete(x, "common-ref"))
      end)

    indications =
      ctl
      |> Enum.drop(3)
      |> Enum.filter(fn e -> e["type"] == "Indication" end)
      |> update_in(
        [Access.all()],
        &with(
          {v, m} <- Map.pop(&1, "output"),
          do:
            if v != nil do
              Map.put(m, "indication", v)
            else
              m
            end
        )
      )

    ctl_msgs =
      ctl
      |> Enum.drop(3)
      |> Enum.filter(fn e -> e["type"] == "Message" end)
      |> Enum.concat(indications)
      |> Eqmi.Builder.Utils.replace_common(common_defs)

    tx_bits = if module["name"] == "CTL", do: 1, else: 2
    type_shift = if module["name"] == "CTL", do: 1, else: 0

    decoder_generator = [
      {"decode_request_tlv", "input"},
      {"decode_response_tlv", "output"},
      {"decode_indication_tlv", "indication"}
    ]

    encoder_generator = [
      {"request", "input"},
      {"response", "output"}
    ]

    defmodule Module.concat(Eqmi, module["name"]) do
      require Eqmi.Builder.Decoder
      require Eqmi.Builder.Encoder

      def process_qmux_sdu(msg, payload) do
        <<m_type::binary-size(1), tx_id::binary-size(unquote(tx_bits)), rest::binary>> = msg

        msg_type =
          m_type
          |> :binary.decode_unsigned(:little)
          |> Bitwise.<<<(unquote(type_shift))
          |> Types.get_message_atom()

        decode_func = get_decode_func(msg_type)
        messages = process_messages(rest, decode_func, [])

        payload
        |> Map.put(
          :message_type,
          msg_type
        )
        |> Map.put(:tx_id, tx_id |> :binary.decode_unsigned(:little))
        |> Map.put(:messages, messages)
      end

      def qmux_sdu(msg_type, transaction_id, messages) do
        msg_id = Eqmi.message_type_id(msg_type)

        ctrl_flag = <<msg_id::unsigned-integer-size(8)>>
        tx_bits_number = unquote(tx_bits) * 8
        tx_id = <<transaction_id::little-unsigned-integer-size(tx_bits_number)>>

        [ctrl_flag, tx_id, messages]
        |> :erlang.list_to_binary()
      end

      def encode_tlv_raw(type, v) do
        t = <<type::unsigned-integer-size(16)>>
        val_len = byte_size(v)
        l = <<val_len::unsigned-integer-size(16)>>

        [t, l, v]
        |> :binary.list_to_bin()
      end

      defp process_messages(<<>>, _, msgs) do
        msgs
      end

      defp process_messages(content, decode_func, msgs) do
        <<m::little-binary-size(2), l::little-binary-size(2), rest::binary>> = content
        len = :binary.decode_unsigned(l, :little)
        msg_id = :binary.decode_unsigned(m, :little)
        <<tlv_bin::binary-size(len), rem_msgs::binary>> = rest
        params = proc_ctl_tlv(tlv_bin, msg_id, decode_func, [])
        message = %{msg_id: msg_id, parameters: params}
        new_msgs = [message | msgs]
        process_messages(rem_msgs, decode_func, new_msgs)
      end

      def proc_ctl_tlv(<<>>, _, _, params) do
        params
      end

      def proc_ctl_tlv(content, msg_id, decode_func, params) do
        <<id::binary-size(1), l::binary-size(2), buffer::binary>> = content

        tlv_len = :binary.decode_unsigned(l, :little)
        <<tlv_content::binary-size(tlv_len), rest::binary>> = buffer
        p = decode_func.(msg_id, id, tlv_content)
        proc_ctl_tlv(rest, msg_id, decode_func, [p | params])
      end

      defp get_decode_func(:response) do
        &decode_response_tlv/3
      end

      defp get_decode_func(:request) do
        &decode_request_tlv/3
      end

      defp get_decode_func(:indication) do
        &decode_indication_tlv/3
      end

      for command <- ctl_msgs do
        msg_id =
          command["id"]
          |> Eqmi.Builder.Utils.id_from_str()

        for {fun, direction} <- decoder_generator do
          elements =
            Map.get(command, direction, [])
            |> Eqmi.Builder.Utils.transform_name()

          for params <- elements do
            param_id =
              params["id"]
              |> Eqmi.Builder.Utils.id_from_str()

            defp unquote(:"#{fun}")(
                   unquote(msg_id),
                   <<unquote(param_id)::unsigned-integer-size(8)>>,
                   msg
                 ) do
              if false do
                msg
              else
                Eqmi.Builder.Decoder.create(unquote(params), unquote(param_id))
              end
            end
          end
        end

        if command["type"] == "Indication" do
          elements =
            Map.get(command, "indication", [])
            |> Eqmi.Builder.Utils.transform_name()

          msg_name = Eqmi.Builder.Utils.name_to_atom(command["name"])

          def indication(
                unquote(msg_name),
                params
              ) do
            if false do
              params
            else
              Eqmi.Builder.Encoder.create(unquote(elements), unquote(msg_id))
            end
          end
        else
          for {fun, direction} <- encoder_generator do
            elements =
              Map.get(command, direction, [])
              |> Eqmi.Builder.Utils.transform_name()

            msg_name = Eqmi.Builder.Utils.name_to_atom(command["name"])

            def unquote(:"#{fun}")(
                  unquote(msg_name),
                  params
                ) do
              if false do
                params
              else
                Eqmi.Builder.Encoder.create(unquote(elements), unquote(msg_id))
              end
            end
          end
        end
      end

      defp decode_request_tlv(_, id, value) do
        decode_unknown_tlv(id, value)
      end

      defp decode_response_tlv(_, id, value) do
        decode_unknown_tlv(id, value)
      end

      defp decode_indication_tlv(_, id, value) do
        decode_unknown_tlv(id, value)
      end

      defp decode_unknown_tlv(id, value) do
        %{:value => value, :param_id => id}
      end
    end
  end
end
