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

python3 "$REPO_ROOT/Tools/Updates/app_signing.py" preflight

VERSION_ARGS=()
if [[ -n "${SAPPHIRE_VERSION:-}" ]]; then VERSION_ARGS+=("MARKETING_VERSION=$SAPPHIRE_VERSION"); fi
if [[ -n "${SAPPHIRE_BUILD_NUMBER:-}" ]]; then VERSION_ARGS+=("CURRENT_PROJECT_VERSION=$SAPPHIRE_BUILD_NUMBER"); fi

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
  COMPILER_INDEX_STORE_ENABLE=NO \
  ONLY_ACTIVE_ARCH=YES \
  SWIFT_OPTIMIZATION_LEVEL=-Onone \
  GCC_OPTIMIZATION_LEVEL=0 \
  DEBUG_INFORMATION_FORMAT=dwarf \
  ${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"} \
  build

APP_PATH="$BUILD_ROOT/Build/Products/Debug/TopLet.app"
# Include the original license/attribution and updater notices in the distributed app.
APP_LEGAL="$APP_PATH/Contents/Resources/Legal"
mkdir -p "$APP_LEGAL"
cp "$REPO_ROOT/LICENSE" "$APP_LEGAL/LICENSE-AGPLv3.txt"
cp "$REPO_ROOT/CREDITS.md" "$APP_LEGAL/CREDITS.md"
cp "$REPO_ROOT/docs/licenses/Sparkle-LICENSE.txt" "$APP_LEGAL/Sparkle-LICENSE.txt"

# Reuse the configured Keychain identity for every version. Without a configured
# identity local builds remain ad-hoc; missing configured keys fail closed.
python3 "$REPO_ROOT/Tools/Updates/app_signing.py" sign "$APP_PATH"
printf '%s\n' "$APP_PATH"
