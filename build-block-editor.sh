#!/usr/bin/env bash
# Сборка проекта BlockEditor под Linux/WSL (dotnet msbuild, SDK 8 в ~/.dotnet).
# Использование: ./build-block-editor.sh [Debug|Release]
set -e

export PATH="$PATH:$HOME/.dotnet"
CONFIG="${1:-Debug}"
PROJECT_DIR="$(cd "$(dirname "$0")/BlockEditor" && pwd)"

echo "Сборка BlockEditor [$CONFIG] ..."
cd "$PROJECT_DIR"
dotnet restore BlockEditor.csproj
dotnet msbuild BlockEditor.csproj /p:Configuration="$CONFIG" /v:minimal

echo ""
echo "Готово: Development/Out/Bin/BlockEditor.dll (+ .plugin, + BlockEditor.pdb)"