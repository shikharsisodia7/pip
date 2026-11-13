#!/usr/bin/env bash
# Fails if tracked files contain anything that must never be public:
# key-like strings, env files, internal planning notes, audio, or local user paths.
set -uo pipefail

fail=0
report() { echo "check-public: $1"; fail=1; }

tracked=$(git ls-files)

if echo "$tracked" | grep -E '^docs/internal/' >/dev/null; then
  report "files under docs/internal/ are tracked"
fi

if echo "$tracked" | grep -Ei '\.(wav|mp3|webm|m4a|ogg|flac)$' >/dev/null; then
  report "audio files are tracked"
fi

if echo "$tracked" | grep -E '(^|/)\.env' | grep -v '\.env\.example$' >/dev/null; then
  report "an env file other than .env.example is tracked"
fi

if echo "$tracked" | grep -E '^(\.cache(/|$)|\.superset/)' >/dev/null; then
  report ".cache or local tooling config is tracked"
fi

if echo "$tracked" | grep -E '(\.xcodeproj/|(^|/)Local\.xcconfig$|(^|/)xcuserdata/)' >/dev/null; then
  report "generated Xcode project or local signing config is tracked"
fi

if git grep -nIE '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]+' -- 'ios/'; then
  report "a development team id is tracked"
fi

# No real key, token or voice id from a local .env.local may appear in a tracked file.
# Values are compared silently; only the variable name is reported.
if [ -f .env.local ]; then
  while IFS='=' read -r name value; do
    case "$name" in *KEY*|*TOKEN*|*SECRET*|*VOICE_ID*) ;; *) continue ;; esac
    value="${value%\"}"; value="${value#\"}"
    [ "${#value}" -ge 12 ] || continue
    if git grep -qIF -e "$value" -- . 2>/dev/null; then
      report "the value of $name from .env.local appears in a tracked file"
    fi
  done < .env.local
fi

patterns=(
  '\bsk[-_][A-Za-z0-9_-]{20,}'
  'xi-api-key:[[:space:]]*["'"'"']?[A-Za-z0-9_]{20,}'
  '^[A-Z_]*_API_KEY=[^[:space:]]+'
  '^PIP_VOICE_ID=[^[:space:]]+'
  '/Users/[A-Za-z0-9._-]+/'
  '/home/[A-Za-z0-9._-]+/'
)
for p in "${patterns[@]}"; do
  if git grep -nIE "$p" -- . ':!scripts/check-public.sh' ':!package-lock.json'; then
    report "tracked file matches forbidden pattern: $p"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "check-public: FAILED"
  exit 1
fi
echo "check-public: ok"
