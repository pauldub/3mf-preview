#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 Tests/fixtures.py
swiftc -module-cache-path build/TestModuleCache -import-objc-header Core/Bridge.h Core/*.swift Tests/main.swift -larchive -o build/model-tests
build/model-tests "$PWD/Tests/fixtures"
