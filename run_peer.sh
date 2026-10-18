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

PEER_NAME="${1:-Laptop}"
echo "Starting PrivChat desktop peer CLI as '$PEER_NAME'..."
PYTHONPATH=protocol .venv/bin/python protocol/tools/peer_cli.py --name "$PEER_NAME" "${@:2}"
