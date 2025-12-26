defmodule Microsoft.Azure.ActiveDirectory.RestClient do
  alias Microsoft.Azure.AzureEnvironment

  alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.{
    DeviceCodeResponse,
    TokenResponse,
    DeviceAuthenticatorError,
    State
  }

  @az_cli_clientid "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
  # @az_cli_clientid "c7218025-d73c-46c2-bfbb-ef0a6d4b0c40"

  def proxy_config do
    case System.get_env("http_proxy") do
      nil ->
        []

      "" ->
        []

      proxy_cfg ->
        [host, port] = String.split(proxy_cfg, ":")
        [connect_options: [proxy: {String.to_charlist(host), String.to_integer(port)}]]
    end
  end

  def new do
    Req.new(proxy_config())
  end

  def perform_request(context) do
    client = new()

    opts =
      context
      |> Map.to_list()
      |> Keyword.new()

    Req.request!(client, opts)
  end

  def clean_tenant_id(tenant_id, azure_environment) when is_atom(azure_environment) do
    %{active_directory_tenant_suffix: domain} = AzureEnvironment.get(azure_environment)

    cond do
      tenant_id == "common" -> tenant_id
      tenant_id |> String.ends_with?(".#{domain}") -> tenant_id
      tenant_id |> UUID.info() |> elem(0) == :ok -> tenant_id
      true -> "#{tenant_id}.#{domain}"
    end
  end

  def create_url(v = %{azure_environment: _, endpoint: :active_directory_endpoint, path: _}) do
    "https://#{AzureEnvironment.get_val(v.azure_environment, v.endpoint)}#{v.path}"
  end

  def url(%{} = context, options \\ []) do
    url =
      context
      |> Map.merge(
        options
        |> Enum.into(%{})
      )
      |> create_url()

    context
    |> Map.put(:url, url)
  end

  def service_principal_login(
        tenant_id,
        resource,
        client_id,
        client_secret,
        azure_environment
      )
      when is_atom(azure_environment) do
    form_data = %{
      "resource" => resource,
      "grant_type" => "client_credentials",
      "client_id" => client_id,
      "client_secret" => client_secret
    }

    response =
      %{}
      |> Map.put(:method, :post)
      |> Map.put(:azure_environment, azure_environment)
      |> url(
        endpoint: :active_directory_endpoint,
        path: "/#{tenant_id |> clean_tenant_id(azure_environment)}/oauth2/token?api-version=1.0"
      )
      |> Map.put(:form, form_data)
      |> perform_request()

    case response do
      %{status: 200} ->
        {:ok, response.body |> TokenResponse.from_json()}

      %{status: status} when 400 <= status and status < 500 ->
        {:error, response.body |> DeviceAuthenticatorError.from_json()}
    end
  end

  def discovery_document(tenant_id, azure_environment) when is_atom(azure_environment) do
    response =
      %{}
      |> Map.put(:method, :get)
      |> Map.put(:azure_environment, azure_environment)
      |> url(
        endpoint: :active_directory_endpoint,
        path:
          "/#{tenant_id |> clean_tenant_id(azure_environment)}/.well-known/openid-configuration"
      )
      |> perform_request()

    case response do
      %{status: 200} ->
        {:ok, response.body}

      %{status: status} when 400 <= status and status < 500 ->
        {:error, response.body |> DeviceAuthenticatorError.from_json()}
    end
  end

  def keys(tenant_id, azure_environment) when is_atom(azure_environment) do
    {:ok, %{"jwks_uri" => jwks_uri}} = tenant_id |> discovery_document(azure_environment)

    response =
      %{}
      |> Map.put(:method, :get)
      |> Map.put(:url, jwks_uri)
      |> perform_request()

    case response do
      %{status: 200} ->
        {:ok, response.body |> Map.get("keys") |> Enum.map(&JOSE.JWK.from/1)}

      %{status: status} when 400 <= status and status < 500 ->
        {:error, response.body |> DeviceAuthenticatorError.from_json()}
    end
  end

  def get_device_code(%State{
        tenant_id: tenant_id,
        resource: resource,
        azure_environment: azure_environment
      }) do
    form_data = %{
      "resource" => resource,
      "client_id" => @az_cli_clientid
    }

    response =
      %{}
      |> Map.put(:method, :post)
      |> Map.put(:azure_environment, azure_environment)
      |> url(
        endpoint: :active_directory_endpoint,
        path:
          "/#{tenant_id |> clean_tenant_id(azure_environment)}/oauth2/devicecode?api-version=1.0"
      )
      |> Map.put(:form, form_data)
      |> perform_request()

    case response do
      %{status: 200} ->
        {:ok, response.body |> DeviceCodeResponse.from_json()}

      %{status: status} when 400 <= status and status < 500 ->
        {:error, response.body |> DeviceAuthenticatorError.from_json()}
    end
  end

  def fetch_device_code_token(%State{
        resource: resource,
        azure_environment: azure_environment,
        device_code_response: %DeviceCodeResponse{device_code: device_code}
      }) do
    form_data = %{
      "resource" => resource,
      "code" => device_code,
      "grant_type" => "device_code",
      "client_id" => @az_cli_clientid
    }

    response =
      %{}
      |> Map.put(:method, :post)
      |> Map.put(:azure_environment, azure_environment)
      |> url(
        endpoint: :active_directory_endpoint,
        path: "/common/oauth2/token"
      )
      |> Map.put(:form, form_data)
      |> perform_request()

    case response do
      %{status: 200} ->
        {:ok, response.body |> TokenResponse.from_json()}

      %{status: status} when 400 <= status and status < 500 ->
        {:error, response.body |> DeviceAuthenticatorError.from_json()}
    end
  end

  def refresh_token(%State{
        resource: resource,
        azure_environment: azure_environment,
        token_response: %{refresh_token: refresh_token}
      }) do
    form_data = %{
      "resource" => resource,
      "refresh_token" => refresh_token,
      "grant_type" => "refresh_token",
      "client_id" => @az_cli_clientid
    }

    response =
      %{}
      |> Map.put(:method, :post)
      |> Map.put(:azure_environment, azure_environment)
      |> url(
        endpoint: :active_directory_endpoint,
        path: "/common/oauth2/token"
      )
      |> Map.put(:form, form_data)
      |> perform_request()

    case response do
      %{status: 200} ->
        {:ok, response.body |> TokenResponse.from_json()}

      %{status: status} when 400 <= status and status < 500 ->
        {:error, response.body |> DeviceAuthenticatorError.from_json()}
    end
  end
end
