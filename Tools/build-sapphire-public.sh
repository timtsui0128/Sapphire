#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${SAPPHIRE_PUBLIC_BUILD_ROOT:-"$REPO_ROOT/output/public-build"}"
PACKAGE_CACHE="${SAPPHIRE_PACKAGE_CACHE:-"$BUILD_ROOT/SourcePackages"}"
PROJECT_PATH="$BUILD_ROOT/Sapphire.xcodeproj"

python3 "$REPO_ROOT/Tools/prepare-sapphire-public.py" \
  --repo "$REPO_ROOT" --output "$PROJECT_PATH"

if [[ "${1:-}" == "--prepare-only" ]]; then
  exit 0
fi
if [[ $# -gt 0 ]]; then
  printf 'Usage: bash Tools/build-sapphire-public.sh [--prepare-only]\n' >&2
  exit 2
fi

# Building the explicit target also avoids resolving an upstream self-referencing
# scheme back to the original project, whose newer file format Xcode 26.3 cannot open.
xcodebuild \
  -project "$PROJECT_PATH" \
  -target Sapphire \
  -configuration Debug \
  -sdk macosx \
  -arch "$(uname -m)" \
  -clonedSourcePackagesDirPath "$PACKAGE_CACHE" \
  -onlyUsePackageVersionsFromResolvedFile \
  "SYMROOT=$BUILD_ROOT/Build/Products" \
  "OBJROOT=$BUILD_ROOT/Build/Intermediates.noindex" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  ONLY_ACTIVE_ARCH=YES \
  SWIFT_OPTIMIZATION_LEVEL=-Onone \
  GCC_OPTIMIZATION_LEVEL=0 \
  DEBUG_INFORMATION_FORMAT=dwarf \
  build

APP_PATH="$BUILD_ROOT/Build/Products/Debug/Sapphire.app"
# Local ad-hoc signing makes the resulting app launchable without a developer account.
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
printf '%s\n' "$APP_PATH"
