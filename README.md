# ExMicrosoftAzureManagementSamples

## Sign-in demo

```bash
/mnt/c/Program\ Files\ \(x86\)/Elixir/bin/iex -S mix
```

```elixir
#
# Sign in to Storage using Azure AD
#
alias Microsoft.Azure.ActiveDirectory.{DeviceAuthenticator, DeviceAuthenticatorSupervisor}
alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.State
alias Microsoft.Azure.Storage
alias Microsoft.Azure.Storage.{Container, Blob, Queue, BlobStorage}

storage_account_name = "erlang"
resource = "https://#{storage_account_name}.blob.core.windows.net/"

{:ok, storage_pid} = %State{ resource: resource, tenant_id: "chgeuerfte.onmicrosoft.com", azure_environment: :azure_global } |> DeviceAuthenticatorSupervisor.start_link()

storage_pid |> DeviceAuthenticator.get_device_code()

aad_token_provider = fn (_resource) ->
    storage_pid |> DeviceAuthenticator.get_token
    |> elem(1)
    |> Map.get(:access_token)
end

aad_token_provider.(resource)

aad_token_provider.(resource) |> JOSE.JWT.peek()
aad_token_provider.(resource) |> JOSE.JWT.peek() |> Map.get(:fields) |> Enum.map( fn({k,v}) -> "#{k |> String.pad_trailing(12, " ")}: #{inspect(v)}" end) |> Enum.join("\n") |> IO.puts()
aad_token_provider.(resource) |> JOSE.JWT.peek() |> Map.get(:fields) |> Map.get("iat")

storage_pid |> DeviceAuthenticatorSupervisor.get_agent_state()

storage_pid |> DeviceAuthenticatorSupervisor.get_worker_pid() |> Process.exit(:kill)
```

--------------------------

## misc

Currently, I'm having problems POSTing to ARM API: https://github.com/swagger-api/swagger-codegen/issues/8138

- https://github.com/OAI/OpenAPI-Specification/blob/master/versions/3.0.0.md#parameterObject
- https://github.com/swagger-api/swagger-codegen/blob/master/modules/swagger-codegen/src/main/java/io/swagger/codegen/languages/ElixirClientCodegen.java
- https://github.com/swagger-api/swagger-codegen/tree/master/modules/swagger-codegen/src/main/resources/elixir
- https://github.com/swagger-api/swagger-codegen/blob/master/modules/swagger-codegen/src/main/resources/elixir/api.mustache#L46
- https://swagger.io/docs/specification/2-0/describing-request-body/


```sh
find . -type f -name "*.ex" -exec sed -i'' -e 's/add_param(:body, :"parameters", parameters)/add_param(:body, :body, parameters)/g' {} +
```
