#!/usr/bin/env bash
set -euo pipefail

DEFAULT_RELEASE_REPOSITORY="applied-ai-consulting/oriental"
DEFAULT_RELEASE_VERSION="latest"
DEFAULT_AGENT_RELEASE_TAG_PREFIX="agents/opsrabbit-vision/v"
DEFAULT_ASSET_NAME=""
DEFAULT_DEVICE_ID="pi5-belt-line-1"
DEFAULT_PLUGIN_ID="conveyor-vision"
DEFAULT_DATA_DIR="/var/lib/opsrabbit-vision"
DEFAULT_CONFIG_PATH="/etc/opsrabbit-vision/vision-agent.toml"
DEFAULT_CREDENTIAL_PATH="/etc/opsrabbit-vision/device-token.json"
DEFAULT_MODEL_RELEASE_REPOSITORY="applied-ai-consulting/oriental"
DEFAULT_MODEL_RELEASE_VERSION="models/smoke-test-yolov8n-coco/v1.0.0"
DEFAULT_MODEL_MANIFEST_ASSET_NAME="model-manifest.json"
DEFAULT_MODEL_HEF_ASSET_NAME="smoke-test-yolov8n-coco-1.0.0.hef"

release_repository="${OPSRABBIT_VISION_RELEASE_REPOSITORY:-${DEFAULT_RELEASE_REPOSITORY}}"
release_version="${OPSRABBIT_VISION_RELEASE_VERSION:-${DEFAULT_RELEASE_VERSION}}"
asset_name="${OPSRABBIT_VISION_ASSET_NAME:-${DEFAULT_ASSET_NAME}}"
model_release_repository="${OPSRABBIT_VISION_MODEL_RELEASE_REPOSITORY:-${DEFAULT_MODEL_RELEASE_REPOSITORY}}"
model_release_version="${OPSRABBIT_VISION_MODEL_RELEASE_VERSION:-${DEFAULT_MODEL_RELEASE_VERSION}}"
model_manifest_asset_name="${OPSRABBIT_VISION_MODEL_MANIFEST_ASSET_NAME:-${DEFAULT_MODEL_MANIFEST_ASSET_NAME}}"
model_hef_asset_name="${OPSRABBIT_VISION_MODEL_HEF_ASSET_NAME:-${DEFAULT_MODEL_HEF_ASSET_NAME}}"
device_id="${OPSRABBIT_VISION_DEVICE_ID:-}"
base_url="${OPSRABBIT_VISION_BASE_URL:-}"
plugin_id="${OPSRABBIT_VISION_PLUGIN_ID:-${DEFAULT_PLUGIN_ID}}"
data_dir="${OPSRABBIT_VISION_DATA_DIR:-${DEFAULT_DATA_DIR}}"
github_token_file="${OPSRABBIT_VISION_GITHUB_TOKEN_FILE:-}"
device_token_file="${OPSRABBIT_VISION_DEVICE_TOKEN_FILE:-}"
non_interactive="false"
install_hailo="prompt"
start_service="true"
run_preflight="true"
force_configure="false"
install_model="prompt"
cleanup_dir=""

usage() {
  cat <<'USAGE'
Install the OpsRabbit Vision Agent on Raspberry Pi OS.

Usage:
  curl -fsSL https://raw.githubusercontent.com/applied-ai-consulting/opsrabbit-vision-agent-installer/main/install.sh | sudo bash

Options:
  --release-repository OWNER/REPO     GitHub repo containing the private release asset.
  --release-version VERSION|latest    Release tag to download. Defaults to latest agents/opsrabbit-vision/v* release.
  --asset-name NAME                   Debian asset name in the release. Defaults to opsrabbit-vision-agent_VERSION_arm64.deb.
  --model-release-repository OWNER/REPO
                                      Optional GitHub repo containing model release assets.
  --model-release-version VERSION|latest
                                      Model release tag to download. Defaults to models/smoke-test-yolov8n-coco/v1.0.0.
  --model-manifest-asset-name NAME    Model manifest asset name. Defaults to model-manifest.json.
  --model-hef-asset-name NAME         Hailo HEF model asset name to install. Defaults to smoke-test-yolov8n-coco-1.0.0.hef.
  --install-model yes|no|prompt       Download/install model after agent configuration.
  --skip-model-install                Alias for --install-model no, useful when rerunning after a model was already installed.
  --device-id ID                      Registered Conveyor Vision device id.
  --base-url URL                      OpsRabbit backend base URL reachable from the Pi.
  --plugin-id ID                      OpsRabbit plugin id. Defaults to conveyor-vision.
  --data-dir PATH                     Agent spool/data directory.
  --github-token-file PATH            File containing GitHub token for private release asset download.
  --device-token-file PATH            File containing OpsRabbit plugin/device API token.
  --install-hailo yes|no|prompt       Install Raspberry Pi hailo-all package.
  --skip-preflight                    Configure/install without running preflight.
  --no-start                          Do not enable/start the systemd service.
  --force-configure                   Replace existing config/credential files after backing them up.
  --non-interactive                   Do not prompt; required values must come from options/env.
  -h, --help                          Show this help.

Environment variables mirror the long option names with OPSRABBIT_VISION_*
prefixes, for example OPSRABBIT_VISION_BASE_URL.

Security model:
  S3 credentials are configured in OpsRabbit/Conveyor Vision, not on the Pi.
  Model releases can be private; the GitHub token is used only for downloads.
  The agent receives short-lived upload authorizations from OpsRabbit and
  stores only its device API token locally.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-repository) release_repository="${2:?}"; shift 2 ;;
    --release-version) release_version="${2:?}"; shift 2 ;;
    --asset-name) asset_name="${2:?}"; shift 2 ;;
    --model-release-repository) model_release_repository="${2:?}"; shift 2 ;;
    --model-release-version) model_release_version="${2:?}"; shift 2 ;;
    --model-manifest-asset-name) model_manifest_asset_name="${2:?}"; shift 2 ;;
    --model-hef-asset-name) model_hef_asset_name="${2:?}"; shift 2 ;;
    --install-model) install_model="${2:?}"; shift 2 ;;
    --skip-model-install) install_model="no"; shift ;;
    --device-id) device_id="${2:?}"; shift 2 ;;
    --base-url) base_url="${2:?}"; shift 2 ;;
    --plugin-id) plugin_id="${2:?}"; shift 2 ;;
    --data-dir) data_dir="${2:?}"; shift 2 ;;
    --github-token-file) github_token_file="${2:?}"; shift 2 ;;
    --device-token-file) device_token_file="${2:?}"; shift 2 ;;
    --install-hailo) install_hailo="${2:?}"; shift 2 ;;
    --skip-preflight) run_preflight="false"; shift ;;
    --no-start) start_service="false"; shift ;;
    --force-configure) force_configure="true"; shift ;;
    --non-interactive) non_interactive="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;34m[opsrabbit-vision]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[opsrabbit-vision]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[opsrabbit-vision]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root, for example: curl -fsSL .../install.sh | sudo bash"
  fi
}

need_interactive() {
  if [[ "${non_interactive}" == "true" ]]; then
    fail "$1 is required in --non-interactive mode"
  fi
  if ! { true </dev/tty; } 2>/dev/null; then
    fail "An interactive terminal is required. Run from SSH or pass non-interactive options/files."
  fi
}

prompt_text() {
  local var_name="$1"
  local prompt="$2"
  local default="${3:-}"
  local current="${!var_name:-}"
  if [[ -n "${current}" ]]; then return; fi
  need_interactive "${prompt}"
  local answer
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " answer </dev/tty
    printf -v "${var_name}" '%s' "${answer:-${default}}"
  else
    read -r -p "${prompt}: " answer </dev/tty
    [[ -n "${answer}" ]] || fail "${prompt} cannot be empty"
    printf -v "${var_name}" '%s' "${answer}"
  fi
}

read_secret() {
  local prompt="$1"
  local file="$2"
  local value
  if [[ -n "${file}" ]]; then
    [[ -f "${file}" ]] || fail "Secret file not found: ${file}"
    value="$(tr -d '\r\n' <"${file}")"
    [[ -n "${value}" ]] || fail "Secret file is empty: ${file}"
    printf '%s' "${value}"
    return
  fi
  need_interactive "${prompt}"
  read -r -s -p "${prompt}: " value </dev/tty
  printf '\n' >/dev/tty
  [[ -n "${value}" ]] || fail "${prompt} cannot be empty"
  printf '%s' "${value}"
}

validate_inputs() {
  command -v curl >/dev/null 2>&1 || fail "curl is required"
  command -v python3 >/dev/null 2>&1 || fail "python3 is required"
  command -v apt-get >/dev/null 2>&1 || fail "This installer currently supports Debian/Raspberry Pi OS systems with apt-get"
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || true)"
  [[ "${arch}" == "arm64" ]] || fail "This package is arm64-only; detected architecture: ${arch:-unknown}"
  [[ "${release_repository}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "Invalid --release-repository"
  if [[ -n "${asset_name}" ]]; then
    [[ "${asset_name}" =~ ^[A-Za-z0-9_.+-]+\.deb$ ]] || fail "Asset name must be a .deb filename"
  fi
  if [[ -n "${model_release_repository}" ]]; then
    [[ "${model_release_repository}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "Invalid --model-release-repository"
  fi
  [[ "${model_manifest_asset_name}" =~ ^[A-Za-z0-9_.+-]+\.json$ ]] || fail "Model manifest asset name must be a .json filename"
  if [[ -n "${model_hef_asset_name}" ]]; then
    [[ "${model_hef_asset_name}" =~ ^[A-Za-z0-9_.+-]+\.hef$ ]] || fail "Model HEF asset name must be a .hef filename"
  fi
  [[ "${device_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$ ]] || fail "Invalid device id"
  [[ "${plugin_id}" =~ ^[a-z][a-z0-9-]{0,79}$ ]] || fail "Invalid plugin id"
  [[ "${base_url}" =~ ^https?://[^[:space:]]+$ ]] || fail "Base URL must start with http:// or https://"
  [[ "${data_dir}" = /* ]] || fail "Data directory must be an absolute path"
  case "${install_hailo}" in yes|no|prompt) ;; *) fail "--install-hailo must be yes, no, or prompt" ;; esac
  case "${install_model}" in yes|no|prompt) ;; *) fail "--install-model must be yes, no, or prompt" ;; esac
}

github_api() {
  local github_token="$1"
  shift
  curl --fail --silent --show-error \
    -H "Authorization: Bearer ${github_token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

derive_agent_asset_name() {
  local version_tag="$1"
  local semantic_version="${version_tag#${DEFAULT_AGENT_RELEASE_TAG_PREFIX}}"
  [[ "${semantic_version}" != "${version_tag}" ]] || fail "Cannot derive Debian asset name from non-agent release tag: ${version_tag}"
  [[ "${semantic_version}" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-.+][A-Za-z0-9_.+-]+)?$ ]] || fail "Cannot derive Debian asset name from invalid semantic version: ${semantic_version}"
  printf 'opsrabbit-vision-agent_%s_arm64.deb' "${semantic_version}"
}

resolve_latest_agent_release() {
  local github_token="$1"
  local repository="$2"
  log "Resolving latest OpsRabbit Vision Agent release from ${repository}..." >&2
  local metadata
  metadata="$(github_api "${github_token}" "https://api.github.com/repos/${repository}/releases?per_page=100")"
  METADATA="${metadata}" PREFIX="${DEFAULT_AGENT_RELEASE_TAG_PREFIX}" python3 - <<'PY'
import json
import os
import re

prefix = os.environ["PREFIX"]
releases = json.loads(os.environ["METADATA"])

def semver_key(tag_name: str):
    version = tag_name[len(prefix):]
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$", version)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())

candidates = []
for release in releases:
    tag_name = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease"):
        continue
    if not tag_name.startswith(prefix):
        continue
    key = semver_key(tag_name)
    if key is not None:
        candidates.append((key, tag_name))

if not candidates:
    raise SystemExit(f"no non-draft, non-prerelease agent releases found with tag prefix {prefix}")

print(max(candidates)[1])
PY
}

resolve_agent_release_inputs() {
  local github_token="$1"
  if [[ "${release_version}" == "latest" ]]; then
    release_version="$(resolve_latest_agent_release "${github_token}" "${release_repository}")"
    log "Latest OpsRabbit Vision Agent release is ${release_version}."
  fi
  if [[ -z "${asset_name}" ]]; then
    asset_name="$(derive_agent_asset_name "${release_version}")"
    log "Using derived Debian asset name ${asset_name}."
  fi
  [[ "${asset_name}" =~ ^[A-Za-z0-9_.+-]+\.deb$ ]] || fail "Asset name must be a .deb filename"
}

download_release_asset() {
  local github_token="$1"
  local output_path="$2"
  local repository="${3:-${release_repository}}"
  local version="${4:-${release_version}}"
  local name="${5:-${asset_name}}"
  local metadata_url
  if [[ "${version}" == "latest" ]]; then
    metadata_url="https://api.github.com/repos/${repository}/releases/latest"
  else
    metadata_url="https://api.github.com/repos/${repository}/releases/tags/${version}"
  fi

  log "Resolving ${name} from ${repository} release ${version}..."
  local metadata asset_id checksum_id
  metadata="$(github_api "${github_token}" "${metadata_url}")"
  asset_id="$(METADATA="${metadata}" python3 - "${name}" <<'PY'
import json, sys
asset_name = sys.argv[1]
import os
release = json.loads(os.environ["METADATA"])
for asset in release.get("assets", []):
    if asset.get("name") == asset_name:
        print(asset["id"])
        break
else:
    raise SystemExit(f"release asset not found: {asset_name}")
PY
)"
  checksum_id="$(METADATA="${metadata}" python3 - "${name}" <<'PY' || true
import json, sys
import os
asset_name = sys.argv[1]
release = json.loads(os.environ["METADATA"])
preferred = f"{asset_name}.sha256"
checksum_assets = []
for asset in release.get("assets", []):
    name = asset.get("name")
    if name == preferred:
        print(asset["id"])
        raise SystemExit(0)
    if name and name.endswith("SHA256SUMS"):
        checksum_assets.append(asset)
if checksum_assets:
    print(checksum_assets[0]["id"])
PY
)"

  log "Downloading ${name}..."
  curl --fail --silent --show-error --location \
    -H "Authorization: Bearer ${github_token}" \
    -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/${repository}/releases/assets/${asset_id}" \
    -o "${output_path}"

  if [[ -n "${checksum_id}" ]]; then
    log "Downloading checksum asset and verifying ${name}..."
    curl --fail --silent --show-error --location \
      -H "Authorization: Bearer ${github_token}" \
      -H "Accept: application/octet-stream" \
      "https://api.github.com/repos/${repository}/releases/assets/${checksum_id}" \
      -o "${output_path}.sha256"
    if grep -F -q "$(basename "${output_path}")" "${output_path}.sha256"; then
      (cd "$(dirname "${output_path}")" && sha256sum --check --ignore-missing "$(basename "${output_path}.sha256")")
    else
      warn "Checksum asset did not contain ${name}; continuing without release checksum verification for this asset."
    fi
  else
    warn "No checksum release asset found for ${name}; continuing without release checksum verification."
  fi
}

install_model_assets() {
  local github_token="$1"
  local temporary_dir="$2"
  local should_install="${install_model}"
  if [[ "${should_install}" == "prompt" ]]; then
    if [[ "${non_interactive}" == "true" ]]; then
      should_install="no"
    else
      local answer
      read -r -p "Download and install a Hailo model now? [y/N]: " answer </dev/tty
      case "${answer}" in y|Y|yes|YES) should_install="yes" ;; *) should_install="no" ;; esac
    fi
  fi
  if [[ "${should_install}" != "yes" ]]; then
    warn "Model install skipped. Run opsrabbit-vision model-install before starting a real inspection."
    return
  fi
  prompt_text model_release_repository "Model release repository" "${DEFAULT_MODEL_RELEASE_REPOSITORY}"
  prompt_text model_release_version "Model release version/tag" "${DEFAULT_MODEL_RELEASE_VERSION}"
  prompt_text model_manifest_asset_name "Model manifest asset name" "${DEFAULT_MODEL_MANIFEST_ASSET_NAME}"
  prompt_text model_hef_asset_name "Model HEF asset name" "${DEFAULT_MODEL_HEF_ASSET_NAME}"
  validate_inputs

  local model_dir manifest_path hef_path
  model_dir="${temporary_dir}/model"
  mkdir -p "${model_dir}"
  manifest_path="${model_dir}/${model_manifest_asset_name}"
  hef_path="${model_dir}/${model_hef_asset_name}"

  download_release_asset \
    "${github_token}" \
    "${manifest_path}" \
    "${model_release_repository}" \
    "${model_release_version}" \
    "${model_manifest_asset_name}"
  download_release_asset \
    "${github_token}" \
    "${hef_path}" \
    "${model_release_repository}" \
    "${model_release_version}" \
    "${model_hef_asset_name}"

  log "Installing immutable Hailo model into the agent registry..."
  /opt/opsrabbit-vision/venv/bin/opsrabbit-vision model-install \
    --config "${DEFAULT_CONFIG_PATH}" \
    --manifest "${manifest_path}" \
    --artifact "${hef_path}"
}

install_system_packages() {
  log "Installing Raspberry Pi OS dependencies..."
  apt-get update
  apt-get install -y ca-certificates curl python3 python3-picamera2 python3-pil

  local should_install_hailo="${install_hailo}"
  if [[ "${should_install_hailo}" == "prompt" ]]; then
    if [[ "${non_interactive}" == "true" ]]; then
      should_install_hailo="no"
    else
      local answer
      read -r -p "Install Raspberry Pi hailo-all package if available? [Y/n]: " answer </dev/tty
      case "${answer}" in n|N|no|NO) should_install_hailo="no" ;; *) should_install_hailo="yes" ;; esac
    fi
  fi
  if [[ "${should_install_hailo}" == "yes" ]]; then
    apt-get install -y hailo-all || warn "hailo-all install failed or is unavailable; install Hailo AI Kit packages manually before live inference."
  fi
}

backup_if_needed() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    if [[ "${force_configure}" != "true" ]]; then
      fail "${path} already exists. Re-run with --force-configure to back it up and replace it."
    fi
    local backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
    log "Backing up ${path} to ${backup}"
    mv "${path}" "${backup}"
  fi
}

configure_agent() {
  local device_token="$1"
  local token_temp="/root/vision-agent-token.txt"
  local custom_data_dir_args=()
  local systemd_override="/etc/systemd/system/opsrabbit-vision.service.d/storage.conf"

  install -m 0600 /dev/null "${token_temp}"
  printf '%s' "${device_token}" >"${token_temp}"

  backup_if_needed "${DEFAULT_CONFIG_PATH}"
  backup_if_needed "${DEFAULT_CREDENTIAL_PATH}"
  if [[ "${data_dir}" != "${DEFAULT_DATA_DIR}" ]]; then
    mkdir -p "$(dirname "${systemd_override}")" "${data_dir}"
    custom_data_dir_args=(--data-dir "${data_dir}" --systemd-override-output "${systemd_override}")
  else
    mkdir -p "${data_dir}"
  fi

  log "Generating Vision Agent configuration..."
  /opt/opsrabbit-vision/venv/bin/opsrabbit-vision configure \
    --output "${DEFAULT_CONFIG_PATH}" \
    --credential-output "${DEFAULT_CREDENTIAL_PATH}" \
    --device-id "${device_id}" \
    --base-url "${base_url}" \
    --plugin-id "${plugin_id}" \
    --api-token-file "${token_temp}" \
    "${custom_data_dir_args[@]}"

  rm -f "${token_temp}"
  chown root:opsrabbit-vision "${DEFAULT_CONFIG_PATH}"
  chmod 0640 "${DEFAULT_CONFIG_PATH}"
  chown opsrabbit-vision:opsrabbit-vision "${DEFAULT_CREDENTIAL_PATH}"
  chown -R opsrabbit-vision:opsrabbit-vision "${data_dir}"

  if [[ "${base_url}" == http://* ]]; then
    log "Disabling TLS verification in config because base URL uses http://"
    python3 - "${DEFAULT_CONFIG_PATH}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("verify_tls = true", "verify_tls = false")
path.write_text(text)
PY
  fi
}

run_agent_preflight() {
  log "Running preflight..."
  runuser -u opsrabbit-vision -- /opt/opsrabbit-vision/venv/bin/opsrabbit-vision preflight \
    --config "${DEFAULT_CONFIG_PATH}"
}

enable_service() {
  log "Enabling and starting systemd service..."
  systemctl daemon-reload
  systemctl enable --now opsrabbit-vision
  systemctl status opsrabbit-vision --no-pager || true
}

main() {
  require_root
  prompt_text device_id "Vision device id" "${DEFAULT_DEVICE_ID}"
  prompt_text base_url "OpsRabbit backend base URL reachable from this Pi"
  validate_inputs

  cat <<'NOTICE'

Object-store/S3 note:
  Do NOT install AWS credentials on this Raspberry Pi for normal operation.
  Configure S3/object storage in OpsRabbit / the Conveyor Vision plugin.
  The Vision Agent uploads images and video using short-lived upload
  authorizations issued by OpsRabbit, while retaining evidence locally until
  remote verification succeeds.

NOTICE
  if [[ "${non_interactive}" != "true" ]]; then
    read -r -p "Have you configured S3/object storage in OpsRabbit? [Y/n]: " object_store_ready </dev/tty
    case "${object_store_ready}" in
      n|N|no|NO)
        warn "Continuing, but evidence uploads will not complete until OpsRabbit object storage is configured."
        ;;
    esac
  fi

  local github_token device_token temporary_dir deb_path
  github_token="$(read_secret "GitHub token for release download" "${github_token_file}")"
  device_token="$(read_secret "OpsRabbit Vision device API token" "${device_token_file}")"
  resolve_agent_release_inputs "${github_token}"
  temporary_dir="$(mktemp -d)"
  cleanup_dir="${temporary_dir}"
  trap '[[ -n "${cleanup_dir:-}" ]] && rm -rf "${cleanup_dir}"' EXIT
  deb_path="${temporary_dir}/${asset_name}"

  install_system_packages
  download_release_asset "${github_token}" "${deb_path}"

  log "Installing ${asset_name}..."
  apt-get install -y "${deb_path}"

  configure_agent "${device_token}"
  install_model_assets "${github_token}" "${temporary_dir}"

  if [[ "${run_preflight}" == "true" ]]; then
    run_agent_preflight
  else
    warn "Skipping preflight by request."
  fi

  if [[ "${start_service}" == "true" ]]; then
    enable_service
  else
    warn "Service start skipped. Run: sudo systemctl enable --now opsrabbit-vision"
  fi

  log "Install complete."
  log "Follow logs with: journalctl -u opsrabbit-vision -f"
}

main "$@"
