#!/usr/bin/env sh
set -e

# Configuration
OWNER="synlace"
REPO="okayrun-cli"
BINARY_NAME="okay"

# Determine target install directory (defaults to ~/.local/bin if not specified or root)
if [ -z "$BINDIR" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        BINDIR="/usr/local/bin"
    else
        BINDIR="$HOME/.local/bin"
    fi
fi

# Detect Operating System
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
    darwin*)  OS="darwin" ;;
    linux*)   OS="linux" ;;
    msys*|mingw*|cygwin*) OS="windows" ;;
    *)
        echo "[Installer] ERROR: Unsupported operating system: $OS" >&2
        exit 1
        ;;
esac

# Detect Architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)
        echo "[Installer] ERROR: Unsupported CPU architecture: $ARCH" >&2
        exit 1
        ;;
esac

# Get latest release tag from GitHub API
echo "[Installer] Fetching latest release version from GitHub..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/$OWNER/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_RELEASE" ]; then
    echo "[Installer] ERROR: Could not retrieve latest release version from $OWNER/$REPO." >&2
    exit 1
fi

echo "[Installer] Installing $BINARY_NAME $LATEST_RELEASE for $OS/$ARCH..."

# Define extension and download URL
EXT="tar.gz"
if [ "$OS" = "windows" ]; then
    EXT="zip"
fi

FILENAME="${BINARY_NAME}_${OS}_${ARCH}.${EXT}"
DOWNLOAD_URL="https://github.com/$OWNER/$REPO/releases/download/$LATEST_RELEASE/$FILENAME"

# Create temporary directory for download
TMP_DIR=$(mktemp -d)
clean_up() {
    rm -rf "$TMP_DIR"
}
trap clean_up EXIT

# Download tarball/zip
echo "[Installer] Downloading $DOWNLOAD_URL..."
curl -sL -o "$TMP_DIR/$FILENAME" "$DOWNLOAD_URL"

# Extract archive
cd "$TMP_DIR"
if [ "$EXT" = "tar.gz" ]; then
    tar -xzf "$FILENAME"
else
    unzip -q "$FILENAME"
fi

# Ensure target binary directory exists
mkdir -p "$BINDIR"

# Install binary with elevated privileges only if needed
if [ -w "$BINDIR" ]; then
    mv "$BINARY_NAME" "$BINDIR/$BINARY_NAME"
    chmod +x "$BINDIR/$BINARY_NAME"
else
    echo "[Installer] Elevated permissions needed to install to $BINDIR"
    sudo mv "$BINARY_NAME" "$BINDIR/$BINARY_NAME"
    sudo chmod +x "$BINDIR/$BINARY_NAME"
fi

echo "[Installer] Successfully installed $BINARY_NAME to $BINDIR/$BINARY_NAME"

# Check if target directory is in PATH
case ":$PATH:" in
    *:"$BINDIR":*) ;;
    *)
        echo "[Installer] WARNING: $BINDIR is not in your PATH. Add it to your shell configuration (e.g., ~/.bashrc or ~/.zshrc):"
        echo "  export PATH=\"\$PATH:$BINDIR\""
        ;;
esac
