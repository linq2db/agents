---
area: REMOTE
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 25/25
coverage_tier_2: 6/6
---

# REMOTE

Six transport-binding NuGet packages that expose a linq2db data context over a network wire. Each package is a thin shim: it has no query logic, no mapping logic, and no wire-format ownership. All of those live in [REMOTE-CLIENT](../REMOTE-CLIENT/INDEX.md) (`ILinqService`, `RemoteDataContextBase`, `LinqServiceQuery/Result/Info`) and [INTERNAL-API](../INTERNAL-API/INDEX.md) (`LinqServiceSerializer`).

## Common pattern

Every transport follows the same three-type pattern:

- **`<X>DataContext`** -- subclasses `RemoteDataContextBase`. Overrides `GetClient()` to construct a transport-specific `ILinqService` client. Overrides `ContextIDPrefix` to tag query cache buckets (e.g. `"GrpcRemoteLinqService"`, `"HttpRemoteLinqService"`, `"SignalRRemoteLinqService"`, `"WcfRemoteLinqService"`).
- **`<X>LinqServiceClient`** -- implements `ILinqService` by delegating each of the five methods (`GetInfoAsync`, `ExecuteNonQueryAsync`, `ExecuteScalarAsync`, `ExecuteReaderAsync`, `ExecuteBatchAsync`) to the underlying transport channel. Sets `ILinqService.RemoteClientTag` to a transport identifier string.
- **Server surface** -- receives the same five calls over the wire and delegates to an injected `ILinqService` (the concrete `LinqService` / `LinqService<T>` from REMOTE-CLIENT). Error propagation is uniform: a `bool transferInternalExceptionToClient` flag wraps exceptions in the native error type of the transport (`RpcException` for gRPC, `FaultException` for WCF; HTTP relies on status codes).
- **Client lifetime (HTTP, SignalR)** -- both contexts override `OwnsClient => false` (`HttpClientDataContext.cs:57`, `SignalRDataContext.cs:45`), so `RemoteDataContextBase` never disposes the `ILinqService` per query. The context disposes only the transport object it created itself (`_ownedHttpClient` / `_ownedHubConnection`); objects passed in by the caller stay with the caller.

## Subsystems

### gRPC (`LinqToDB.Remote.Grpc`)

TFMs: `net462;netstandard2.0;net8.0;net9.0;net10.0`. AOT-compatible on net8.0+ (`IsAotCompatible` conditional in the csproj).

gRPC (protobuf-net.Grpc) requires message types for every parameter and return value. Four DTO wrappers live in `Dto/`:
- `GrpcConfiguration` -- wraps `string? Configuration` (field 1). Request for `GetInfoAsync`.
- `GrpcConfigurationQuery` -- wraps `string? Configuration` + `string QueryData` (fields 1, 2). Request for all four query operations.
- `GrpcInt` -- wraps `int Value` (field 1) with bidirectional implicit operators.
- `GrpcString` -- wraps `string? Value` (field 1) with bidirectional implicit operators.

All four carry `[DataContract]` / `[DataMember(Order = N)]`.

`IGrpcLinqService` is the `[Service]` contract; `GrpcLinqService` is the server impl (unwraps `CallContext` for `CancellationToken`; throws `RpcException(StatusCode.Unknown, ...)` on transferred exceptions). `GrpcLinqServiceClient` implements `ILinqService` + `IDisposable` over a `GrpcChannel` proxy. `GrpcDataContext` accepts `string address` + optional `GrpcChannelOptions`; `GetClient()` calls `GrpcChannel.ForAddress(...)` per logical query.

**Compile-time proxies (AOT/trim support).** Two internal partial classes drive the protobuf-net source generators so no proxy or marshaller is reflection-built on the client:
- `GrpcLinqServiceProxies : ClientFactory` (`GrpcLinqServiceProxies.cs:16-18`) -- `[ProtoGrpc(Model = typeof(GrpcLinqServiceTypeModel))]` + `[ProtoService(typeof(IGrpcLinqService), typeof(GrpcLinqService))]`. Generates the client factory and server bindings for `IGrpcLinqService`.
- `GrpcLinqServiceTypeModel : TypeModel` (`GrpcLinqServiceTypeModel.cs:9-10`) -- `[ProtoModel]` compile-time serialization model for the exchanged DTOs.
- Both are `internal sealed`: `GrpcLinqServiceClient` stays the consumer entry point, and generated members would otherwise enter the declared public API (two without nullable annotations). `PublicAPI.Unshipped.txt` therefore holds only `#nullable enable`.
- `GrpcLinqServiceClient` constructor now builds its proxy via `GrpcLinqServiceProxies.Instance.CreateClient<IGrpcLinqService>(channel.CreateCallInvoker())` (`GrpcLinqServiceClient.cs:23`) instead of the reflection-based `CreateGrpcService()`.
- Server hosts may keep `AddCodeFirstGrpc()` (reflection binder); the generated and reflection binders must not both be registered or every operation binds twice (remark on `GrpcLinqServiceProxies`).
- csproj: `PBN9001` added to `NoWarn` (protobuf-net notice that the `[ProtoGrpc]` generator is in use); `ProjectReference` to `LinqToDB` carries `PrivateAssets="contentfiles;build"`.

### HTTP (`LinqToDB.Remote.HttpClient.Client` + `.Server`)

Client TFMs: `net462;netstandard2.0;net8.0;net9.0;net10.0`. Server: `net8.0;net9.0;net10.0` (ASP.NET Core, `Microsoft.NET.Sdk.Web`).

Client: `HttpClientLinqServiceClient` uses `HttpClient` with `PostAsJsonAsync`/`ReadFromJsonAsync`/`ReadAsStringAsync`; endpoint `{requestUri}/{methodName}/{configuration?}`. `HttpClientDataContext` accepts a pre-built client, `(HttpClient, requestUri)`, or `(Uri baseAddress, requestUri)`. Client `ServiceConfigurationExtensions` registers the client keyed-scoped + `TContext` transient + `IDataContextFactory<TContext>`; default route `"api/linq2db"`; `InitHttpClientAsync` warms up via `ConfigureAsync`.

Ownership: the `(Uri baseAddress, requestUri)` ctor creates an `HttpClient` and records it in `_ownedHttpClient` (`HttpClientDataContext.cs:50`); `Dispose()` / `DisposeAsync()` overrides dispose it after the base. `OwnsClient` is `false`, so the `HttpClientLinqServiceClient` itself is never released per query. A caller-supplied `HttpClient` or client is not disposed.

Server: `LinqToDBController` is an `[ApiController]` exposing five `[HttpPost]` actions; lazily creates `LinqService { AllowUpdates = false, RemoteClientTag = "HttpClient" }`. `LinqToDBController<T>` receives `ILinqService<T>` via DI. Server `ServiceConfigurationExtensions` provides `AddLinqToDBController` overloads using `SpecificControllerFeatureProvider<T>` + `ControllerRouteConvention<T>`.

### SignalR (`LinqToDB.Remote.SignalR.Client` + `.Server`)

Shared namespace `LinqToDB.Remote.SignalR`. Client/Server TFMs: `net462;netstandard2.0;net8.0;net9.0;net10.0` (server adds `Microsoft.AspNetCore.SignalR.Core` on pre-net8.0).

Client: `SignalRLinqServiceClient` implements `ILinqService` + `IAsyncDisposable`, delegating to `HubConnection.InvokeAsync<T>(methodName, args)` (method names match `ILinqService` member names). `SignalRDataContext` accepts a pre-built client or a raw `HubConnection`. Client `ServiceConfigurationExtensions` registers `HubConnection` as a singleton wrapped in `Container<HubConnection>`; enables `WithAutomaticReconnect()` on net8.0+; default hub route `"/hub/linq2db"`; `InitSignalRAsync` calls `StartAsync()` + `ConfigureAsync`.

Ownership: the `HubConnection` ctor stores the connection in `_ownedHubConnection` (`SignalRDataContext.cs:38`). `DisposeAsync()` awaits `_ownedHubConnection.DisposeAsync()` after the base; `HubConnection` has no synchronous disposal, so sync `Dispose()` runs `DisposeOwnedHubConnectionAsync` via `Task.Run(...).GetAwaiter().GetResult()` to keep the wait off the synchronization context of the caller (`SignalRDataContext.cs:54-69`). It is a method rather than a lambda because `HubConnection.DisposeAsync` returns `Task` on net462/netstandard2.0 and `ValueTask` on net8.0+ (IDE0200 / MA0215 differ per TFM, hence a scoped `#pragma warning disable MA0215`). `SignalRLinqServiceClient.DisposeAsync()` stays a deliberate no-op (`:61`): the connection belongs to whoever created it.

Server: `LinqToDBHub` extends `Hub`; hub methods are plain named methods. `LinqToDBHub<T>` receives `ILinqService<T>` via DI. No server-side `ServiceConfigurationExtensions` -- user adds `MapHub<LinqToDBHub>()`.

### WCF (`LinqToDB.Remote.Wcf`)

TFM: **`net462` only**. Single combined client+server package using `System.ServiceModel`.

`IWcfLinqService` is the `[ServiceContract]`; methods lack `CancellationToken` (WCF limitation -- client does best-effort `ThrowIfCancellationRequested()`). `WcfLinqService` is `[ServiceBehavior(InstanceContextMode.Single, ConcurrencyMode.Multiple)]`, wraps exceptions as `FaultException`. `WcfLinqServiceClient` extends `ClientBase<IWcfLinqService>` + `ILinqService` (four ctor overloads). `WcfDataContext` mirrors the four ctors; `GetClient()` selects the right one by populated fields.

All six csproj files now reference `LinqToDB.csproj` with `PrivateAssets="contentfiles;build"` (gRPC, HTTP client/server, SignalR client/server, WCF), so content/build assets of the core package do not flow transitively to consumers.

## Key types

| Type | Package | Role |
|---|---|---|
| `IGrpcLinqService` | `linq2db.Remote.Grpc` | gRPC service contract (`[Service]`/`[Operation]`) |
| `GrpcLinqService` | `linq2db.Remote.Grpc` | Server: delegates to `ILinqService` |
| `GrpcLinqServiceClient` | `linq2db.Remote.Grpc` | Client: implements `ILinqService` over gRPC channel (proxy from generated factory) |
| `GrpcLinqServiceProxies` | `linq2db.Remote.Grpc` | Internal `ClientFactory` generated by `[ProtoGrpc]`/`[ProtoService]` (AOT-safe client proxies + server bindings) |
| `GrpcLinqServiceTypeModel` | `linq2db.Remote.Grpc` | Internal `[ProtoModel]` compile-time `TypeModel` for the DTOs |
| `GrpcDataContext` | `linq2db.Remote.Grpc` | Client entry point (`RemoteDataContextBase`) |
| `GrpcConfiguration`/`GrpcConfigurationQuery`/`GrpcInt`/`GrpcString` | `linq2db.Remote.Grpc` | Protobuf message wrappers |
| `HttpClientLinqServiceClient` | `linq2db.Remote.HttpClient.Client` | Client over `HttpClient` |
| `HttpClientDataContext` | `linq2db.Remote.HttpClient.Client` | Client entry point, disposes only an `HttpClient` it created |
| `LinqToDBController`/`LinqToDBController<T>` | `linq2db.Remote.HttpClient.Server` | ASP.NET Core MVC controller |
| `SignalRLinqServiceClient` | `linq2db.Remote.SignalR.Client` | Client over `HubConnection` |
| `SignalRDataContext` | `linq2db.Remote.SignalR.Client` | Client entry point, disposes the `HubConnection` handed to its raw-connection ctor |
| `LinqToDBHub`/`LinqToDBHub<T>` | `linq2db.Remote.SignalR.Server` | ASP.NET Core SignalR hub |
| `IWcfLinqService` | `linq2db.Remote.Wcf` | WCF service contract |
| `WcfLinqService` | `linq2db.Remote.Wcf` | Server `[ServiceBehavior]` impl |
| `WcfLinqServiceClient` | `linq2db.Remote.Wcf` | Client `ClientBase<IWcfLinqService>` + `ILinqService` |
| `WcfDataContext` | `linq2db.Remote.Wcf` | Client entry point |

## Files (Tier 1 / Tier 2)

**Tier 1** (all `.cs` files in the area, every file read): the gRPC `GrpcDataContext`/`GrpcLinqService`/`GrpcLinqServiceClient`/`GrpcLinqServiceProxies`/`GrpcLinqServiceTypeModel`/`IGrpcLinqService` + 4 `Dto/*`; HTTP client `HttpClientDataContext`/`HttpClientLinqServiceClient`/`ServiceConfigurationExtensions`; HTTP server `LinqToDBController`/`LinqToDBController{T}`/`ServiceConfigurationExtensions`; SignalR client `SignalRDataContext`/`SignalRLinqServiceClient`/`ServiceConfigurationExtensions`; SignalR server `LinqToDBHub`/`LinqToDBHub{T}`; WCF `WcfDataContext`/`WcfLinqService`/`WcfLinqServiceClient`/`IWcfLinqService`.

**Tier 2** (6 csproj files -- read for TFM data): `LinqToDB.Remote.Grpc.csproj`, `LinqToDB.Remote.HttpClient.Client.csproj`, `LinqToDB.Remote.HttpClient.Server.csproj`, `LinqToDB.Remote.SignalR.Client.csproj`, `LinqToDB.Remote.SignalR.Server.csproj`, `LinqToDB.Remote.Wcf.csproj`.

**Tier 3**: none.

## TFM matrix

| Package | TFMs |
|---|---|
| `linq2db.Remote.Grpc` | `net462;netstandard2.0;net8.0;net9.0;net10.0` |
| `linq2db.Remote.HttpClient.Client` | `net462;netstandard2.0;net8.0;net9.0;net10.0` |
| `linq2db.Remote.HttpClient.Server` | `net8.0;net9.0;net10.0` (ASP.NET Core only) |
| `linq2db.Remote.SignalR.Client` | `net462;netstandard2.0;net8.0;net9.0;net10.0` |
| `linq2db.Remote.SignalR.Server` | `net462;netstandard2.0;net8.0;net9.0;net10.0` (needs `Microsoft.AspNetCore.SignalR.Core` on pre-net8.0) |
| `linq2db.Remote.Wcf` | `net462` only |

## Inbound / outbound dependencies

**Inbound:** user application code that installs one of these NuGet packages.

**Outbound:**
- [REMOTE-CLIENT](../REMOTE-CLIENT/INDEX.md) -- `ILinqService`, `ILinqService<T>`, `RemoteDataContextBase`, `LinqService`, `LinqService<T>`, `LinqServiceInfo`, `IDataContextFactory<T>`, `DataContextFactory<T>`. Every type here is defined against REMOTE-CLIENT contracts.
- [INTERNAL-API](../INTERNAL-API/INDEX.md) -- `LinqServiceSerializer` (owned by `Internal/Remote/`). Transports pass the string payload opaquely, they own none of the encoding.
- ASP.NET Core (`Microsoft.AspNetCore.Mvc`, `Microsoft.AspNetCore.SignalR`) -- server packages only.
- `Grpc.Net.Client`, `protobuf-net.Grpc`, `protobuf-net` -- gRPC (protobuf-net source generators for `[ProtoGrpc]` / `[ProtoModel]`).
- `Microsoft.Extensions.Http` -- HTTP client.
- `System.ServiceModel` -- WCF (net462 BCL).

## Known issues / debt

- **`WcfLinqServiceClient.RemoteClientTag` Cyrillic typo** (`WcfLinqServiceClient.cs:57`): `"Wсf"` contains a Cyrillic `с` (U+0441). No functional impact but breaks equality vs Latin `"Wcf"`.
- **WCF cancellation is best-effort only** -- `ThrowIfCancellationRequested()` before each call, cannot cancel in-flight WCF calls.
- **`SignalRLinqServiceClient.DisposeAsync` is a no-op** (`SignalRLinqServiceClient.cs:61`), lifetime is managed by `SignalRDataContext` (which disposes a raw `HubConnection` it was given) or DI.
- **SignalR server has no `ServiceConfigurationExtensions`** -- no `AddLinqToDBHub` analogue to `AddLinqToDBController` (inconsistency with HTTP).
- **gRPC creates a new channel per query** (`GrpcDataContext.GetClient()`), channel pooling not explicit.
- **gRPC `ExecuteBatchAsync` drops the cancellation token** (`GrpcLinqServiceClient.cs:72-78`): the other four calls forward `cancellationToken` to the proxy, this one does not.
- **HTTP `CA2000` suppression** (`HttpClientDataContext.cs:46`) for the `HttpClient` transferred to `HttpClientLinqServiceClient`.
- **SignalR sync `Dispose()` blocks** on `Task.Run(DisposeOwnedHubConnectionAsync).GetAwaiter().GetResult()` (`SignalRDataContext.cs:59`), unavoidable as `HubConnection` has no sync disposal -- prefer `DisposeAsync`.
- **gRPC server binder choice**: generated bindings (`GrpcLinqServiceProxies`) and `AddCodeFirstGrpc()` must not both be registered on one host.

## See also

- [REMOTE-CLIENT](../REMOTE-CLIENT/INDEX.md) -- contracts and default implementations this area binds.
- [INTERNAL-API](../INTERNAL-API/INDEX.md) -- `LinqServiceSerializer` (wire format ownership).
- [EXTENSIONS-PKG](../EXTENSIONS-PKG/INDEX.md) -- `AddLinqToDBService<TContext>` registers `ILinqService<TContext>` for the server side.

<details><summary>Coverage</summary>

- Tier 1 (visited / total): 23 / 23 (all .cs files in area read in full)
- Tier 2 (visited / total): 6 / 6 (all csprojs read for TFM/package data)
- Tier 3 (skipped, logged): 0

Read (this run -- delta):
- `Source/LinqToDB.Remote.Grpc/PublicAPI.Shipped.txt` -- v6 release promotion: Unshipped entries moved to Shipped. No API surface changes; pure baseline churn.
- `Source/LinqToDB.Remote.Wcf/PublicAPI.Shipped.txt` -- v6 release promotion: Unshipped entries moved to Shipped. No API surface changes; pure baseline churn.

Read (this run -- delta):
- `Source/LinqToDB.Remote.Grpc/GrpcLinqServiceClient.cs` -- proxy now from generated `GrpcLinqServiceProxies.Instance.CreateClient`, not reflection `CreateGrpcService()`.
- `Source/LinqToDB.Remote.Grpc/GrpcLinqServiceProxies.cs` -- new (Tier 1): internal `[ProtoGrpc]`/`[ProtoService]` `ClientFactory` for AOT/trim.
- `Source/LinqToDB.Remote.Grpc/GrpcLinqServiceTypeModel.cs` -- new (Tier 1): internal `[ProtoModel]` `TypeModel`.
- `Source/LinqToDB.Remote.Grpc/LinqToDB.Remote.Grpc.csproj` -- `PBN9001` NoWarn, `PrivateAssets` on core reference.
- `Source/LinqToDB.Remote.Grpc/PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt` -- baseline only (Unshipped is `#nullable enable`), generated types are internal.
- `Source/LinqToDB.Remote.HttpClient.Client/HttpClientDataContext.cs` -- `OwnsClient => false`, `_ownedHttpClient` disposed in `Dispose`/`DisposeAsync`.
- `Source/LinqToDB.Remote.HttpClient.Client/PublicAPI.Shipped.txt` -- adds `Dispose`, `DisposeAsync`, `OwnsClient` overrides.
- `Source/LinqToDB.Remote.SignalR.Client/SignalRDataContext.cs` -- `OwnsClient => false`, `_ownedHubConnection` disposed (sync via `Task.Run`, async directly).
- `Source/LinqToDB.Remote.SignalR.Client/SignalRLinqServiceClient.cs` -- `DisposeAsync` no-op documented by comment.
- `Source/LinqToDB.Remote.SignalR.Client/PublicAPI.Shipped.txt` -- adds `Dispose`, `OwnsClient` overrides.
- `Source/LinqToDB.Remote.HttpClient.Client/LinqToDB.Remote.HttpClient.Client.csproj`, `HttpClient.Server`, `SignalR.Client`, `SignalR.Server`, `Wcf` csproj -- `PrivateAssets="contentfiles;build"` on core `ProjectReference`.
</details>
