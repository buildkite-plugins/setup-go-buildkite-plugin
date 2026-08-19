#!/usr/bin/env bash

setup_go_cache_enabled() {
  [ "$(plugin_cfg_default cache false)" = "true" ]
}

setup_go_cache_yaml_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\'}"
}

setup_go_cache_dependency_paths() {
  local base_var="BUILDKITE_PLUGIN_SETUP_GO_CACHE_DEPENDENCY_PATH"
  local index=0
  local indexed_var
  local value

  value="$(plugin_cfg cache-dependency-path)"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return
  fi

  while :; do
    indexed_var="${base_var}_${index}"
    if [ -z "${!indexed_var+x}" ]; then
      break
    fi
    printf '%s\n' "${!indexed_var}"
    index=$((index + 1))
  done

  if [ "$index" -gt 0 ]; then
    return
  fi

  # WORKING_DIRECTORY is resolved by the pre-command hook before this function runs.
  # shellcheck disable=SC2153
  if [ -f "${WORKING_DIRECTORY}/go.work.sum" ]; then
    printf '%s\n' "go.work.sum"
  elif [ -f "${WORKING_DIRECTORY}/go.sum" ]; then
    printf '%s\n' "go.sum"
  elif [ -f "${WORKING_DIRECTORY}/go.work" ]; then
    printf '%s\n' "go.work"
  else
    printf '%s\n' "go.mod"
  fi
}

setup_go_cache_checksum_yaml() {
  local path
  local separator=""

  printf '['
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s' "$separator"
    setup_go_cache_yaml_quote "$path"
    separator=", "
  done < <(setup_go_cache_dependency_paths)
  printf ']'
}

setup_go_cache_write_config() {
  local config_file="$1"
  local checksum_yaml

  checksum_yaml="$(setup_go_cache_checksum_yaml)"

  cat > "$config_file" <<YAML
caches:
  - name: setup-go-modules
    cache_key:
      - setup-go-modules-v1
      - { agent: os }
      - { agent: arch }
      - { env: SETUP_GO_CACHE_VERSION, fallback_limit: true }
      - { checksum: ${checksum_yaml} }
    target_paths:
      - $(setup_go_cache_yaml_quote "$GO_MOD_CACHE_DIR")

  - name: setup-go-build
    cache_key:
      - setup-go-build-v1
      - { agent: os }
      - { agent: arch }
      - { env: SETUP_GO_CACHE_VERSION, fallback_limit: true }
      - { checksum: ${checksum_yaml} }
      - { agent: branch }
      - { env: BUILDKITE_COMMIT }
    target_paths:
      - $(setup_go_cache_yaml_quote "$GO_BUILD_CACHE_DIR")
YAML
}

setup_go_cache_annotate_failure() {
  local operation="$1"
  local agent_binary="$2"
  local context="setup-go-cache-${BUILDKITE_JOB_ID:-local}"

  if [ "$(plugin_cfg_default cache-annotations true)" != "true" ]; then
    return
  fi

  printf '%s\n' \
    "⚠️ setup-go could not ${operation} Buildkite Cache." \
    "The command continued without the cache. This may indicate that Cache is unavailable or that the registry policy denied the operation." |
    "$agent_binary" annotate --style warning --context "$context" >/dev/null 2>&1 || true
}

setup_go_cache_execute() (
  local operation="$1"
  local config_file
  local working_directory
  local registry
  local agent_binary

  working_directory="$(plugin_cfg dir)"
  working_directory="${working_directory:-${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}}"
  WORKING_DIRECTORY="$working_directory"
  GO_MOD_CACHE_DIR="${GOMODCACHE:?GOMODCACHE is required for Buildkite Cache}"
  GO_BUILD_CACHE_DIR="${GOCACHE:?GOCACHE is required for Buildkite Cache}"
  registry="$(plugin_cfg_default cache-registry '~')"
  agent_binary="${BUILDKITE_AGENT_BINARY_PATH:-buildkite-agent}"

  umask 077
  config_file="$(mktemp "${TMPDIR:-/tmp}/setup-go-cache.XXXXXX")"
  trap 'rm -f "$config_file"' EXIT
  setup_go_cache_write_config "$config_file"

  cd "$working_directory" || exit
  "$agent_binary" cache "$operation" \
    --cache-config-file "$config_file" \
    --registry "$registry" \
    --name setup-go-modules \
    --name setup-go-build
)

setup_go_cache_run() {
  local operation="$1"
  local agent_binary="${BUILDKITE_AGENT_BINARY_PATH:-buildkite-agent}"

  if setup_go_cache_execute "$operation"; then
    return
  fi

  echo "^^^ +++"
  echo ":warning: setup-go Buildkite Cache ${operation} failed"
  setup_go_cache_annotate_failure "$operation" "$agent_binary"

  if [ "$(plugin_cfg_default cache-fail-on-error false)" = "true" ]; then
    return 1
  fi
}
