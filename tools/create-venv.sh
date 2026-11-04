#!/bin/sh
# Creates .venv with Python 3.11 (the version on the phone) and an unmodified psa_car_controller release.
set -e
cd "$(dirname "$0")/.."
uv venv --python 3.11 .venv
uv pip install --python .venv -r requirements.txt -r requirements-setup.txt
uv pip install --python .venv --no-deps -r requirements-psacc.txt
