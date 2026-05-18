#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  if [[ "$SOURCE" != /* ]]; then
    SOURCE="$DIR/$SOURCE"
  fi
done

PROJECT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
cd "$PROJECT_DIR"

./run.sh
