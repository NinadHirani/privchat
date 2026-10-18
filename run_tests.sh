#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ ! -d ".venv" ]; then
    echo "Creating virtualenv..."
    python3 -m venv .venv
    .venv/bin/pip install --upgrade pip
    .venv/bin/pip install -r requirements.txt
fi

echo "Running PrivChat protocol test suite..."
PYTHONPATH=protocol .venv/bin/pytest protocol/tests -v

echo "Validating deterministic test vectors generator..."
PYTHONPATH=protocol .venv/bin/python protocol/gen_vectors.py

echo "All tests passed successfully!"
