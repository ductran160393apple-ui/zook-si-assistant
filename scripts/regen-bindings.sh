#!/usr/bin/env bash
# Sinh lại binding UniFFI (Swift + Kotlin) từ lõi Rust.
# Dùng: ./scripts/regen-bindings.sh
# Yêu cầu: cargo, uniffi-bindgen 0.28 (script tự cài nếu thiếu).
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v uniffi-bindgen >/dev/null; then
  echo "cài uniffi-bindgen 0.28..." >&2
  cargo install uniffi-bindgen --version "=0.28.3" --locked
fi

# Bản debug chưa strip để bindgen đọc được UDL nhúng.
cargo build -p aiassist-core --lib
DYLIB="$(ls -t target/debug/libaiassist_core.dylib | head -n 1)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
uniffi-bindgen generate --library "$DYLIB" --language swift --out-dir "$TMP/swift"
uniffi-bindgen generate --library "$DYLIB" --language kotlin --out-dir "$TMP/kotlin"

# Swift: bản chuẩn vào Generated/ (+ bản copy cho SwiftPM, gitignore).
cp "$TMP/swift/aiassist_core.swift" macos/Generated/aiassist_core.swift
cp "$TMP/swift/aiassist_core.swift" macos/Sources/AiAssistant/AiAssistCoreFFI.swift
cp "$TMP/swift/aiassist_coreFFI.h" macos/Generated/aiassist_coreFFI.h
cp "$TMP/swift/aiassist_coreFFI.h" macos/CAiAssistCore/aiassist_coreFFI.h
cp "$TMP/swift/aiassist_coreFFI.modulemap" macos/Generated/aiassist_coreFFI.modulemap
# Kotlin: bản duy nhất, commit cùng source.
cp "$TMP/kotlin/uniffi/aiassist_core/aiassist_core.kt" \
  android/app/src/main/java/aiassist/uniffi/aiassist_core/aiassist_core.kt
echo "bindings regenerated"
