#!/usr/bin/env bash
# Сборка проекта BlockEditor под Linux/WSL (dotnet msbuild из ~/.dotnet).
#
# Использование:
#   ./build-block-editor.sh                     # Debug против Bin (16.0.62.x)
#   ./build-block-editor.sh Release             # то же, Release
#   ./build-block-editor.sh Debug old           # против Bin_16_50 (16.0.50.x)
#   ./build-block-editor.sh Debug ../../Development/Out/Bin_16_50   # произвольный каталог
#
# Каталог корпуса передаётся в проект как /p:RoburBinDir=... — конвенция
# Dop/ROBUR-16.0.50-compat.md: один и тот же исходник собирается под любой
# корпус, отличаются только ссылки и выходной каталог.
set -e

export PATH="$PATH:$HOME/.dotnet"

CONFIG="${1:-Debug}"
CORPUS="${2:-new}"
PROJECT_DIR="$(cd "$(dirname "$0")/BlockEditor" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Каталог Development/Out может лежать на уровень выше (BlockEditor — субмодуль
# PluginExample-main) или на два (BlockEditor клонирован рядом). Берём тот, где есть сборки.
resolve_corpus() {
    local variant="$1"
    local candidate
    for candidate in "$ROOT_DIR/../Development/Out/$variant" \
                     "$ROOT_DIR/../../Development/Out/$variant" \
                     "$ROOT_DIR/Development/Out/$variant"; do
        if [ -f "$candidate/Topomatic.ApplicationPlatform.dll" ]; then
            (cd "$candidate" && pwd)
            return 0
        fi
    done
    return 1
}

case "$CORPUS" in
    new|"")  LABEL="new" ;;
    old)     LABEL="old" ;;
    /*|*)    LABEL="" ;;   # произвольный путь
    *)       echo "Неизвестный корпус: '$CORPUS' (ожидается: new | old | путь)" >&2; exit 1 ;;
esac

if [ -n "$LABEL" ]; then
    ROBUR_BIN_DIR="$(resolve_corpus "$([ "$LABEL" = new ] && echo Bin || echo Bin_16_50)")" || {
        echo "Не найдены сборки Robur 16.0.${LABEL/new/62}.x: искал Development/Out/$([ "$LABEL" = new ] && echo Bin || echo Bin_16_50) выше по дереву" >&2
        exit 1
    }
else
    ROBUR_BIN_DIR="$CORPUS"
fi

if [ ! -f "$ROBUR_BIN_DIR/Topomatic.ApplicationPlatform.dll" ]; then
    echo "Нет сборок Robur в каталоге: $ROBUR_BIN_DIR" >&2
    exit 1
fi

echo "Сборка BlockEditor [$CONFIG] против $ROBUR_BIN_DIR ..."
cd "$PROJECT_DIR"
dotnet restore BlockEditor.csproj
dotnet msbuild BlockEditor.csproj \
    /p:Configuration="$CONFIG" \
    "/p:RoburBinDir=$ROBUR_BIN_DIR/" \
    /v:minimal

echo ""
echo "Готово: $ROBUR_BIN_DIR/BlockEditor.dll (+ .plugin, + BlockEditor.pdb)"