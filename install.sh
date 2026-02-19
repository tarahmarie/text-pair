#!/bin/bash
#===============================================================================
# TextPAIR Minimal Install Script
# For macOS (Apple Silicon M1/M2/M3/M4 and Intel)
#
# This script installs TextPAIR WITHOUT the web app, PostgreSQL, or Apache.
# Designed for running sequence alignments locally and outputting
# alignments.jsonl for downstream analysis.
#
# Source: https://github.com/tarahmarie/text-pair (mac-bare-metal branch)
# Forked from: https://github.com/ARTFL-Project/text-pair
#
# Prerequisites:
#   - macOS with Python 3.11+ installed
#   - Git
#
# Usage:
#   1. Clone: git clone -b mac-bare-metal https://github.com/tarahmarie/text-pair
#   2. cd text-pair
#   3. Run: ./install.sh
#
# Note: Uses --break-system-packages to install globally without virtualenv.
#===============================================================================

set -e

echo "=== TextPAIR Minimal Install for macOS (No Web App) ==="
echo ""

#-------------------------------------------------------------------------------
# Check we're on macOS
#-------------------------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Warning: This script is written for macOS."
    echo "Linux users will need to adjust commands."
fi

#-------------------------------------------------------------------------------
# Check architecture (Apple Silicon vs Intel)
#-------------------------------------------------------------------------------
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

if [ "$ARCH" = "arm64" ]; then
    BINARY_ARCH="aarch64"
    echo "  -> Using ARM64/aarch64 binary (Apple Silicon)"
elif [ "$ARCH" = "x86_64" ]; then
    BINARY_ARCH="x86_64"
    echo "  -> Using x86_64 binary (Intel Mac)"
else
    echo "Error: Unknown architecture $ARCH"
    exit 1
fi

#-------------------------------------------------------------------------------
# Check we're in the text-pair directory
#-------------------------------------------------------------------------------
if [ ! -f "lib/pyproject.toml" ]; then
    echo "Error: lib/pyproject.toml not found."
    echo "Make sure you're in the text-pair repository root directory."
    exit 1
fi

#-------------------------------------------------------------------------------
# Check for required patches (should already be applied on mac-bare-metal branch)
#-------------------------------------------------------------------------------
echo ""
echo "=== Verifying patches ==="

if grep -q "psycopg2-binary" lib/pyproject.toml; then
    echo "  [OK] psycopg2-binary patch present"
else
    echo "  [APPLYING] psycopg2 -> psycopg2-binary"
    sed -i '' 's/"psycopg2"/"psycopg2-binary"/' lib/pyproject.toml
fi

if grep -q "def cli_entry" lib/textpair/__main__.py; then
    echo "  [OK] cli_entry() wrapper present"
else
    echo "  [APPLYING] Adding cli_entry() async wrapper"
    cat >> lib/textpair/__main__.py << 'EOF'

def cli_entry():
    """Wrapper to properly run the async main() function."""
    import asyncio
    asyncio.run(main())
EOF
fi

if grep -q "cli_entry" lib/pyproject.toml; then
    echo "  [OK] Entry point uses cli_entry"
else
    echo "  [APPLYING] Updating entry point to cli_entry"
    sed -i '' 's/textpair.__main__:main/textpair.__main__:cli_entry/' lib/pyproject.toml
fi

#-------------------------------------------------------------------------------
# Install Python packages
#-------------------------------------------------------------------------------
echo ""
echo "=== Installing Python packages ==="

# Install textpair_llm first (local dependency)
if [ -d "lib/textpair_llm" ]; then
    echo "Installing textpair_llm..."
    pip3 install -e lib/textpair_llm/. --break-system-packages
fi

# Install main textpair library
echo ""
echo "Installing textpair (this downloads ~100MB of dependencies)..."
pip3 install -e lib/. --break-system-packages

#-------------------------------------------------------------------------------
# Install compareNgrams binary
#-------------------------------------------------------------------------------
echo ""
echo "=== Installing compareNgrams binary ==="

BINARY_PATH="lib/core/binary/${BINARY_ARCH}/compareNgrams"

if [ -f "$BINARY_PATH" ]; then
    if [ -f "/usr/local/bin/compareNgrams" ]; then
        echo "  compareNgrams already installed"
    else
        echo "  Installing to /usr/local/bin/ (requires sudo)..."
        sudo cp "$BINARY_PATH" /usr/local/bin/
        sudo chmod +x /usr/local/bin/compareNgrams
    fi
else
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

#-------------------------------------------------------------------------------
# Test installation
#-------------------------------------------------------------------------------
echo ""
echo "=== Testing installation ==="
echo "Running: python3 -m textpair --help"
echo ""
echo "NOTE: First run takes 1-2 minutes while spacy/torch models load."
echo "      This is normal - do not interrupt it."
echo ""

if python3 -m textpair --help > /dev/null 2>&1; then
    echo "[SUCCESS] textpair is working!"
else
    echo ""
    echo "Testing with visible output..."
    python3 -m textpair --help
fi

echo ""
echo "==============================================================================="
echo "INSTALLATION COMPLETE"
echo "==============================================================================="
echo ""
echo "Your fork: https://github.com/tarahmarie/text-pair"
echo "Branch: mac-bare-metal"
echo ""
echo "To run an alignment:"
echo ""
echo "  1. Edit config/config.ini:"
echo "     - source_file_path = /absolute/path/to/your/TEI/files"
echo "     - target_file_path = (leave empty to compare source against itself)"
echo "     - language = english"
echo ""
echo "  2. Run:"
echo "     python3 -m textpair --config=config/config.ini \\"
echo "                        --skip_web_app \\"
echo "                        --output_path=/tmp/textpair-out \\"
echo "                        --workers=4 \\"
echo "                        my_alignment"
echo ""
echo "  3. Results will be in:"
echo "     /tmp/textpair-out/my_alignment/results/alignments.jsonl"
echo ""
echo "TIPS:"
echo "  - Use ABSOLUTE paths in config.ini"
echo "  - First run is slow (spacy model loading)"
echo "  - Delete output dir between runs to avoid 'File exists' errors"
echo "  - The --skip_web_app flag is required (no PostgreSQL)"
echo ""