#!/bin/bash
# Ctrl+G generate entrypoint
# Usage: ai-command-generate.sh "user typed text"

set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/ai-command-request.sh" generate "$@"
