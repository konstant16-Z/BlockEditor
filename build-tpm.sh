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
#   ./build-tpm.sh              # Debug
#   ./build-tpm.sh Release
#
# Итог: dist/BlockEditor-<версия>.tpm + SHA-256 на stdout (вставьте
# его в catalog.json как tpm_sha256).

set -euo pipefail

CONFIG="${1:-Debug}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$ROOT/BlockEditor"
PROJ="$PROJ_DIR/BlockEditor.csproj"
PLUGIN_SRC="$PROJ_DIR/BlockEditor.plugin"
ASSEMBLY_INFO="$PROJ_DIR/Properties/AssemblyInfo.cs"

OUT_BIN="$PROJ_DIR/../../Development/Out/Bin"   # как в csproj: ../../Development/Out/Bin
STAGE="$ROOT/dist/.stage"
DIST="$ROOT/dist"

# ---- параметры пакета (при необходимости правьте здесь) ------------------------
PKG_NAME="block-editor"                          # kebab-case, id в каталоге
PKG_CAPTION="Редактор блоков"                     # заголовок на русском
PKG_DESCRIPTION="Правка определения блока в отдельном окне чертежа Robur: изменения применяются к исходному блоку (обновляются все его вставки). Также сохранение блока в нативный .dwp и переименование."
PKG_AUTHOR="Konstantin Zelensky"
PKG_MIN_VERSION="16.0"                            # как у канона ("16.0")
# --------------------------------------------------------------------------------

need() { command -v "$1" >/dev/null 2>&1 || { echo "ОШИБКА: нужен $1" >&2; exit 1; }; }
need dotnet
need python3

# Версия — единый источник истины: AssemblyInfo.cs
FULL_VERSION="$(sed -n 's/.*AssemblyVersion("\([^"]*\)").*/\1/p' "$ASSEMBLY_INFO" | head -1)"
[ -n "$FULL_VERSION" ] || { echo "ОШИБКА: не найден AssemblyVersion в $ASSEMBLY_INFO" >&2; exit 1; }
VERSION="${FULL_VERSION%.*}"                     # 1.0.0.0 -> 1.0.0
TPM_NAME="BlockEditor-${VERSION}.tpm"

# ---- сборка --------------------------------------------------------------------
echo "==> Сборка ($CONFIG)"
export PATH="$PATH:$HOME/.dotnet"
( cd "$PROJ_DIR" && dotnet msbuild "$PROJ" "/p:Configuration=$CONFIG" -v:m -nologo )

DLL="$OUT_BIN/BlockEditor.dll"
[ -f "$DLL" ] || { echo "ОШИБКА: не найден $DLL" >&2; exit 1; }

# ---- манифест пакета ------------------------------------------------------------
echo "==> Манифест пакета $VERSION"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/plugins" "$STAGE/icons"
python3 - "$PKG_NAME" "$VERSION" "$PKG_CAPTION" "$PKG_DESCRIPTION" "$PKG_AUTHOR" "$PKG_MIN_VERSION" > "$STAGE/package.json.tmp" <<'PY'
import json, sys
name, version, caption, description, author, minver = sys.argv[1:7]
print(json.dumps({
    "name": name,
    "version": version,
    "caption": caption,
    "description": description,
    "author": author,
    "minVersion": minver,
}, ensure_ascii=False, indent=2))
PY
mv "$STAGE/package.json.tmp" "$STAGE/package.json"

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
files = []
for root, dirs, names in os.walk(stage):
    dirs.sort(); names.sort()
    for n in names:
        full = os.path.join(root, n)
        files.append((full, os.path.relpath(full, stage).replace(os.sep, '/')))
# канон: package.json первым, далее содержимое по алфавиту
files.sort(key=lambda p: (p[1] != 'package.json', p[1]))
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    # канон-пакеты содержат и записи каталогов (bin/, plugins/, icons/), даже если icons/ пуст
    for d in ('bin', 'plugins', 'icons'):
        z.writestr(zipfile.ZipInfo(d + '/'), b'')
    for full, rel in files:
        z.write(full, rel)
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