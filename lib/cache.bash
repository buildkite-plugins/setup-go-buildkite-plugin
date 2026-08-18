#!/usr/bin/env bash

setup_go_cache_enabled() {
  [ "$(plugin_cfg_default cache false)" = "true" ]
}

setup_go_cache_state_dir() {
  local state_root

  if [ -n "${BUILDKITE_ENV_FILE:-}" ]; then
    state_root="$(dirname "$BUILDKITE_ENV_FILE")"
  else
    state_root="${TMPDIR:-/tmp}"
  fi

  printf '%s/setup-go-buildkite-plugin-%s' "$state_root" "${BUILDKITE_JOB_ID:-local}"
}

setup_go_cache_config_file() {
  printf '%s/cache.yml' "$(setup_go_cache_state_dir)"
}

setup_go_cache_working_directory_file() {
  printf '%s/working-directory' "$(setup_go_cache_state_dir)"
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
  local config_file
  local state_dir
  local checksum_yaml

  state_dir="$(setup_go_cache_state_dir)"
  config_file="$(setup_go_cache_config_file)"
  checksum_yaml="$(setup_go_cache_checksum_yaml)"
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"

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

  printf '%s\n' "$WORKING_DIRECTORY" > "$(setup_go_cache_working_directory_file)"
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

setup_go_cache_run() {
  local operation="$1"
  local config_file
  local working_directory
  local registry
  local agent_binary

  config_file="$(setup_go_cache_config_file)"
  if [ ! -f "$config_file" ]; then
    echo "Buildkite Cache configuration is missing: $config_file" >&2
    return 1
  fi

  working_directory="$(cat "$(setup_go_cache_working_directory_file)")"
  registry="$(plugin_cfg_default cache-registry '~')"
  agent_binary="${BUILDKITE_AGENT_BINARY_PATH:-buildkite-agent}"

  if (
    cd "$working_directory"
    "$agent_binary" cache "$operation" \
      --cache-config-file "$config_file" \
      --registry "$registry" \
      --name setup-go-modules \
      --name setup-go-build
  ); then
    return
  fi

  echo "^^^ +++"
  echo ":warning: setup-go Buildkite Cache ${operation} failed"
  setup_go_cache_annotate_failure "$operation" "$agent_binary"

  if [ "$(plugin_cfg_default cache-fail-on-error false)" = "true" ]; then
    return 1
  fi
}
