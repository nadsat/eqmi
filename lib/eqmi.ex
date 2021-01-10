defmodule Eqmi do
  @moduledoc """
  Documentation for `Eqmi`.
  """
  @sender_types %{0 => :control_point, 128 => :service}
  @service_types %{
    0 => :qmi_ctl,
    1 => :qmi_wds,
    2 => :qmi_dms,
    3 => :qmi_nas,
    4 => :qmi_qos,
    5 => :qmi_wms,
    6 => :qmi_pds,
    9 => :qmi_voice,
    10 => :qmi_cat,
    11 => :qmi_cat,
    12 => :qmi_pbm,
    14 => :qmi_cat
  }
  @message_types %{0 => :request, 1 => :response, 2 => :indication}

  common_base =
    File.read!("priv/qmi-common.json")
    |> Jason.decode!()

  svc_data =
    File.stream!("priv/qmi-service-ctl.json")
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
    |> Eqmi.Builder.replace_common(common_defs)

  tx_bits = if module["name"] == "CTL", do: 1, else: 2

  # @ctl_msgs ctl_msgs
  defmodule Module.concat(Eqmi, module["name"]) do
    @ctl_msgs ctl_msgs
    @decoder_generator [
      {"decode_request_tlv", "input"},
      {"decode_response_tlv", "output"},
      {"decode_indication_tlv", "indication"}
    ]

    require Eqmi.Builder

    def process_qmux_sdu(msg, payload) do
      <<m_type::binary-size(1), tx_id::binary-size(unquote(tx_bits)), rest::binary>> = msg

      IO.inspect(rest)
      msg_type = m_type |> :binary.decode_unsigned(:little) |> Eqmi.get_message_type()
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

    def request(:allocate_cid, params) do
      {len, content} =
        [
          %{
            "format" => "guint8",
            "id" => "0x01",
            "name" => :service,
            "public-format" => "QmiService",
            "since" => "1.0",
            "type" => "TLV"
          }
        ]
        |> Enum.map(fn x ->
          x
          |> Eqmi.Tlv.encode_tlv(params)
        end)
        |> Enum.reverse()
        |> Enum.reduce({0, []}, fn {l, b}, {size, list} ->
          {l + size, [b | list]}
        end)

      # TODO agregar msg_id
      msg_id = <<34::little-unsigned-integer-size(16)>>

      [msg_id, <<len::little-unsigned-integer-size(16)>>, content]
      |> :erlang.list_to_binary()
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
      IO.puts("proc ctl done")
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

    for command <- @ctl_msgs do
      msg_id =
        command["id"]
        |> Eqmi.Builder.id_from_str()

      for {fun, direction} <- @decoder_generator do
        elements =
          Map.get(command, direction, [])
          |> Eqmi.Builder.transform_name()

        for params <- elements do
          param_id =
            params["id"]
            |> Eqmi.Builder.id_from_str()

          defp unquote(:"#{fun}")(
                 unquote(msg_id),
                 <<unquote(param_id)::unsigned-integer-size(8)>>,
                 msg
               ) do
            if false do
              msg
            else
              Eqmi.Builder.create_decoder(unquote(params), unquote(param_id))
            end
          end
        end
      end
    end

    defp decode_request_tlv(_, _, _) do
      %{}
    end

    defp decode_response_tlv(_, _, _) do
      %{}
    end

    defp decode_indication_tlv(_, _, _) do
      %{}
    end
  end

  def open_device(dev) do
    options = [:read, :write, :raw]
    File.open(dev, options)
  end

  def close_device(dev) do
    File.close(dev)
  end

  def get_sender_type(type_id) do
    @sender_types[type_id]
  end

  def get_service_type(svc_id) do
    @service_types[svc_id]
  end

  def get_message_type(msg_id) do
    @message_types[msg_id]
  end

  def hello(device) do
    # for command <- @ctl_msgs do
    #  IO.puts("ddddddddddddddddddddd")
    #  IO.inspect(command)
    #  IO.puts("ddddddddddddddddddddd")

    #  msg_id =
    #    command["id"]
    #    |> Eqmi.Builder.id_from_str()

    #  IO.inspect(msg_id)

    #  IO.inspect(command["id"])
    #  IO.inspect(command["type"])

    #  elements =
    #    Map.get(command, "output", %{})
    #    |> Enum.filter(fn x -> !Map.has_key?(x, "common-ref") end)
    #    |> Eqmi.Builder.transform_name()

    #  for out_params <- elements do
    #    IO.puts("TTTTTTTTTTTTTTTTTTTTTTTTTTTT")
    #    IO.inspect(out_params)
    #    IO.puts("----------------------------")
    #    IO.inspect(out_params["format"])
    #    IO.puts("----------------------------")
    #  end
    # end

    IO.puts("+++++++++++++++++")
    msg = IO.binread(device, 3)
    IO.puts("+++++++++++++++++")
    msg = process_message(msg, device)
    IO.inspect(msg)
    :pasturri
  end

  defp process_message({:error, reason}, _) do
    {:error, reason}
  end

  defp process_message(:eof, _) do
    {:error, :eof}
  end

  defp process_message(qmux, dev) do
    <<_version, content::binary>> = qmux
    IO.inspect(qmux)
    len = :binary.decode_unsigned(content, :little)
    msg = IO.binread(dev, len - 2)
    <<header::binary-size(3), rest::binary>> = msg
    payload = Eqmi.QmuxHeader.parse(header)
    process_service(payload, rest)
  end

  defp process_service(%{service_type: :qmi_ctl} = payload, messages) do
    IO.puts("sender_type [#{inspect(payload.sender_type)}]")
    IO.puts("client_id [#{inspect(payload.client_id)}]")
    Eqmi.CTL.process_qmux_sdu(messages, payload)
  end
end
