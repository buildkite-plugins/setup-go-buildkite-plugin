# setup-go Buildkite Plugin

Install Go via [mise](https://mise.jdx.dev/), export the Go toolchain into the Buildkite step, and wire Go caches.

This plugin is intentionally opinionated:

- `mise` is installed if missing or at the wrong version
- repository-defined Go in `.tool-versions`, `mise.toml`, or `.mise.toml` is installed with `mise install go`
- otherwise Go is installed via `mise install go@<version>`
- `mise env --shell bash ...` is appended to `$BUILDKITE_ENV_FILE`
- `GOCACHE`, `GOMODCACHE`, `GOPATH`, and `GOLANGCI_LINT_CACHE` are exported automatically
- `MISE_DATA_DIR` defaults match `buildkite-plugins/mise-buildkite-plugin` so the toolchain cache is shared

## Examples

### Pin a Go version

```yml
steps:
  - label: ":golang: Test"
    plugins:
      - setup-go#v0.1.0:
          version: 1.24.0
    command: go test ./...
```

### Read the version from `go.mod`

```yml
steps:
  - label: ":golang: Test"
    plugins:
      - setup-go#v0.1.0: ~
    command: go test ./...
```

If `version` and `version-file` are unset, the plugin searches `dir` in this order:

1. `.tool-versions`
2. `mise.toml`
3. `.mise.toml`
4. `go.work`
5. `go.mod`

For `go.mod` and `go.work`, `toolchain go1.x.y` wins over `go 1.x`, while `toolchain default` falls back to the `go` directive.

### Monorepo example

```yml
steps:
  - label: ":golang: Test backend"
    plugins:
      - setup-go#v0.1.0:
          dir: backend
    command: go test ./...
```

### Hosted agent cache volumes

```yml
cache: ".buildkite/cache-volume"

steps:
  - label: ":golang: Test"
    plugins:
      - setup-go#v0.1.0: ~
    command: go test ./...
```

When running on Buildkite hosted agents, the plugin automatically uses `/cache/bkcache/mise` for `MISE_DATA_DIR` and `/cache/bkcache/setup-go` for Go caches when a cache volume is attached. Buildkite only mounts that volume when the pipeline or step defines `cache`, so you still need to request one in `pipeline.yml`.

## Configuration

- `version`: Go version to install, for example `1.24.0`. Highest precedence.
- `version-file`: file containing the Go version. Relative paths are resolved from `dir`.
- `dir`: directory used for version discovery. Defaults to the checkout directory.
- `mise-version` (default: `latest`): mise version to install.
- `cache-root`: root directory for `GOCACHE`, `GOMODCACHE`, `GOPATH`, and `GOLANGCI_LINT_CACHE`. When set, `MISE_DATA_DIR` is colocated under `<cache-root>/mise`.

## Environment

The plugin exports:

- `MISE_DATA_DIR`
- `MISE_TRUSTED_CONFIG_PATHS`
- `MISE_YES`
- `GOCACHE`
- `GOMODCACHE`
- `GOPATH`
- `GOLANGCI_LINT_CACHE`

Default `MISE_DATA_DIR` values match `buildkite-plugins/mise-buildkite-plugin`:

- hosted agents with a cache volume: `/cache/bkcache/mise`
- `XDG_DATA_HOME/mise` when `XDG_DATA_HOME` is set
- `~/.local/share/mise` otherwise

The Go cache defaults under `cache-root` are:

- `GOCACHE=<cache-root>/go/build`
- `GOPATH=<cache-root>/go`
- `GOMODCACHE=<cache-root>/go/pkg/mod`
- `GOLANGCI_LINT_CACHE=<cache-root>/golangci-lint`

`PATH` is also prefixed with `${GOBIN:-${GOPATH}/bin}` so installed Go tools remain available in later commands.

If the corresponding environment variables are already set, they take precedence over plugin configuration.

## Development

Run plugin checks locally:

```bash
mise install
docker run --rm -v "$PWD:/plugin" -w /plugin buildkite/plugin-linter --id setup-go --path /plugin
docker run --rm -v "$PWD:/plugin" -w /plugin buildkite/plugin-tester
bats tests/pre-command.bats
"$(mise where shellcheck@0.11.0)/shellcheck-v0.11.0/shellcheck" hooks/pre-command tests/pre-command.bats
```
