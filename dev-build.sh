#!/bin/bash

# Development build script - includes timestamp update for .app
# Usage: ./dev-build.sh [swift build arguments]

set -e

# Run swift build with any provided arguments
swift build "$@"

# Ensure dist app bundle exists (copy template if available), then update only dist
if [[ -f ".build/debug/dmgTweakApp" ]]; then
    if [[ ! -d "dist/dmgTweak.app" ]]; then
        if [[ -d "dmgTweak.app" ]]; then
            mkdir -p dist
            cp -R "dmgTweak.app" "dist/"
        else
            echo "⚠️ No template app bundle found (dmgTweak.app). Please add one to repo root to initialize dist." >&2
            exit 0
        fi
    fi
    cp ".build/debug/dmgTweakApp" "dist/dmgTweak.app/Contents/MacOS/dmgTweak"
    if [[ -d "Sources/Resources" ]]; then
        rsync -a --include='*/' --include='*.lproj/**' --exclude='*' "Sources/Resources/" "dist/dmgTweak.app/Contents/Resources/"
    fi
    if [[ -f "packaging/icon.icns" ]]; then
        mkdir -p "dist/dmgTweak.app/Contents/Resources"
        cp "packaging/icon.icns" "dist/dmgTweak.app/Contents/Resources/icon.icns"
    fi
    find "dist/dmgTweak.app/Contents/MacOS" -maxdepth 1 -type f ! -name "dmgTweak" -exec rm -f {} +
    touch "dist/dmgTweak.app"
    echo "✓ Updated: dist/dmgTweak.app ($(date '+%H:%M:%S'))"
fi

echo "🎉 Build complete (dist only)"
