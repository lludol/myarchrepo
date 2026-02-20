#!/bin/bash

# Clean ./src subfolders (build artifacts per package)
rm -f src/*/*.log
rm -f src/*/*.AppImage*
rm -f src/*/*.deb
rm -f src/*/*.rpm
rm -f src/*/*.tmp
rm -f src/*/*.html
rm -f src/*/*.snap
rm -f src/*/*.tar.gz
rm -f src/*/*.zip
rm -rf src/*/.cache/
rm -rf src/*/src/
rm -rf src/*/pkg/
rm -rf src/*/build/

# Clean x86_64 (logs)
rm -f x86_64/*.log
