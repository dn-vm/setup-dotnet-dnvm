# setup-dotnet-dnvm

A GitHub Action that installs a specific .NET SDK version using
[dnvm](https://github.com/dn-vm/dnvm) as the install engine, as an alternative to
[`actions/setup-dotnet`](https://github.com/actions/setup-dotnet).

Because dnvm installs into a manifest-tracked `DNVM_HOME`, re-running the action for an
SDK that is already installed is a no-op — combine it with `actions/cache` on the install
directory to skip re-downloads across runs.

## Usage

```yaml
- uses: dn-vm/setup-dotnet-dnvm@v1
  with:
    dotnet-version: '8.0.100'

- run: dotnet --version
```

## Inputs

| Name             | Required | Default        | Description                                             |
|------------------|----------|----------------|---------------------------------------------------------|
| `dotnet-version` | yes      |                | Exact .NET SDK version to install (e.g. `8.0.100`).     |
| `dnvm-version`   | no       | `1.1.2`        | Version of dnvm to use as the install engine.           |
| `install-dir`    | no       | `$HOME/.dnvm`  | `DNVM_HOME` directory the SDK is installed into.        |

> **Note:** v1 supports **exact** SDK versions only. Floating versions and channels
> (`latest`, `lts`, `8.0`, `8.0.1xx`), quality, `global.json`, and architecture selection
> are planned for later releases.

## Outputs

| Name             | Description                          |
|------------------|--------------------------------------|
| `dotnet-version` | The installed .NET SDK version.      |
| `dotnet-root`    | `DOTNET_ROOT` of the installed SDK.  |

## Environment set for later steps

- Prepends the SDK directory to `PATH`.
- Sets `DOTNET_ROOT`.

## Platform support

| OS      | x64 | arm64 |
|---------|-----|-------|
| Linux   | ✅  | ✅    |
| macOS   | ✅  | ✅    |
| Windows | ✅  | ❌ (dnvm publishes win-x64 only) |
