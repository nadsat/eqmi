defmodule Eqmi.QmuxHeader do
  def parse(msg) do
    <<control_flag::integer-size(8), service_type::integer-size(8), client_id::integer-size(8)>> =
      msg

    %{
      sender_type: Eqmi.get_sender_type(control_flag),
      client_id: client_id,
      service_type: Eqmi.get_service_type(service_type)
    }
  end
end
