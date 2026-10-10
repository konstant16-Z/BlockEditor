<#
    Упаковка релиза BlockEditor в .tpm (Windows).

    Общий сборщик лежит в репозитории Shared — клон рядом с проектом:
        ..\Shared\BuildTpm.Common.ps1        (BlockEditor отдельным клоном)
        ..\..\Shared\BuildTpm.Common.ps1     (BlockEditor внутри PluginExample-main,
                                              Shared — субмодуль рядом)
        ..\..\..\Shared\BuildTpm.Common.ps1  (Shared рядом с клоном PluginExample-main)
    Клонируется один раз:
        git clone https://github.com/konstant16-Z/Shared C:\OpnCod_Proj\Shared

    Аналог для WSL/Linux — build-tpm.sh (тот же состав пакета и тот же SHA-256).
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Debug',
    [string]$Corpus = 'new',      # new (16.0.62.x) | old (16.0.50.x) | произвольный путь
    [string]$OutDir = ''          # по умолчанию <корень проекта>\dist
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }

# Каталог сборок корпуса: Development/Out может лежать на уровень выше (BlockEditor —
# субмодуль PluginExample-main) или на два (отдельный клон рядом).
function Resolve-Corpus([string]$variant) {
    foreach ($c in @((Join-Path $root "..\Development\Out\$variant"),
                     (Join-Path $root "..\..\Development\Out\$variant"),
                     (Join-Path $root "Development\Out\$variant"))) {
        if (Test-Path -LiteralPath (Join-Path $c 'Topomatic.ApplicationPlatform.dll')) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return $null
}

if ($Corpus -eq 'new') {
    $corpusDir = Resolve-Corpus 'Bin'; $corpusLabel = 'new (16.0.62.x)'
} elseif ($Corpus -eq 'old') {
    $corpusDir = Resolve-Corpus 'Bin_16_50'; $corpusLabel = 'old (16.0.50.x)'
} else {
    $corpusDir = $Corpus; $corpusLabel = $Corpus
}
if (-not $corpusDir) { throw "Не найдены сборки Robur для корпуса '$Corpus' (искал Development/Out/* выше по дереву)." }
$corpusDir = (Resolve-Path -LiteralPath $corpusDir).Path

$common = @(
    (Join-Path $root '..\Shared\BuildTpm.Common.ps1'),
    (Join-Path $root '..\..\Shared\BuildTpm.Common.ps1'),
    (Join-Path $root '..\..\..\Shared\BuildTpm.Common.ps1')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $common) {
    throw @"
Не найден общий сборщик BuildTpm.Common.ps1 (искали в ..\Shared, ..\..\Shared, ..\..\..\Shared).
Клонируйте репозиторий Shared рядом с проектом:
    git clone https://github.com/konstant16-Z/Shared C:\OpnCod_Proj\Shared
"@
}

. $common

# Версия — из package.json в корне (единственный источник истины).
$package = Get-Content (Join-Path $root 'package.json') -Raw | ConvertFrom-Json
$version = $package.version
if (-not $version) { throw 'В package.json нет поля version.' }

# Сборка: .NET SDK (dotnet msbuild) или полный msbuild из PATH
Write-Host "==> Сборка ($Configuration, корпус $corpusLabel)" -ForegroundColor Cyan
$proj = Join-Path $root 'BlockEditor\BlockEditor.csproj'
$roburProp = "/p:RoburBinDir=$corpusDir\"
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    & dotnet msbuild $proj "/p:Configuration=$Configuration" $roburProp -v:q -nologo
} else {
    & msbuild $proj "/p:Configuration=$Configuration" $roburProp -v:q -nologo
}
if ($LASTEXITCODE -ne 0) { throw "Сборка вернула $LASTEXITCODE" }

# Упаковка
Write-Host '==> Упаковка' -ForegroundColor Cyan
Build-AbrTpm `
    -Base $root `
    -TpmName 'BlockEditor' `
    -DllPath (Join-Path $corpusDir 'BlockEditor.dll') `
    -PluginFiles @('BlockEditor.plugin') `
    -OutDir $OutDir

$tpmPath = Join-Path $OutDir "BlockEditor-$version.tpm"
Write-Host ''
Write-Host "Готово: $tpmPath" -ForegroundColor Green
Write-Host 'SHA-256 (в catalog.json -> tpm_sha256):'
(Get-FileHash $tpmPath -Algorithm SHA256).Hash.ToLower()