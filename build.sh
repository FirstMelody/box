#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "${SCRIPT_DIR}"

if ! command -v zip >/dev/null 2>&1; then
  echo "zip command not found" >&2
  exit 1
fi

VERSION=$(awk -F '=' '$1 == "version" { gsub(/\r/, "", $2); print $2; exit }' module.prop)
if [ -z "${VERSION}" ]; then
  echo "failed to read version from module.prop" >&2
  exit 1
fi

OUTPUT="box-${VERSION}.zip"
rm -f "${OUTPUT}"

zip -r -o -X -ll "${OUTPUT}" ./ \
  -x '.git/*' \
  -x '.github/*' \
  -x '.codex_tmp/*' \
  -x 'CHANGELOG.md' \
  -x 'debug/*' \
  -x 'update.json' \
  -x 'build.sh' \
  -x 'build.ps1' \
  -x 'KernelSU_bugreport_*.tar.gz' \
  -x 'LICENSE' \
  -x 'box-*.zip'
