#!/usr/bin/env bash
# What CI runs, in the order it runs it. A failure here is a failure there.
#
#   scripts/quality.sh
#
# `mix dialyzer` is not included: it needs a PLT built once and takes minutes,
# so CI runs it as its own job (`types`).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "format"
mix format --check-formatted

echo "compile"
mix compile --warnings-as-errors

echo "credo"
mix credo --strict

echo "test"
mix test

echo "docs"
mix docs
