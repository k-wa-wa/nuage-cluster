#!/bin/bash

set -e

ANTHROPIC_AUTH_TOKEN=ollama \
ANTHROPIC_API_KEY="" \
ANTHROPIC_BASE_URL=http://192.168.5.222:11434 \
~/.local/bin/claude --model qwen3.5:9b --dangerously-skip-permissions
