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
.\build-tpm.ps1                      # Debug + упаковка в dist\
.\build-tpm.ps1 -Configuration Release
```

Скрипт выводит путь к пакету и его SHA-256 — это значение уходит в
`catalog.json` (`tpm_sha256`) и в заметки релиза.

Аналог для WSL/Linux — `./build-tpm.sh` (тот же состав пакета; хеш совпадает,
пока метаданные в zip не трогаются).

## Версия

Берётся из `package.json` в корне репозитория (поле `version`) — он же попадает
в имя файла `BlockEditor-<версия>.tpm`. Меняете версию один раз в `package.json`;
`AssemblyInfo.cs` держите синхронно (`AssemblyVersion`).