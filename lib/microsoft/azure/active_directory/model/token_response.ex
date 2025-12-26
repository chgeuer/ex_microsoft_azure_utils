defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.TokenResponse do
  @derive {Inspect, except: [:access_token, :refresh_token, :id_token]}

  defstruct [
    :access_token,
    :refresh_token,
    :id_token,
    :expires_in,
    :expires_on,
    :ext_expires_in,
    :not_before,
    :resource,
    :token_type,
    :scope,
    :foci
  ]

  def from_json(json) when is_binary(json),
    do: json |> Jason.decode!(keys: :atoms) |> from_json()

  def from_json(map) when is_map(map) do
    struct(__MODULE__, map)
    |> Map.update!(:not_before, fn
      val when is_binary(val) -> val |> String.to_integer() |> DateTime.from_unix!()
      val when is_integer(val) -> DateTime.from_unix!(val)
    end)
    |> Map.update!(:expires_on, fn
      val when is_binary(val) -> val |> String.to_integer() |> DateTime.from_unix!()
      val when is_integer(val) -> DateTime.from_unix!(val)
    end)
    |> Map.update!(:expires_in, fn
      val when is_binary(val) -> String.to_integer(val)
      val when is_integer(val) -> val
    end)
    |> Map.update!(:ext_expires_in, fn
      val when is_binary(val) -> String.to_integer(val)
      val when is_integer(val) -> val
    end)
  end
end
