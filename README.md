# BlockEditor — редактор блоков Topomatic Robur

Плагин для «Топоматик Робур» (САПР автодорог и ж/д, чертежи Robur). Позволяет
редактировать **определение блока** в отдельном окне чертежа, сохранять блок в
нативный файл `.dwp` и переименовывать блок.

## Установка

Требуется Robur **16.0.62.12** и новее. Готовый пакет:
[Releases → BlockEditor-1.0.0.tpm](https://github.com/konstant16-Z/BlockEditor/releases/download/v1.0.0/BlockEditor-1.0.0.tpm).

**Способ 1 — штатный менеджер пакетов Topomatic** (`.tpm` — стандартный формат):

```
TopomaticPackageManager.exe install BlockEditor-1.0.0.tpm
```

После установки перезапустить Robur. Если плагин не подхватился — выполнить
`clearcache` в командной строке Robur.

**Способ 2 — «Библиотека модулей» (ABR).** В конструкторе библиотеки добавить
дополнительный источник каталога с URL нашего `catalog.json`:

```
https://raw.githubusercontent.com/konstant16-Z/BlockEditor/main/catalog.json
```

Запись каталога (`catalog.json`) — по образцу `Y-Abramov/robur-modules`: те же
10 полей (`name`, `title`, `version`, `description`, `author`, `tpm_url`,
`tpm_sha256`, `help_url`, `min_version`, `compatibility`), тот же формат — массив
объектов. ABR помечает сторонние источники предупреждением (`BuildExternalSourceWarning`),
поэтому в `tpm_sha256` обязателен SHA-256 пакета.

Проверка целостности скачанного пакета:

```bash
sha256sum BlockEditor-1.0.0.tpm
# b2d647164f6596cc1a797d2f0c7d5696596528d093037f1e9badb2657cefc4ac
```

## Команды (меню «Блоки»)

| Команда | Действие |
|---|---|
| `block_editor_edit` | Открыть определение выбранного блока в отдельном окне-редакторе. После правок пользователь закрывает окно — плагин спрашивает «Применить изменения блока?» и при согласии **перезаписывает определение исходного блока** (обновляются все вставки этого блока в чертеже), затем удаляет временный файл. |
| `block_editor_save` | Сохранить блок (без вставки) в отдельный файл через диалог — **только нативный `.dwp`** (Stg/BSTG, без потерь). |
| `block_editor_rename` | Переименовать блок (валидация как в штатном диалоге переименования). |

Выбор блока: если в текущем выделении ровно одна вставка — она берётся автоматически;
иначе плагин просит указать вставку кликом на экране.

## Контекстное меню

Все три команды доступны в контекстном меню вставки блока (правая кнопка по выбранному
блоку в окне чертежа) — рядом со штатным «Разбить тэг на примитивы»:

- **Редактировать блок в отдельном окне** — открыть определение блока и править его;
- **Сохранить блок в файл DWP**;
- **Переименовать блок**.

```json
"contexts": {
  "object.dwgtag": {
    "items": [ "id_block_edit", "-", "id_block_save", "id_block_rename" ]
  }
}
```

`object.dwgtag` — объектный контекст Robur для вставки блока (`DwgInsert`; в Robur вставка
называется «тэг»). Объект уже выбран (по нему и кликнули), поэтому `PickInsert` берёт его
из выделения без дополнительного запроса. Механизм и остальные ключи —
`ApiNotes/plugin.md` → «Контекстные меню».

## Как это устроено

1. Вставка блока → `DwgInsert.Block` — исходное определение блока.
2. `new Drawing()` — временный чертёж; сущности определения копируются в
   пространство модели через `Entities.CopyFrom(…)` + `ReferencesContext` (ссылки на
   слои, типы линий, вложенные блоки переразрешаются для нового чертежа).
3. Временный файл `RoburBlockEdit_*.dwp` в системном TEMP пишется как бэкап в **нативном
   формате Robur** (провайдер `NativeDwpExportProvider`: `Drawing.SaveToStg` → бинарный Stg,
   без Acax-моста); сам чертёж живёт в памяти.
4. Окно-редактор создаётся по эталону `[cmd("open_dwg_cmp")]` из
   `Topomatic.Dwg.Controller`: `Project.AddDocumentWindow` →
   `AddCadViewFrame(Consts.ModelFrame, "Модель")` → `DrawingLayer` (в нашем случае
   `Enable = true` — окно редактируемое) → `layer.Drawing = временный чертёж` →
   `SolveLimits(false)`/`Unlock()`/`Invalidate()`/`Activate()`.
   Все штатные команды чертежа (линия, круг, …) пишут правки прямо во временный
   чертёж в памяти — «дождаться правок» реализовано подпиской на `FormClosing`.
5. По закрытию окна: «Да» — `block.Entities.Clear()` + `CopyFrom(…)` обратно
   (в `BeginUpdate`/`EndUpdate` исходного чертежа), обновление экрана, удаление
   временного файла. «Нет» — правки отбрасываются, файл удаляется. «Отмена» —
   окно остаётся открытым.

## Сборка

```
./build-block-editor.sh          # Linux/WSL (dotnet msbuild)
msbuild BlockEditor.csproj /p:Configuration=Debug   # Windows
```

Вывод и ссылки — общий каталог `Development/Out/Bin/` (правило AGENTS.md;
`CopyLocal=false` на всех ссылках Robur). После установки в Robur выполните
`clearcache`, если плагин не подхватился.

## Структура

```
BlockEditor/
  BlockEditor.csproj      .NET Framework 4.8, LangVersion 7.3
  BlockEditor.plugin      манифест (actions + contexts + menubars rbproj)
  Module.cs               команды
  ModulePluginHost.cs     публичный хост
  Core/BlockOps.cs        операции с чертежами/блоками (выбор, копирование, слои)
  Core/BlockEditSession.cs сессия редактирования: окно + применение по закрытию
  build-tpm.sh            сборка + упаковка релиза (.tpm)
```

## Релиз: упаковка `.tpm`

`.tpm` — формат дистрибуции модулей Robur: **обычный ZIP** (deflate, без подписи;
целостность проверяется по SHA-256 ассета релиза). Состав пакета:

```
package.json          манифест пакета (обязателен)
bin/BlockEditor.dll   сборка модуля
plugins/BlockEditor.plugin
icons/                необязательно (densities 16dp/32dp × 1x…3x)
```

`package.json` — шесть полей: `name` (kebab-case id), `version` (semver), `caption`
(заголовок), `description`, `author`, `minVersion` (минимальная версия ПК, `"16.0"`).

```bash
./build-tpm.sh              # Debug → dist/BlockEditor-1.0.0.tpm + SHA-256
./build-tpm.sh Release
```

- **Версия берётся из `AssemblyInfo.cs`** (`AssemblyVersion("1.0.0.0")` → `1.0.0`) —
  единый источник истины; в `package.json` попадает без четвёртой части.
- Параметры пакета (`PKG_CAPTION`, `PKG_DESCRIPTION`, `PKG_AUTHOR`, …) задаются в
  начале `build-tpm.sh`.
- Скрипт печатает SHA-256 — его значение уходит в реестр пакетов как `tpm_sha256`.
- Зависимостей нет: упаковка на `python3` (`zipfile`), `zip` в WSL может отсутствовать.
- Каталог `dist/` в репозиторий не коммитится.

Проверка целостности/состава пакета:

```bash
sha256sum dist/BlockEditor-1.0.0.tpm
python3 -m zipfile -l dist/BlockEditor-1.0.0.tpm
```

Запись в реестре пакетов (`catalog.json`) — по образцу `RoadStyle`:

```json
{
  "name": "block-editor",
  "title": "Редактор блоков",
  "version": "1.0.0",
  "description": "…",
  "author": "Konstantin Zelensky",
  "tpm_url": "https://github.com/konstant16-Z/BlockEditor/releases/download/v1.0.0/BlockEditor-1.0.0.tpm",
  "tpm_sha256": "<SHA-256 из вывода скрипта>",
  "help_url": "…",
  "min_version": "16.0.62.12",
  "compatibility": ["Топоматик Robur — Автомобильные дороги", "…"]
}
```

Сборка `Debug` (то, что идёт в релиз — по конвенции каталога модулей Robur) —
`./build-tpm.sh Debug`; при необходимости `Release` — той же командой со вторым аргументом.

## Ограничения

- Редактируется само определение блока (локальные координаты), не трансформация
  вставки. Типы линий, отсутствующие в исходном чертеже, не переносятся — только
  слои (имя/цвет/видимость).
- **Формат сохранения — только `.dwp`**, нативный формат Robur
  (`NativeDwpExportProvider`: `StgDocument` + `drawing.SaveToStg(body)` +
  `SaveToStreamAsBinary` = BSTG). Все сущности Robur сохраняются без потерь, Acax-мост
  не требуется. Экспорт в DWG/DXF плагином не делается.
- Выбор провайдера по расширению — канон `tables_single_drawing`:
  `DrawingExportProvider.GetProvider(Path.GetExtension(file))` → фолбэк
  `GetPreferedProvider()` (тоже возвращает `.dwp` — `NativeDwpExportProvider`, Order 3009).
- Временный файл — резервная копия; при штатном сценарии файл удаляется. Если
  Robur падает до закрытия окна редактора, файл останется в TEMP.
- Запись требует зарегистрированного `NativeDwpExportProvider`
  (`Topomatic.Acax.Export.dll`). При его отсутствии редактирование всё равно работает
  (правки читаются из памяти), а команда сохранения покажет ошибку.