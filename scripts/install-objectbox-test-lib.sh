#!/usr/bin/env bash
# Downloads the ObjectBox C library that `flutter test` loads from lib/libobjectbox.so (gitignored).
# The version comes from the resolved objectbox_flutter_libs package so tests run the same library the app bundles.
set -euo pipefail

cd "$(dirname "$0")/.."

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) arch=x64 ;;
  Linux-aarch64 | Linux-arm64) arch=aarch64 ;;
  *) echo "Unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

libs_root=$(jq -r '.packages[] | select(.name == "objectbox_flutter_libs") | .rootUri' .dart_tool/package_config.json)
libs_root=${libs_root#file://}
version=$(sed -n 's/^[[:space:]]*set(OBJECTBOX_VERSION \([^)]*\)).*/\1/p' "$libs_root/linux/CMakeLists.txt")
[[ -n $version ]] || { echo "OBJECTBOX_VERSION not found in $libs_root/linux/CMakeLists.txt" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
curl -fsSL "https://github.com/objectbox/objectbox-c/releases/download/v$version/objectbox-linux-$arch.tar.gz" \
  | tar -xz -C "$tmp"
cp "$tmp/lib/libobjectbox.so" lib/libobjectbox.so
echo "Installed ObjectBox $version to lib/libobjectbox.so"
