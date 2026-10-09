#!/usr/bin/env bash
# Build the site and deploy dist/ to the Cloudflare Pages project "tabbi".
# Needs `npx wrangler login` once. See README.md.
set -euo pipefail

cd "$(dirname "$0")"
python3 build.py
npx wrangler pages deploy dist --project-name=tabbi --branch=main --commit-dirty=true
