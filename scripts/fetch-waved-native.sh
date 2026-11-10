#!/usr/bin/env bash
set -euo pipefail

# Downloads and verifies the official lightninglabs/wavelength release binary for every RID
# WavedProcessManager.GetRuntimeIdentifier() can return, and installs it at
# BTCPayServer.Plugins.Wavelength/Native/<rid>/waved - so `dotnet publish` can produce a
# complete, runnable .btcpay without anyone building waved themselves. Run automatically by
# the DownloadWavedNativeForPublish MSBuild target (BTCPayServer.Plugins.Wavelength.csproj)
# before every publish; safe to run directly too.
#
# Skips a RID whose Native/<rid>/waved file already exists, so a developer's own locally-built
# waved - placed there manually, which remains supported and is what this script's own absence
# used to require of everyone - is never overwritten by this script.
#
# The archive and per-binary SHA256 hashes below were copied from the matching entries in
# https://github.com/lightninglabs/wavelength/releases/download/$WAVED_VERSION/manifest-$WAVED_VERSION.txt
# (itself detached-signed by wavelength's release maintainers - see the manifest-*.sig assets
# on the same release) after independently downloading and re-hashing all four archives.
# Pinning the hashes here, rather than fetching and trusting the manifest at publish time, is
# deliberate: a later tampering of a release asset, or a MITM at publish time, is then caught
# against a value reviewed in this script's own PR - not against whatever the attacker also
# controls to serve alongside the tampered binary.
#
# To bump WAVED_VERSION: download manifest-<version>.txt from the new release
# (https://github.com/lightninglabs/wavelength/releases/tag/<version>), copy the
# "<rid-archive>.tar.gz" and "<rid-archive>/waved" hash pairs for each RID into the table
# below, and update WAVED_VERSION and the archive basenames together.
#
# Assumes GNU coreutils (sha256sum) and curl/tar are on PATH, same as this repo's other
# scripts - a plain `brew install coreutils` covers a macOS dev machine missing sha256sum.

WAVED_VERSION="v0.2.1"
WAVELENGTH_REPO="${WAVELENGTH_REPO:-https://github.com/lightninglabs/wavelength}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/BTCPayServer.Plugins.Wavelength/Native"

# rid  archive-basename (without .tar.gz)        archive sha256                                                   waved sha256
ASSETS="
linux-x64   wavelength-linux-amd64-$WAVED_VERSION   7d0d24f7297cf0b87a3eab1eafe2d71535b04daa97bb874c89d3da550aa3737e   f6cec36bcd3fde27c182ad37edfc5913cea3802896bfe8177eb3d312adbe59be
linux-arm64 wavelength-linux-arm64-$WAVED_VERSION   f291caa77e40d035983926d0f39e77032e508dbf4481304e6fe6ab9de9ffe959   23679b8c97c58af064847449366b5f9ef5c77fbb82e738a3b396c2a6bb5be6bd
osx-x64     wavelength-darwin-amd64-$WAVED_VERSION  b502037a48bdf1e3717aa1152f4fb55d6154df3c378b51ff6b5dcb776f568f3a   4102d498e238b7144faf7af9cb02adeaee3c42cc220a7259104da4fc64e5bfc4
osx-arm64   wavelength-darwin-arm64-$WAVED_VERSION  82ef2abd9dc2aa2f8e7964691e5396dfaaf66c877e5a9554616a3adb722e49a6   1f9180f4a09080efe5b613ed2551fa91de6f84f84ced439f8e844ea6388e9b6b
"

verify_sha256() {
  local file="$1" expected="$2" actual
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  if [ "$actual" != "$expected" ]; then
    echo "error: $file: expected sha256 $expected, got $actual" >&2
    exit 1
  fi
}

fetch_rid() {
  local rid="$1" archive_base="$2" archive_sha256="$3" waved_sha256="$4"
  local dest="$NATIVE_DIR/$rid/waved"

  if [ -f "$dest" ]; then
    echo "Skipping $rid: $dest already present."
    return
  fi

  local archive_name="$archive_base.tar.gz"
  local url="$WAVELENGTH_REPO/releases/download/$WAVED_VERSION/$archive_name"
  local work_dir
  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' RETURN

  echo "Fetching $url for $rid..."
  curl -sSL --fail -o "$work_dir/$archive_name" "$url"
  verify_sha256 "$work_dir/$archive_name" "$archive_sha256"

  tar -xzf "$work_dir/$archive_name" -C "$work_dir" "$archive_base/waved"
  verify_sha256 "$work_dir/$archive_base/waved" "$waved_sha256"

  mkdir -p "$NATIVE_DIR/$rid"
  mv "$work_dir/$archive_base/waved" "$dest"
  chmod +x "$dest"
  echo "Installed $dest ($rid, $WAVED_VERSION)."
}

while read -r rid archive_base archive_sha256 waved_sha256; do
  [ -z "$rid" ] && continue
  fetch_rid "$rid" "$archive_base" "$archive_sha256" "$waved_sha256"
done <<< "$ASSETS"
