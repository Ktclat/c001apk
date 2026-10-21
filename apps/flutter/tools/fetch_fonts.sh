#!/usr/bin/env bash
set -euo pipefail
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$app_dir/assets/fonts"
mkdir -p "$target_dir"
url_base="https://raw.githubusercontent.com/CodePlayer/webfont-noto/7af038d32866b387c64ef8e644abf5c303e48db6/dist/NotoSans/NotoSansCJKsc-hinted/subset/NotoSansCJKsc-hinted-standard"

fetch_font() {
  local name="$1" expected="$2" target="$target_dir/$1" actual temp
  if [[ -f "$target" ]]; then
    actual="$(git hash-object "$target")"
    if [[ "$actual" == "$expected" ]]; then
      echo "Font verified: $name"
      return
    fi
  fi
  temp="$(mktemp "$target_dir/.font.XXXXXXXX")"
  if ! curl --fail --location --silent --show-error \
      --retry 4 --retry-delay 2 --connect-timeout 20 --max-time 180 \
      "$url_base/$name" --output "$temp"; then
    rm -f "$temp"
    echo "Unable to download $name" >&2
    exit 1
  fi
  actual="$(git hash-object "$temp")"
  if [[ "$actual" != "$expected" ]]; then
    rm -f "$temp"
    echo "Integrity check failed for $name" >&2
    exit 1
  fi
  mv "$temp" "$target"
  echo "Font installed: $name"
}
fetch_font NotoSansCJKsc-Regular.otf db41e65196f7ac227ace4a88b290d925587ed9be
fetch_font NotoSansCJKsc-Medium.otf df0844dd98e040db25dfdb62a61975745b183844
fetch_font NotoSansCJKsc-Bold.otf 2c02c2a70768918337ba8125070abf60020b8360
