#!/bin/bash
# VibeMic Native — setup script for macOS
set -e

echo "=== VibeMic Native (macOS) Setup ==="

# Check we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "ERROR: This setup script is for macOS only."
    exit 1
fi

# Check Homebrew
if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew not found. Install from https://brew.sh"
    exit 1
fi

# System dependencies
echo "Installing system dependencies via brew..."
brew install sox

# Python dependencies
echo "Installing Python packages..."
pip3 install openai rumps pynput Pillow pyobjc-framework-Cocoa

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create config.json if missing (from .env.example template)
if [ ! -f "$SCRIPT_DIR/config.json" ]; then
    echo ""
    echo "⚠️  No config.json found. Run VibeMic and open Settings to configure."
fi

# Make executable
chmod +x "$SCRIPT_DIR/vibemic.py"

# LaunchAgent for autostart (login item)
PLIST_NAME="com.vibemic.native"
PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>${SCRIPT_DIR}/vibemic.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${HOME}/.cache/vibemic/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.cache/vibemic/stderr.log</string>
</dict>
</plist>
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "To run:  python3 $SCRIPT_DIR/vibemic.py"
echo "Autostart: Enabled via LaunchAgent (runs on login)"
echo ""
echo "⚠️  IMPORTANT: You must grant these permissions in System Settings → Privacy & Security:"
echo "   1. Accessibility — for your terminal app (to detect PgDn and simulate Cmd+V)"
echo "   2. Microphone — for your terminal app (to record audio)"
echo ""
echo "Usage: Press PgDn to start recording, PgDn again to stop & type."
