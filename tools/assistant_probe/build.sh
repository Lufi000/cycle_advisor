#!/bin/bash
# 编译 assistant probe：复用 App 的真实 prompt 构建代码（LLMService + 模型层）。
# 产物位于 tools/assistant_probe/build/probe，并把 lproj 拷到旁边，
# 让 String(localized:) 能解析中文/英文文案（与 App 行为一致）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$ROOT/tools/assistant_probe/build"

mkdir -p "$BUILD_DIR"

swiftc -swift-version 5 -O \
  "$ROOT/Sources/Core/Secrets.swift" \
  "$ROOT/Sources/Core/LLMService.swift" \
  "$ROOT/Sources/Core/Models/CyclePhase.swift" \
  "$ROOT/Sources/Core/Models/UserProfile.swift" \
  "$ROOT/Sources/Core/Models/MenstrualSymptoms.swift" \
  "$ROOT/Sources/Core/UserProfileManager.swift" \
  "$ROOT/Sources/Shared/LanguageManager.swift" \
  "$ROOT/Sources/Shared/Theme.swift" \
  "$ROOT/tools/assistant_probe/main.swift" \
  -o "$BUILD_DIR/probe"

rm -rf "$BUILD_DIR/zh-Hans.lproj" "$BUILD_DIR/en.lproj"
cp -R "$ROOT/Sources/Resources/zh-Hans.lproj" "$BUILD_DIR/"
cp -R "$ROOT/Sources/Resources/en.lproj" "$BUILD_DIR/"

echo "probe built at $BUILD_DIR/probe"
