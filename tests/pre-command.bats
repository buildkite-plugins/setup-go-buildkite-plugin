#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  export HOME="${TEST_TMPDIR}/home"
  export BUILDKITE_BUILD_CHECKOUT_PATH="${TEST_TMPDIR}/checkout"
  export BUILDKITE_ENV_FILE="${TEST_TMPDIR}/env"
  export BUILDKITE_PLUGIN_SETUP_GO_MISE_VERSION="1.0.0"
  export MISE_MOCK_CONFIG_GO_VERSION="1.0.0"
  export PATH="${TEST_TMPDIR}/mock-bin:${PATH}"

  mkdir -p "${HOME}" "${BUILDKITE_BUILD_CHECKOUT_PATH}" "${TEST_TMPDIR}/mock-bin"
  write_unexpected_install_mock curl
  write_unexpected_install_mock tar

  export MISE_DATA_DIR="${TEST_TMPDIR}/mise-data"
  write_mise_mock "${MISE_DATA_DIR}"

  export MISE_MOCK_LOG="${TEST_TMPDIR}/mise.log"
  : > "${MISE_MOCK_LOG}"

  unset BUILDKITE_PLUGIN_SETUP_GO_CACHE_ROOT
  unset BUILDKITE_PLUGIN_SETUP_GO_DIR
  unset BUILDKITE_PLUGIN_SETUP_GO_VERSION
  unset BUILDKITE_PLUGIN_SETUP_GO_VERSION_FILE
  unset BUILDKITE_COMPUTE_TYPE
  unset GOBIN
  unset GOCACHE
  unset GOLANGCI_LINT_CACHE
  unset GOMODCACHE
  unset GOPATH
  unset MISE_HOSTED_CACHE_VOLUME_ROOT
  unset SETUP_GO_HOSTED_CACHE_VOLUME_ROOT
  unset XDG_DATA_HOME
  unset XDG_CACHE_HOME
}

write_mise_mock() {
  local data_dir="$1"

  mkdir -p "${data_dir}/bin"

  cat > "${data_dir}/bin/mise" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

log_file="${MISE_MOCK_LOG:?}"
cmd="${1:-}"

resolve_version() {
  case "${1:-}" in
    go@*)
      printf '%s' "${1#go@}"
      ;;
    go)
      printf '%s' "${MISE_MOCK_CONFIG_GO_VERSION:-1.0.0}"
      ;;
    *)
      printf '%s' "${1:-}"
      ;;
  esac
}

write_go_mock() {
  local version="$1"
  local go_root="${MISE_DATA_DIR}/installs/go/${version}"

  mkdir -p "${go_root}/bin"
  cat > "${go_root}/bin/go" <<'GO'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  env)
    if [ "${2:-}" = "-json" ]; then
      version="${GOROOT##*/}"
      cat <<JSON
{
  "GOVERSION": "go${version}",
  "GOROOT": "${GOROOT:-}",
  "GOPATH": "${GOPATH:-}",
  "GOMODCACHE": "${GOMODCACHE:-}",
  "GOCACHE": "${GOCACHE:-}",
  "GOBIN": "${GOBIN:-}"
}
JSON
    else
      exit 1
    fi
    ;;
  *)
    exit 1
    ;;
esac
GO
  chmod +x "${go_root}/bin/go"
}

case "${cmd}" in
  --version|version)
    echo "1.0.0 linux-x64 (2026-03-19)"
    ;;
  install)
    if [ -n "${2:-}" ]; then
      write_go_mock "$(resolve_version "${2}")"
    fi
    echo "install pwd=${PWD} $*" >> "${log_file}"
    ;;
  env)
    if [ "${2:-}" = "--shell" ] && [ "${3:-}" = "bash" ] && [ -n "${4:-}" ]; then
      version="$(resolve_version "${4}")"
      echo "export GOROOT=\"${MISE_DATA_DIR}/installs/go/${version}\""
      echo "export PATH=\"${MISE_DATA_DIR}/installs/go/${version}/bin:\$PATH\""
      echo "env pwd=${PWD} $*" >> "${log_file}"
    else
      exit 1
    fi
    ;;
  ls)
    if [ -f "${PWD}/.tool-versions" ]; then
      source_path="${PWD}/.tool-versions"
    elif [ -f "${PWD}/mise.toml" ]; then
      source_path="${PWD}/mise.toml"
    elif [ -f "${PWD}/.mise.toml" ]; then
      source_path="${PWD}/.mise.toml"
    else
      echo "[]"
      exit 0
    fi

    cat <<JSON
[
  {
    "version": "${MISE_MOCK_CONFIG_GO_VERSION:-1.0.0}",
    "source": {
      "path": "${source_path}"
    }
  }
]
JSON
    ;;
  *)
    echo "unexpected command: $*" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "${data_dir}/bin/mise"
}

write_unexpected_install_mock() {
  local tool="$1"

  cat > "${TEST_TMPDIR}/mock-bin/${tool}" <<MOCK
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected ${tool} invocation" >&2
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/mock-bin/${tool}"
}

teardown() {
  rm -rf "${TEST_TMPDIR}"
}

setup_install_mocks() {
  cat > "${TEST_TMPDIR}/mock-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'mock archive'
MOCK

  cat > "${TEST_TMPDIR}/mock-bin/tar" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

dest=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -C)
      dest="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p "${dest}/mise/bin"
cat > "${dest}/mise/bin/mise" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail

write_go_mock() {
  local version="$1"
  local go_root="${MISE_DATA_DIR}/installs/go/${version}"

  mkdir -p "${go_root}/bin"
  cat > "${go_root}/bin/go" <<'GO'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  env)
    if [ "${2:-}" = "-json" ]; then
      version="${GOROOT##*/}"
      cat <<JSON
{
  "GOVERSION": "go${version}",
  "GOROOT": "${GOROOT:-}",
  "GOPATH": "${GOPATH:-}",
  "GOMODCACHE": "${GOMODCACHE:-}",
  "GOCACHE": "${GOCACHE:-}",
  "GOBIN": "${GOBIN:-}"
}
JSON
    else
      exit 1
    fi
    ;;
  *)
    exit 1
    ;;
esac
GO
  chmod +x "${go_root}/bin/go"
}

case "${1:-}" in
  --version|version)
    echo "1.0.0 linux-x64 (2026-03-19)"
    ;;
  install)
    if [ -n "${2:-}" ]; then
      case "${2}" in
        go@*)
          version="${2#go@}"
          ;;
        go)
          version="${MISE_MOCK_CONFIG_GO_VERSION:-1.0.0}"
          ;;
        *)
          version="${2}"
          ;;
      esac
      write_go_mock "${version}"
    fi
    ;;
  env)
    if [ "${2:-}" = "--shell" ] && [ "${3:-}" = "bash" ] && [ -n "${4:-}" ]; then
      case "${4}" in
        go@*)
          version="${4#go@}"
          ;;
        go)
          version="${MISE_MOCK_CONFIG_GO_VERSION:-1.0.0}"
          ;;
        *)
          version="${4}"
          ;;
      esac
      echo "export GOROOT=\"${MISE_DATA_DIR}/installs/go/${version}\""
      echo "export PATH=\"${MISE_DATA_DIR}/installs/go/${version}/bin:\$PATH\""
    else
      exit 1
    fi
    ;;
  ls)
    if [ -f "${PWD}/.tool-versions" ]; then
      source_path="${PWD}/.tool-versions"
    elif [ -f "${PWD}/mise.toml" ]; then
      source_path="${PWD}/mise.toml"
    elif [ -f "${PWD}/.mise.toml" ]; then
      source_path="${PWD}/.mise.toml"
    else
      echo "[]"
      exit 0
    fi

    cat <<JSON
[
  {
    "version": "${MISE_MOCK_CONFIG_GO_VERSION:-1.0.0}",
    "source": {
      "path": "${source_path}"
    }
  }
]
JSON
    ;;
  *)
    echo "unexpected installed command: $*" >&2
    exit 1
    ;;
esac
INNER
chmod +x "${dest}/mise/bin/mise"
MOCK

  chmod +x "${TEST_TMPDIR}/mock-bin/curl" "${TEST_TMPDIR}/mock-bin/tar"
}

@test "uses plugin version config and exports Go cache environment" {
  export BUILDKITE_PLUGIN_SETUP_GO_VERSION="1.24.0"

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  grep -F "install pwd=${BUILDKITE_BUILD_CHECKOUT_PATH} install go@1.24.0" "${MISE_MOCK_LOG}"
  grep -F "env pwd=${BUILDKITE_BUILD_CHECKOUT_PATH} env --shell bash go@1.24.0" "${MISE_MOCK_LOG}"
  grep -F "export GOCACHE=${HOME}/.cache/setup-go-buildkite-plugin/go/build" "${BUILDKITE_ENV_FILE}"
  grep -F "export GOMODCACHE=${HOME}/.cache/setup-go-buildkite-plugin/go/pkg/mod" "${BUILDKITE_ENV_FILE}"
  grep -F "export GOPATH=${HOME}/.cache/setup-go-buildkite-plugin/go" "${BUILDKITE_ENV_FILE}"
  grep -F "export GOLANGCI_LINT_CACHE=${HOME}/.cache/setup-go-buildkite-plugin/golangci-lint" "${BUILDKITE_ENV_FILE}"
  [[ "${output}" == *'"GOVERSION": "go1.24.0"'* ]]
  [[ "${output}" != *"white_check_mark"* ]]
}

@test "exports Go environment in the hook shell" {
  export BUILDKITE_PLUGIN_SETUP_GO_VERSION="1.24.0"

  run bash -c "
    . hooks/pre-command >/dev/null
    env | grep -Fx 'GOCACHE=${HOME}/.cache/setup-go-buildkite-plugin/go/build'
    env | grep -Fx 'GOMODCACHE=${HOME}/.cache/setup-go-buildkite-plugin/go/pkg/mod'
    env | grep -Fx 'GOPATH=${HOME}/.cache/setup-go-buildkite-plugin/go'
    env | grep -Fx 'GOLANGCI_LINT_CACHE=${HOME}/.cache/setup-go-buildkite-plugin/golangci-lint'
    env | grep -Fx 'MISE_TRUSTED_CONFIG_PATHS=${BUILDKITE_BUILD_CHECKOUT_PATH}'
    case \":\$PATH:\" in
      *\":${HOME}/.cache/setup-go-buildkite-plugin/go/bin:\"*) ;;
      *) exit 1 ;;
    esac
    case \":\$PATH:\" in
      *\":${MISE_DATA_DIR}/installs/go/1.24.0/bin:\"*) ;;
      *) exit 1 ;;
    esac
  "

  [ "${status}" -eq 0 ]
}

@test "resolves version from go.mod toolchain" {
  cat > "${BUILDKITE_BUILD_CHECKOUT_PATH}/go.mod" <<'EOF'
module example.com/test

go 1.23.0
toolchain go1.23.5
EOF

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  grep -F "install pwd=${BUILDKITE_BUILD_CHECKOUT_PATH} install go@1.23.5" "${MISE_MOCK_LOG}"
  [[ "${output}" == *"Using Go version: 1.23.5"* ]]
}

@test "falls back to go directive when toolchain is default" {
  cat > "${BUILDKITE_BUILD_CHECKOUT_PATH}/go.mod" <<'EOF'
module example.com/test

go 1.23.0
toolchain default
EOF

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  grep -F "install pwd=${BUILDKITE_BUILD_CHECKOUT_PATH} install go@1.23.0" "${MISE_MOCK_LOG}"
  [[ "${output}" == *"Using Go version: 1.23.0"* ]]
}

@test "uses version-file relative to dir" {
  subdir="${BUILDKITE_BUILD_CHECKOUT_PATH}/backend"
  mkdir -p "${subdir}"
  printf '1.22.7\n' > "${subdir}/.go-version"
  export BUILDKITE_PLUGIN_SETUP_GO_DIR="${subdir}"
  export BUILDKITE_PLUGIN_SETUP_GO_VERSION_FILE=".go-version"

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  grep -F "install pwd=${subdir} install go@1.22.7" "${MISE_MOCK_LOG}"
}

@test "parses version-file from mise.toml table syntax" {
  subdir="${BUILDKITE_BUILD_CHECKOUT_PATH}/backend"
  mkdir -p "${subdir}"
  cat > "${subdir}/mise.toml" <<'EOF'
[tools.go]
version = "1.22.7"
EOF
  export BUILDKITE_PLUGIN_SETUP_GO_DIR="${subdir}"
  export BUILDKITE_PLUGIN_SETUP_GO_VERSION_FILE="mise.toml"

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  grep -F "install pwd=${subdir} install go@1.22.7" "${MISE_MOCK_LOG}"
}

@test "uses repo go from mise.toml and shared mise data dir defaults" {
  unset MISE_DATA_DIR
  export MISE_MOCK_CONFIG_GO_VERSION="1.24.0"
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  cat > "${BUILDKITE_BUILD_CHECKOUT_PATH}/mise.toml" <<'EOF'
[tools.go]
version = "1.24.0"
EOF
  write_mise_mock "${XDG_DATA_HOME}/mise"

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  grep -F "Using mise data dir: ${XDG_DATA_HOME}/mise (XDG_DATA_HOME fallback)" <<< "${output}"
  grep -F "Using Go version: 1.24.0 (${BUILDKITE_BUILD_CHECKOUT_PATH}/mise.toml)" <<< "${output}"
  grep -F "install pwd=${BUILDKITE_BUILD_CHECKOUT_PATH} install go" "${MISE_MOCK_LOG}"
  grep -F "env pwd=${BUILDKITE_BUILD_CHECKOUT_PATH} env --shell bash go" "${MISE_MOCK_LOG}"
  grep -F "export MISE_DATA_DIR=${XDG_DATA_HOME}/mise" "${BUILDKITE_ENV_FILE}"
}

@test "uses hosted cache volume automatically when available" {
  hosted_cache_root="${TEST_TMPDIR}/hosted-cache"
  unset MISE_DATA_DIR
  export BUILDKITE_PLUGIN_SETUP_GO_VERSION="1.24.0"
  export BUILDKITE_COMPUTE_TYPE="hosted"
  export MISE_HOSTED_CACHE_VOLUME_ROOT="${hosted_cache_root}"
  write_mise_mock "${hosted_cache_root}/mise"

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  grep -F "Using cache root: ${hosted_cache_root}/setup-go (Buildkite hosted agent cache volume)" <<< "${output}"
  grep -F "Using mise data dir: ${hosted_cache_root}/mise (Buildkite hosted agent cache volume)" <<< "${output}"
  grep -F "export MISE_DATA_DIR=${hosted_cache_root}/mise" "${BUILDKITE_ENV_FILE}"
  grep -F "export GOCACHE=${hosted_cache_root}/setup-go/go/build" "${BUILDKITE_ENV_FILE}"
  grep -F "export GOLANGCI_LINT_CACHE=${hosted_cache_root}/setup-go/golangci-lint" "${BUILDKITE_ENV_FILE}"
}

@test "preserves golangci-lint cache when already set" {
  export BUILDKITE_PLUGIN_SETUP_GO_VERSION="1.24.0"
  export GOLANGCI_LINT_CACHE="${TEST_TMPDIR}/custom-golangci-lint-cache"

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  grep -F "Using golangci-lint cache: ${TEST_TMPDIR}/custom-golangci-lint-cache (GOLANGCI_LINT_CACHE environment variable)" <<< "${output}"
  grep -F "export GOLANGCI_LINT_CACHE=${TEST_TMPDIR}/custom-golangci-lint-cache" "${BUILDKITE_ENV_FILE}"
}

@test "fails when no version source exists" {
  run bash hooks/pre-command

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Could not determine Go version"* ]]
}

@test "installs mise without leaking cleanup trap state" {
  export BUILDKITE_PLUGIN_SETUP_GO_VERSION="1.24.0"
  rm -f "${MISE_DATA_DIR}/bin/mise"
  setup_install_mocks

  run bash hooks/pre-command

  [ "${status}" -eq 0 ]
  [ -x "${MISE_DATA_DIR}/bin/mise" ]
  [[ "${output}" != *"archive: unbound variable"* ]]
}
