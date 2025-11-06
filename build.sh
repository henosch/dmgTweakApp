#!/bin/bash

# ==============================================================================
# dmgTweak Build Script - Complete Build & Install Automation
# ==============================================================================
# 
# This script provides a complete build pipeline for the dmgTweak macOS app:
# 1. Dependency checks and installation (SwiftFormat, SwiftLint)
# 2. Code formatting and linting
# 3. Swift Package Manager compilation
# 4. App bundle update and installation
# 5. Proper timestamping for easy version tracking
#
# Usage:
#   ./build.sh              # Full build with all checks
#   ./build.sh --no-deps    # Skip dependency installation
#   ./build.sh --no-lint    # Skip linting/formatting
#   ./build.sh --help       # Show help
#
# Requirements:
# - macOS with Xcode Command Line Tools
# - Swift Package Manager
# - Homebrew (for dependency installation)
#
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly APP_NAME="dmgTweak"
readonly BUILD_DIR=".build"
readonly DIST_DIR="dist"
readonly INSTALL_DIR="$HOME/Applications"
readonly SOURCES_DIR="Sources/"

# Command line flags
INSTALL_DEPS=true
RUN_LINT=true
VERBOSE=false

# ==============================================================================
# Helper Functions
# ==============================================================================

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Print usage information
show_help() {
    cat << EOF
dmgTweak Build Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --no-deps       Skip dependency installation (SwiftFormat, SwiftLint)
    --no-lint       Skip code formatting and linting
    --verbose       Show verbose output
    --help          Show this help message

EXAMPLES:
    $0                    # Full build with all checks
    $0 --no-deps         # Build without installing dependencies
    $0 --no-lint         # Build without linting/formatting
    $0 --verbose         # Verbose build output

DEPENDENCIES:
    - macOS with Xcode Command Line Tools
    - Homebrew (for SwiftFormat/SwiftLint installation)

EOF
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Homebrew is installed
check_homebrew() {
    if ! command_exists brew; then
        error "Homebrew is required for dependency installation"
        log "Install Homebrew from: https://brew.sh"
        log "Or run with --no-deps to skip dependency installation"
        exit 1
    fi
}

# Install SwiftFormat if not present
install_swiftformat() {
    if command_exists swiftformat; then
        log "SwiftFormat is already installed: $(swiftformat --version)"
        return 0
    fi

    log "Installing SwiftFormat via Homebrew..."
    check_homebrew
    
    if brew install swiftformat; then
        success "SwiftFormat installed successfully"
    else
        warn "Failed to install SwiftFormat - continuing without it"
        return 1
    fi
}

# Install SwiftLint if not present
install_swiftlint() {
    if command_exists swiftlint; then
        log "SwiftLint is already installed: $(swiftlint version)"
        return 0
    fi

    log "Installing SwiftLint via Homebrew..."
    check_homebrew
    
    if brew install swiftlint; then
        success "SwiftLint installed successfully"
    else
        warn "Failed to install SwiftLint - continuing without it"
        return 1
    fi
}

# Format Swift code
format_code() {
    if ! command_exists swiftformat; then
        warn "SwiftFormat not available - skipping code formatting"
        return 0
    fi

    log "Formatting Swift code..."
    if swiftformat . --swift-version 5.9 ${VERBOSE:+--verbose}; then
        success "Code formatting completed"
    else
        warn "Code formatting failed - continuing anyway"
    fi
}

# Lint Swift code
lint_code() {
    if ! command_exists swiftlint; then
        warn "SwiftLint not available - skipping code linting"
        return 0
    fi

    log "Linting Swift code..."
    if swiftlint --fix --quiet && swiftlint ${VERBOSE:+--reporter xcode}; then
        success "Code linting completed - no issues found"
    else
        warn "SwiftLint found issues - check output above"
        log "Build will continue, but consider fixing the issues"
    fi
}

# Clean build artifacts
clean_build() {
    log "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR" "$DIST_DIR"
    success "Build artifacts cleaned"
}

# Compile the Swift project using Swift Package Manager
compile_project() {
    log "Compiling dmgTweak with Swift Package Manager..."
    
    # Check if Package.swift exists
    if [ ! -f "Package.swift" ]; then
        error "Package.swift not found - this project requires Swift Package Manager"
        exit 1
    fi
    
    # Build with Swift Package Manager
    local compile_cmd=(swift build -c release)
    
    if $VERBOSE; then
        log "Running: ${compile_cmd[*]}"
        compile_cmd+=(--verbose)
    fi
    
    if "${compile_cmd[@]}"; then
        success "Swift Package Manager compilation successful"
        
        # Touch .app bundle to update timestamp for development visibility
        if [[ -d ".build/release/dmgTweakApp.app" ]]; then
            touch ".build/release/dmgTweakApp.app"
            log "Updated .app timestamp for development visibility"
        fi
        
        # Copy built binary to our build directory for consistency
        mkdir -p "$BUILD_DIR"
        cp ".build/release/dmgTweakApp" "$BUILD_DIR/$APP_NAME"
        success "Binary copied to: $BUILD_DIR/$APP_NAME"
    else
        error "Swift Package Manager compilation failed"
        exit 1
    fi
}

# Update existing app bundle
update_bundle() {
    log "Updating existing app bundle..."
    
    # Use existing dmgTweak.app bundle
    local existing_app="$APP_NAME.app"
    local dist_app="$DIST_DIR/$APP_NAME.app"
    
    if [ ! -d "$existing_app" ]; then
        error "Existing app bundle not found: $existing_app"
        exit 1
    fi
    
    # Create dist directory and copy existing bundle
    mkdir -p "$DIST_DIR"
    cp -R "$existing_app" "$DIST_DIR/"
    
    # Update the binary in the bundle
    local macos_dir="$dist_app/Contents/MacOS"
    if [ -f "$BUILD_DIR/$APP_NAME" ]; then
        # Einheitlicher Binary-Name im Bundle: dmgTweak
        cp "$BUILD_DIR/$APP_NAME" "$macos_dir/$APP_NAME"
        chmod +x "$macos_dir/$APP_NAME"
        success "Binary updated in existing bundle: $dist_app (Contents/MacOS/$APP_NAME)"

        # Copy localized resources (lproj) into Contents/Resources
        local resources_src="Sources/Resources"
        local resources_dst="$dist_app/Contents/Resources"
        if [ -d "$resources_src" ]; then
            mkdir -p "$resources_dst"
            # Only sync localized .lproj folders; do NOT delete other resources like icon.icns
            rsync -a --include='*/' --include='*.lproj/**' --exclude='*' "$resources_src/" "$resources_dst/"
            success "Localized resources updated: $resources_dst"
        fi

        # Ensure app icon exists
        if [ -f "packaging/icon.icns" ]; then
            mkdir -p "$resources_dst"
            cp "packaging/icon.icns" "$resources_dst/icon.icns"
        fi

        # Remove stray binaries except the expected one
        find "$macos_dir" -maxdepth 1 -type f ! -name "$APP_NAME" -exec rm -f {} +
    else
        error "Built binary not found: $BUILD_DIR/$APP_NAME"
        exit 1
    fi
}

# Code sign the app bundle
sign_bundle() {
    local app_path="$DIST_DIR/$APP_NAME.app"
    
    log "Code signing app bundle..."
    if codesign --force --deep -s - "$app_path" >/dev/null 2>&1; then
        success "App bundle signed successfully"
    else
        warn "Code signing failed - app may not run on other systems"
    fi
}

# Install app to ~/Applications/
install_app() {
    local app_path="$DIST_DIR/$APP_NAME.app"
    local install_path="$INSTALL_DIR/$APP_NAME.app"
    
    log "Installing app to $INSTALL_DIR..."
    
    # Create Applications directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    # Remove old version if it exists
    if [ -d "$install_path" ]; then
        rm -rf "$install_path"
        log "Removed previous version"
    fi
    
    # Copy app bundle
    cp -R "$app_path" "$INSTALL_DIR/"
    
    # Update timestamp for easy version tracking
    touch "$install_path"
    
    # Remove quarantine attribute
    if xattr -dr com.apple.quarantine "$install_path" 2>/dev/null; then
        log "Quarantine attribute removed"
    fi
    
    success "App installed: $install_path"
}

# Optionally package zip and update GitHub release notes with checksum
package_and_update_release() {
    # Source-only packaging: create a zip of the tracked source at HEAD
    if [ -z "${RELEASE_TAG:-}" ]; then
        return 0
    fi
    mkdir -p "$DIST_DIR"
    local zip_name="$DIST_DIR/${APP_NAME}-${RELEASE_TAG}-source.zip"
    log "Packaging source zip for release ${RELEASE_TAG}..."
    rm -f "$zip_name"
    # Use git archive to include only tracked files and honor .gitignore
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        git archive -o "$zip_name" --format=zip HEAD || {
            warn "Failed to create source zip"
            return 0
        }
    else
        warn "Git repository not initialized; skipping source packaging"
        return 0
    fi
    local sha
    sha=$(shasum -a 256 "$zip_name" | awk '{print $1}')
    log "SHA256: $sha"
    if command -v gh >/dev/null 2>&1; then
        local body tmp
        body=$(gh release view "$RELEASE_TAG" --json body -q .body 2>/dev/null || echo "")
        tmp=$(mktemp)
        if echo "$body" | grep -q "^## Checksums"; then
            printf "%s\n\n" "$body" | awk 'BEGIN{p=1} /^## Checksums/{p=0} {if(p)print}' > "$tmp"
        else
            printf "%s\n\n" "$body" > "$tmp"
        fi
        {
            echo "## Checksums"
            echo "- ${APP_NAME}-${RELEASE_TAG}-source.zip (SHA256):"
            echo "  $sha  ${APP_NAME}-${RELEASE_TAG}-source.zip"
        } >> "$tmp"
        gh release upload "$RELEASE_TAG" "$zip_name" --clobber >/dev/null 2>&1 || true
        gh release edit "$RELEASE_TAG" --notes-file "$tmp" >/dev/null 2>&1 || true
        rm -f "$tmp"
        success "Release ${RELEASE_TAG} updated with source zip + checksum"
    else
        warn "gh not found; skipped release notes update"
    fi
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-deps)
                INSTALL_DEPS=false
                shift
                ;;
            --no-lint)
                RUN_LINT=false
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# Main Build Pipeline
# ==============================================================================

main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  dmgTweak Build Script v1.0    ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check if we're in the right directory
    if [ ! -d "$SOURCES_DIR" ] || [ ! -f "Package.swift" ]; then
        error "Sources directory not found: $SOURCES_DIR or Package.swift missing"
        error "Please run this script from the dmgTweak project root directory"
        exit 1
    fi
    
    # Install dependencies if requested
    if $INSTALL_DEPS; then
        log "Installing/checking dependencies..."
        install_swiftformat || true  # Continue on failure
        install_swiftlint || true    # Continue on failure
        echo
    else
        log "Skipping dependency installation (--no-deps)"
        echo
    fi
    
    # Format and lint code if requested
    if $RUN_LINT; then
        format_code
        lint_code
        echo
    else
        log "Skipping code formatting and linting (--no-lint)"
        echo
    fi
    
    # Build pipeline
    clean_build
    compile_project
    update_bundle
    sign_bundle
    # Keep outputs only in dist/
    
    # Final success message
    echo
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  Build completed successfully! ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo
    log "App location: $DIST_DIR/$APP_NAME.app"
    log "Launch with: open '$DIST_DIR/$APP_NAME.app'"
    echo
    
    # Show app info
    if [ -f "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
        local app_size=$(du -sh "$DIST_DIR/$APP_NAME.app" | cut -f1)
        local binary_size=$(du -sh "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" | cut -f1)
        log "App bundle size: $app_size"
        log "Binary size: $binary_size"
        log "Timestamp: $(stat -f "%Sm" "$DIST_DIR/$APP_NAME.app")"
    fi
}

# Run main function with all arguments
main "$@"
