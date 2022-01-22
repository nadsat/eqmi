defmodule Eqmi.QmuxHeader do
  alias Eqmi.Types

  def parse(msg) do
    <<control_flag::integer-size(8), service_type::integer-size(8), client_id::integer-size(8)>> =
      msg

    %{
      sender_type: Types.get_sender_atom(control_flag),
      client_id: client_id,
      service_type: Types.get_service_atom(service_type)
    }
  end

  def new(sender, client_id, service, len) do
    sender_id = Types.sender_id(sender)

    ctrl_flags = <<sender_id::little-unsigned-integer-size(8)>>

    service_id = Types.service_id(service)
    service_type = <<service_id::little-unsigned-integer-size(8)>>
    cid = <<client_id::little-unsigned-integer-size(8)>>

    l = <<len + 5::little-unsigned-integer-size(16)>>

    [l, ctrl_flags, service_type, cid]
    |> :erlang.list_to_binary()
  end
end
