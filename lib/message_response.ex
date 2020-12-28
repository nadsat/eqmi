defmodule Eqmi.MessageResponse do
  def parse(msg) do
    <<result::binary-size(2), err::binary-size(2)>> = msg
    qmi_result = :binary.decode_unsigned(result, :little)
    qmi_error = :binary.decode_unsigned(err, :little)
    %{qmi_result: qmi_result, qmi_error: qmi_error}
  end
end
