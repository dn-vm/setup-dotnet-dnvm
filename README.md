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

Or install the version pinned by a `global.json` (roll-forward rules are applied):

```yaml
- uses: dn-vm/setup-dotnet-dnvm@v1
  with:
    global-json-file: global.json
```

## Inputs

| Name               | Required | Default        | Description                                                       |
|--------------------|----------|----------------|-------------------------------------------------------------------|
| `dotnet-version`   | *        |                | Exact .NET SDK version to install (e.g. `8.0.100`).               |
| `global-json-file` | *        |                | Path to a `global.json` whose SDK version is installed (with roll-forward). |
| `dnvm-version`     | no       | `1.1.2`        | Version of dnvm to use as the install engine.                     |
| `install-dir`      | no       | `$HOME/.dnvm`  | `DNVM_HOME` directory the SDK is installed into.                  |

\* Provide exactly one of `dotnet-version` or `global-json-file`.

> **Note:** v1 supports **exact** SDK versions and `global.json`. Floating versions and
> channels (`latest`, `lts`, `8.0`, `8.0.1xx`), quality, and architecture selection are
> planned for later releases.

## Outputs

| Name             | Description                          |
|------------------|--------------------------------------|
| `dotnet-version` | The installed .NET SDK version.      |
| `dotnet-root`    | `DOTNET_ROOT` of the installed SDK.  |

## Environment set for later steps

- Prepends the SDK directory to `PATH`.
- Sets `DOTNET_ROOT`.

## Caching

Like [`actions/setup-dotnet`](https://github.com/actions/setup-dotnet), the SDK is
downloaded on each run. `setup-dotnet`'s `cache` input caches the **NuGet global-packages
folder** (`~/.nuget/packages`), *not* the SDK — you can do the same here with
[`actions/cache`](https://github.com/actions/cache), independently of this action.

Because dnvm tracks installed SDKs in a manifest, you can *optionally* also cache the
install directory to skip the SDK download on a cache hit — something `setup-dotnet` cannot
easily do:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.dnvm
    key: dnvm-${{ runner.os }}-${{ runner.arch }}-8.0.100

- uses: dn-vm/setup-dotnet-dnvm@v1
  with:
    dotnet-version: '8.0.100'
```

## Platform support

| OS      | x64 | arm64 |
|---------|-----|-------|
| Linux   | ✅  | ✅    |
| macOS   | ✅  | ✅    |
| Windows | ✅  | ❌ (dnvm publishes win-x64 only) |
