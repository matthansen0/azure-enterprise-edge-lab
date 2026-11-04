#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

npm --prefix apps/api test
node --test scripts/test/*.test.cjs
find scripts infra/hooks -name '*.sh' -exec shellcheck {} +
