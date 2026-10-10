# Редактор блоков — упаковка релиза (.tpm) под Windows

Использует общий сборщик из репозитория [`konstant16-Z/Shared`](https://github.com/konstant16-Z/Shared)
(`BuildTpm.Common.ps1`) — те же правила упаковки, что у Runoff и DemLoader.

## Требования

Репозиторий `Shared` должен лежать **рядом** (путь `..\Shared\BuildTpm.Common.ps1`):

```
c:\OpnCod_Proj\
├── PluginExample-main\        (или отдельный клон BlockEditor)
│   └── BlockEditor\
└── Shared\
    └── BuildTpm.Common.ps1
```

Клонировать:

```powershell
git clone https://github.com/konstant16-Z/Shared C:\OpnCod_Proj\Shared
```

## Сборка пакета

```powershell
.\build-tpm.ps1                            # Debug + корпус 16.0.62.x
.\build-tpm.ps1 -Configuration Release
.\build-tpm.ps1 -Corpus old                # корпус 16.0.50.x (локально, не публикуется)
```

Скрипт выводит путь к пакету и его SHA-256 — это значение уходит в
`catalog.json` (`tpm_sha256`) и в заметки релиза.

Аналог для WSL/Linux — `./build-tpm.sh [Debug|Release] [new|old|путь]`
(тот же состав пакета).

## Корпуса

| Корпус | Каталог сборок | Версия | Публикуется |
|---|---|---|---|
| `new` | `Development/Out/Bin` | 16.0.62.12 | да (релизы GitHub) |
| `old` | `Development/Out/Bin_16_50` | 16.0.50.7 | нет, только локально |

Проверка совместимости собранного плагина — штатный инструмент репозитория:

```
./apiq missing Development/Out/Bin_16_50/BlockEditor.dll Bin_16_50
```

Для обоих корпусов ожидается `отсутствует: 0; нет типов: 0` (расхождения сигнатур
в отчёте — перегрузки методов, они не блокеры).

## Версия

Берётся из `package.json` в корне репозитория (поле `version`) — он же попадает
в имя файла `BlockEditor-<версия>.tpm`. Меняете версию один раз в `package.json`;
`AssemblyInfo.cs` держите синхронно (`AssemblyVersion`).