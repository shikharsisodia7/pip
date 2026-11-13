#!/usr/bin/env bash
set -euo pipefail
ROOT="${SUPERSET_ROOT_PATH:-$(cd "$(git rev-parse --git-common-dir)/.." && pwd)}"
[ -f "$ROOT/.env.local" ] && cp "$ROOT/.env.local" .env.local
[ -d "$ROOT/docs/internal" ] && mkdir -p docs && cp -R "$ROOT/docs/internal" docs/
mkdir -p "$ROOT/.cache" && ln -sfn "$ROOT/.cache" .cache
npm ci --prefer-offline --no-audit --no-fund
