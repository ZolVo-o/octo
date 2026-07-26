#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/octo"

echo "🐙 OCTO installer"

if ! command -v bash >/dev/null 2>&1; then
    echo "Ошибка: bash не найден" >&2
    exit 1
fi

mkdir -p "$BIN_DIR"
chmod +x "${PROJECT_DIR}/octo"
ln -sfn "${PROJECT_DIR}/octo" "$TARGET"

echo "Собираю C++ backend..."
if ! command -v g++ >/dev/null 2>&1; then
    echo "Ошибка: g++ не найден. Установите его командой: sudo pacman -S gcc" >&2
    exit 1
fi
mkdir -p "${PROJECT_DIR}/target"
g++ -std=c++17 -O2 -Wall -Wextra \
    "${PROJECT_DIR}/backend/octo_backend.cpp" \
    -o "${PROJECT_DIR}/target/octo-backend"

if command -v cargo >/dev/null 2>&1; then
    echo "Собираю Rust TUI..."
    cargo build --manifest-path "${PROJECT_DIR}/Cargo.toml" --bin octo-tui
else
    echo "Cargo не найден: C++ backend установлен, Rust TUI можно собрать позже."
fi

echo "Готово: ${TARGET}"
echo "Запуск CLI: octo help"
echo "Запуск TUI: octo tui"
