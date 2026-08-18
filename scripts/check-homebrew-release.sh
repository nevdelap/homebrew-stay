#!/usr/bin/env bash

set -euo pipefail
umask 022

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -c safe.directory='*' -C "$script_dir" rev-parse --show-toplevel)"
formula_source_path="$repo_root/Formula/stay.rb"
log_path="$repo_root/.homebrew-release-check.log"
in_homebrew_container=false

case "${1:-}" in
  '') ;;
  --in-homebrew-container) in_homebrew_container=true ;;
  *)
    printf 'Usage: %s\n' "${BASH_SOURCE[0]} [--in-homebrew-container]" >&2
    exit 2
    ;;
esac

if [[ "$in_homebrew_container" == false ]]; then
  exec > >(tee "$log_path") 2>&1
fi

printf 'Logging this check to %s\n' "$log_path"

if [[ ! -f "$formula_source_path" ]]; then
  printf 'Formula not found: %s\n' "$formula_source_path" >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1 &&
   [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  container_runtime=""
  if command -v podman >/dev/null 2>&1; then
    container_runtime="$(command -v podman)"
  elif command -v docker >/dev/null 2>&1; then
    container_runtime="$(command -v docker)"
  fi

  if [[ -n "$container_runtime" && "$in_homebrew_container" == false ]]; then
    container_image="${HOMEBREW_CHECK_CONTAINER_IMAGE:-ubuntu:26.04}"
    host_uid="$(id -u)"
    host_gid="$(id -g)"
    printf '%s\n' \
      "Homebrew is unavailable; running the checks in $container_runtime." \
      "Using the minimal container image: $container_image."
    exec "$container_runtime" run --rm --init --interactive \
      --env "HOMEBREW_CHECK_HOST_UID=$host_uid" \
      --env "HOMEBREW_CHECK_HOST_GID=$host_gid" \
      --volume "$repo_root:/workspace" \
      --workdir /workspace \
      "$container_image" \
      bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail

host_uid="${HOMEBREW_CHECK_HOST_UID:?}"
host_gid="${HOMEBREW_CHECK_HOST_GID:?}"
export DEBIAN_FRONTEND=noninteractive

printf '%s\n' 'Bootstrapping the Ubuntu Homebrew check container ...'
apt-get update
apt-get install --yes --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  file \
  git \
  procps \
  sudo

if [[ "$host_uid" == 0 ]]; then
  printf '%s\n' 'Run this checker as a non-root host user.' >&2
  exit 1
fi

if getent passwd "$host_uid" >/dev/null 2>&1; then
  check_user="$(getent passwd "$host_uid" | cut -d: -f1)"
else
  if getent group "$host_gid" >/dev/null 2>&1; then
    check_group="$(getent group "$host_gid" | cut -d: -f1)"
  else
    check_group=homebrewcheck
    groupadd --gid "$host_gid" "$check_group"
  fi
  check_user=homebrewcheck
  useradd --uid "$host_uid" --gid "$check_group" \
    --create-home --shell /bin/bash "$check_user"
fi

printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$check_user" \
  >/etc/sudoers.d/homebrewcheck
chmod 0440 /etc/sudoers.d/homebrewcheck

su --login "$check_user" --command '
  set -euo pipefail
  export NONINTERACTIVE=1
  /bin/bash -c "$(curl --fail --silent --show-error --location \
    https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  cd /workspace
  exec ./scripts/check-homebrew-release.sh --in-homebrew-container
'
CONTAINER_SCRIPT
    exit $?
  fi

  printf '%s\n' \
    'Homebrew is not installed or on PATH, and no Podman/Docker runtime was found.' \
    'On NixOS, make Podman available with `nix shell nixpkgs#podman` and rerun this script.' >&2
  exit 1
fi

cd "$repo_root"

printf '%s\n' 'Checking the release patch ...'
git -c safe.directory="$repo_root" diff --check

release_check_failed() {
  printf 'Release metadata check failed: %s\n' "$1" >&2
  exit 1
}

formula_versions=()
while IFS= read -r formula_version; do
  formula_versions[${#formula_versions[@]}]="$formula_version"
done < <(
  sed -nE 's#.*releases/download/v([^/]+)/.*#\1#p' \
    Formula/stay.rb
)
if (( ${#formula_versions[@]} != 4 )); then
  release_check_failed 'expected four formula release URLs'
fi

release_version="${formula_versions[0]}"
if [[ ! "$release_version" =~ ^[0-9]+(\.[0-9]+)+([.-][0-9A-Za-z.-]+)?$ ]]; then
  release_check_failed "invalid formula release version: $release_version"
fi
for formula_version in "${formula_versions[@]}"; do
  if [[ "$formula_version" != "$release_version" ]]; then
    release_check_failed 'formula URLs use different release versions'
  fi
done

formula_assets=()
while IFS= read -r formula_asset; do
  formula_assets[${#formula_assets[@]}]="$formula_asset"
done < <(
  sed -nE 's#.*releases/download/v[^/]+/(stay-v[^"]+\.tar\.gz)".*#\1#p' \
    Formula/stay.rb
)
formula_checksums=()
while IFS= read -r formula_checksum; do
  formula_checksums[${#formula_checksums[@]}]="$formula_checksum"
done < <(
  sed -nE 's/.*sha256 "([0-9a-f]{64})".*/\1/p' Formula/stay.rb
)
if (( ${#formula_assets[@]} != 4 )); then
  release_check_failed 'expected four formula release assets'
fi
if (( ${#formula_checksums[@]} != 4 )); then
  release_check_failed 'expected four lowercase formula SHA-256 checksums'
fi

ci_assets=()
while IFS= read -r ci_asset; do
  ci_assets[${#ci_assets[@]}]="$ci_asset"
done < <(
  sed -nE 's/^[[:space:]]+asset: (stay-v[^[:space:]]+\.tar\.gz)$/\1/p' \
    .github/workflows/ci.yml
)
ci_checksums=()
while IFS= read -r ci_checksum; do
  ci_checksums[${#ci_checksums[@]}]="$ci_checksum"
done < <(
  sed -nE 's/^[[:space:]]+([0-9a-f]{64})$/\1/p' \
    .github/workflows/ci.yml
)
ci_release_versions=()
while IFS= read -r ci_release_version; do
  ci_release_versions[${#ci_release_versions[@]}]="$ci_release_version"
done < <(
  sed -nE 's/^[[:space:]]*release_url="[^"]*\/v([^"]+)"/\1/p' \
    .github/workflows/ci.yml
)
if (( ${#ci_assets[@]} != 4 )); then
  release_check_failed 'expected four CI release assets'
fi
if (( ${#ci_checksums[@]} != 4 )); then
  release_check_failed 'expected four lowercase CI SHA-256 checksums'
fi
if (( ${#ci_release_versions[@]} != 1 )); then
  release_check_failed 'expected one CI release URL'
fi
if [[ "${ci_release_versions[0]}" != "$release_version" ]]; then
  release_check_failed 'CI release URL version differs from the formula'
fi

for index in "${!formula_assets[@]}"; do
  formula_asset="${formula_assets[$index]}"
  if [[ "$formula_asset" != "stay-v${release_version}-"* ]]; then
    release_check_failed 'formula asset version differs from its URL version'
  fi
  if [[ "$formula_asset" != "${ci_assets[$index]}" ]]; then
    release_check_failed "formula and CI asset differ at index $index"
  fi
  if [[ "${formula_checksums[$index]}" != "${ci_checksums[$index]}" ]]; then
    release_check_failed "formula and CI checksum differ at index $index"
  fi
done

printf 'Release metadata is consistent for v%s.\n' "$release_version"

printf '%s\n' 'Updating Homebrew metadata ...'
brew update
brew tap nevdelap/stay

tap_path="$(brew --repository nevdelap/stay)"
formula_destination_path="$tap_path/Formula/stay.rb"
mkdir -p "$tap_path/Formula"
cp "$formula_source_path" "$formula_destination_path"

printf '%s\n' 'Running Homebrew audit and style checks ...'
brew audit --strict --new --formula nevdelap/stay/stay
brew style --formula nevdelap/stay/stay

printf '%s\n' 'Fetching and verifying the release archive ...'
brew fetch --force --retry nevdelap/stay/stay

if brew list --formula stay >/dev/null 2>&1; then
  printf '%s\n' 'Reinstalling the tested formula ...'
  brew reinstall nevdelap/stay/stay
else
  printf '%s\n' 'Installing the tested formula ...'
  brew install nevdelap/stay/stay
fi

printf '%s\n' 'Running the formula test ...'
brew test nevdelap/stay/stay

printf '%s\n' \
  'Homebrew release checks passed for this host.' \
  'GitHub Actions still provides the macOS and ARM64 coverage.'
