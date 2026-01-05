#!/bin/bash
# Run the app and show console output

echo "Starting MacCornerFix with console logging..."
echo "Press Ctrl+C to stop"
echo ""

cd "$(dirname "$0")"
./build/MacCornerFix.app/Contents/MacOS/MacCornerFix
