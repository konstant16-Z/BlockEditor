#!/usr/bin/env bash
#
# build-tpm.sh — сборка BlockEditor и упаковка в .tpm.
#
# .tpm — формат дистрибуции модулей Robur (обычный ZIP, deflate, без подписи;
# целостность проверяется по SHA-256 ассета релиза). Состав:
#
#   package.json            — манифест пакета (обязателен)
#   bin/<ИмяСборки>.dll     — сборки модулей
#   plugins/*.plugin        — манифесты Robur
#   icons/                  — иконки (необязательно; densities 16dp/32dp × 1x…3x)
#
# Канон — konstant16-Z/BlockEditor (package.json из AbrModules-1.5.1.tpm
# и RoadStyle-1.1.1.tpm), реестр пакетов: konstant16-Z/RoburModulesIndex.
#
# Использование:
#   ./build-tpm.sh                          # Debug, корпус new (16.0.62.x)
#   ./build-tpm.sh Release
#   ./build-tpm.sh Debug old                # корпус old (16.0.50.x)
#   ./build-tpm.sh Debug ../../Development/Out/Bin_16_50   # произвольный каталог корпуса
#
# Итог: dist/BlockEditor-<версия>.tpm + SHA-256 на stdout (вставьте
# его в catalog.json как tpm_sha256).

set -euo pipefail

CONFIG="${1:-Debug}"

CORPUS="${2:-new}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$ROOT/BlockEditor"
PROJ="$PROJ_DIR/BlockEditor.csproj"
PLUGIN_SRC="$PROJ_DIR/BlockEditor.plugin"
PACKAGE_JSON="$ROOT/package.json"

STAGE="$ROOT/dist/.stage"
DIST="$ROOT/dist"

# Каталог Development/Out может лежать на уровень выше (BlockEditor — субмодуль
# PluginExample-main) или на два (BlockEditor клонирован рядом).
resolve_corpus() {
    local variant="$1" candidate
    for candidate in "$ROOT/../Development/Out/$variant" \
                     "$ROOT/../../Development/Out/$variant" \
                     "$ROOT/Development/Out/$variant"; do
        if [ -f "$candidate/Topomatic.ApplicationPlatform.dll" ]; then
            (cd "$candidate" && pwd); return 0
        fi
    done
    return 1
}

case "$CORPUS" in
    new|"") CORPUS_LABEL="new"; CORPUS_DIR="Bin" ;;
    old)    CORPUS_LABEL="old"; CORPUS_DIR="Bin_16_50" ;;
    /*|*)   CORPUS_LABEL=""; CORPUS_DIR="$CORPUS" ;;
    *) echo "Неизвестный корпус: '$CORPUS' (ожидается: new | old | путь)" >&2; exit 1 ;;
esac

if [ -z "$CORPUS_LABEL" ]; then
    OUT_BIN="$CORPUS"
elif OUT_BIN="$(resolve_corpus "$CORPUS_DIR")"; then
    :
else
    echo "ОШИБКА: не найдены сборки Robur ($CORPUS) — искал Development/Out/$CORPUS_DIR выше по дереву" >&2
    exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "ОШИБКА: нужен $1" >&2; exit 1; }; }
need dotnet
need python3

# Версия — из package.json в корне (единый источник истины, как в build-tpm.ps1)
[ -f "$PACKAGE_JSON" ] || { echo "ОШИБКА: нет $PACKAGE_JSON" >&2; exit 1; }
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8"))["version"])' "$PACKAGE_JSON")"
[ -n "$VERSION" ] || { echo "ОШИБКА: в package.json нет поля version" >&2; exit 1; }
TPM_NAME="BlockEditor-${VERSION}.tpm"

# ---- сборка --------------------------------------------------------------------
echo "==> Сборка ($CONFIG, корпус ${CORPUS_LABEL:-$CORPUS})"
export PATH="$PATH:$HOME/.dotnet"
( cd "$PROJ_DIR" && dotnet msbuild "$PROJ" \
    "/p:Configuration=$CONFIG" "/p:RoburBinDir=$OUT_BIN/" -v:m -nologo )

DLL="$OUT_BIN/BlockEditor.dll"
[ -f "$DLL" ] || { echo "ОШИБКА: не найден $DLL" >&2; exit 1; }

# ---- манифест пакета (копируется байт-в-байт, как в Build-AbrTpm) ----------------
echo "==> Манифест пакета $VERSION"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/plugins" "$STAGE/icons"
cp "$PACKAGE_JSON" "$STAGE/package.json"

# ---- содержимое пакета ----------------------------------------------------------
echo "==> Содержимое"
cp "$DLL" "$STAGE/bin/"
cp "$PLUGIN_SRC" "$STAGE/plugins/"

# ---- упаковка ------------------------------------------------------------------
echo "==> Упаковка $TPM_NAME"
rm -f "$DIST/$TPM_NAME"
python3 - "$STAGE" "$DIST/$TPM_NAME" <<'PY'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
# Фиксированные метаданные записи: иначе mtime файлов попадает в архив, и SHA-256
# меняется при каждой пересборке — tpm_sha256 в catalog.json перестаёт сходиться.
STAMP = (1980, 1, 1, 0, 0, 0)
files = []
for root, dirs, names in os.walk(stage):
    dirs.sort(); names.sort()
    for n in names:
        full = os.path.join(root, n)
        files.append((full, os.path.relpath(full, stage).replace(os.sep, '/')))
# канон: package.json первым, далее содержимое по алфавиту
files.sort(key=lambda p: (p[1] != 'package.json', p[1]))
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    # канон-пакеты содержат и записи каталогов (bin/, plugins/, icons/), даже если icons/ пуст
    for d in ('bin', 'plugins', 'icons'):
        zi = zipfile.ZipInfo(d + '/', date_time=STAMP)
        zi.external_attr = (0o755 << 16) | 0x10
        zi.compress_type = zipfile.ZIP_STORED
        z.writestr(zi, b'')
    for full, rel in files:
        zi = zipfile.ZipInfo(rel, date_time=STAMP)
        zi.external_attr = 0o644 << 16          # права не зависят от umask/ФС
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(full, 'rb') as f:
            z.writestr(zi, f.read())
print("файлов в пакете:", len(files))
PY

echo
echo "Готово: dist/$TPM_NAME"
python3 - "$DIST/$TPM_NAME" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for i in z.infolist():
        print(f"  {i.file_size:>9}  {i.filename}")
PY
echo
echo "SHA-256 (в catalog.json -> tpm_sha256):"
sha256sum "$DIST/$TPM_NAME" | cut -d' ' -f1