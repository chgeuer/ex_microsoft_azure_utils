defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.DeviceAuthenticatorError do
  defstruct [
    :correlation_id,
    :error,
    :error_codes,
    :error_description,
    :timestamp,
    :trace_id
  ]

  def from_json(str),
    do:
      str
      |> Poison.decode!(keys: :atoms, as: %__MODULE__{})
end
