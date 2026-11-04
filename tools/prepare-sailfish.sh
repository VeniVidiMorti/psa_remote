#!/bin/sh
# Fills sailfish/python with psa_bridge and sailfish/lib with the unmodified psa_car_controller release and its
# runtime dependencies, for the phone (aarch64, Python 3.11). Run this before `sfdk build` in sailfish/.
set -e
cd "$(dirname "$0")/.."
PLATFORM="--python-version 3.11 --python-platform aarch64-manylinux2014 --link-mode copy"
rm -rf sailfish/python sailfish/lib
mkdir -p sailfish/python
cp psa_bridge.py sailfish/python/
cp -r stubs sailfish/python/
uv pip install --target sailfish/lib $PLATFORM -r requirements.txt
uv pip install --target sailfish/lib $PLATFORM --no-deps -r requirements-psacc.txt
rm -rf sailfish/lib/bin
find sailfish -name __pycache__ -prune -exec rm -rf {} +
du -sh sailfish/lib
