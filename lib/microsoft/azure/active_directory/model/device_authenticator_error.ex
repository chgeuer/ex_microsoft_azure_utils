defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.DeviceAuthenticatorError do
  defstruct [
    :correlation_id,
    :error,
    :error_codes,
    :error_description,
    :timestamp,
    :trace_id
  ]

  def from_json(str) when is_binary(str),
    do: str |> Jason.decode!(keys: :atoms) |> from_json()

  def from_json(map) when is_map(map) do
    struct(__MODULE__, map)
  end
end
