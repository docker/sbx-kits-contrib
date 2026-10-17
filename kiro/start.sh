#!/bin/bash

echo "Performing authentication check"
kiro-cli whoami > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Currently authenticated"
    kiro-cli "$@"
else
    echo "❌ Not authenticated. Starting login flow..."
    kiro-cli login --use-device-flow
    if [ $? -ne 0 ]; then
        echo "❌ Login failed. Exiting."
        exit 1
    fi
    echo "✅ Currently authenticated"
    kiro-cli "$@"
fi
