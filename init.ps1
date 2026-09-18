#requires -Version 7.0
<#
.SYNOPSIS
    Развернуть just-конфигурацию этого репозитория на текущей машине (Windows).

.DESCRIPTION
    Создаёт основной justfile в каталоге конфигов just (%APPDATA%\just),
    симлинки на общий файл и файл группы из репозитория, пустой local.just
    для машинных алиасов и env с переменными окружения (права — только
    текущему пользователю).

    Скрипт идемпотентен: повторный запуск не трогает local.just и env.

.PARAMETER Group
    Имя группы — каталог внутри Config\.

.PARAMETER WithShell
    Дописать интеграцию (функция j, автодополнение, just_new) в $PROFILE
    между маркерами. Без флага блок просто печатается.

.EXAMPLE
    .\init.ps1 example
    .\init.ps1 -Group example -WithShell
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Group,

    [switch] $WithShell
)

$ErrorActionPreference = 'Stop'

$MinJust    = [version]'1.35.0'
$RepoDir    = $PSScriptRoot
$ConfigDir  = Join-Path $env:APPDATA 'just'
$MarkBegin  = '# >>> just-aliases >>>'
$MarkEnd    = '# <<< just-aliases <<<'

function Write-Step { param([string] $Text) Write-Host "`n== $Text" }
function Write-Info { param([string] $Text) Write-Host "   $Text" }
function Write-Warn { param([string] $Text) Write-Warning $Text }
function Stop-WithError { param([string] $Text) Write-Error $Text; exit 1 }

function Get-AvailableGroups {
    Get-ChildItem -Path (Join-Path $RepoDir 'Config') -Directory |
        Select-Object -ExpandProperty Name
}

function Show-Usage {
    Write-Host 'Использование: .\init.ps1 [-WithShell] <группа>'
    Write-Host ''
    Write-Host 'Группы, доступные в этом репозитории:'
    Get-AvailableGroups | ForEach-Object { Write-Host "  - $_" }
}

# имена рецептов в just-файле (без alias, set, import и переменных)
function Get-RecipeNames {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $names = foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([a-zA-Z_][a-zA-Z0-9_-]*)(\s+[^:=]*)?:([^=].*)?$') {
            $name = $Matches[1]
            if ($name -notin @('set', 'alias', 'import', 'export', 'mod')) { $name }
        }
    }
    return @($names)
}

function Get-EnvKeys {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $keys = foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=') { $Matches[1] }
    }
    return @($keys)
}

function Get-JustVersion {
    $raw = (& just --version) 2>$null
    if (-not $raw) { return $null }
    $token = ($raw -split '\s+')[1]
    try { return [version]($token -replace '[^0-9.].*$', '') } catch { return $null }
}

# --- разбор аргументов ------------------------------------------------------

if (-not $Group) {
    Show-Usage
    Stop-WithError 'не указана группа'
}
$GroupDir = Join-Path (Join-Path $RepoDir 'Config') $Group
if (-not (Test-Path -LiteralPath $GroupDir -PathType Container)) {
    Show-Usage
    Stop-WithError "группы «$Group» нет в $RepoDir\Config"
}
if (-not (Test-Path -LiteralPath (Join-Path $GroupDir 'group.just'))) {
    Stop-WithError "в группе «$Group» нет файла group.just"
}

# --- 1. just ----------------------------------------------------------------

function Install-Just {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info 'пробую winget install Casey.Just'
        & winget install --id Casey.Just --source winget --accept-package-agreements --accept-source-agreements 2>&1 |
            Out-Null
    }
    if (-not (Get-Command just -ErrorAction SilentlyContinue)) {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Info 'пробую scoop install just'
            & scoop install just 2>&1 | Out-Null
        }
    }
    if (-not (Get-Command just -ErrorAction SilentlyContinue)) {
        if (Get-Command cargo -ErrorAction SilentlyContinue) {
            Write-Info 'пробую cargo install just'
            & cargo install just 2>&1 | Out-Null
        }
    }
    # PATH мог измениться внутри сессии установщика
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

Write-Step 'just'
$justVersion = $null
if (Get-Command just -ErrorAction SilentlyContinue) { $justVersion = Get-JustVersion }

if ($justVersion -and $justVersion -ge $MinJust) {
    Write-Info "уже установлен: just $justVersion"
} else {
    if ($justVersion) {
        Write-Warn "just $justVersion старее требуемой $MinJust (нужны allow-duplicate-variables и import?)"
    } else {
        Write-Info 'не найден'
    }
    Install-Just
    $justVersion = Get-JustVersion
    if (-not $justVersion) {
        Stop-WithError 'не удалось установить just — поставьте вручную: https://just.systems'
    }
    if ($justVersion -lt $MinJust) {
        Stop-WithError "установлен just $justVersion, нужна $MinJust или новее"
    }
    Write-Info "установлен just $justVersion"
}

# --- 2. каталог конфигов ----------------------------------------------------

Write-Step 'каталог конфигов'
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
Write-Info $ConfigDir

# группа прошлого развёртывания — нужна, чтобы предупредить о смене
$PrevGroup = $null
$statePath = Join-Path $ConfigDir 'state.env'
if (Test-Path -LiteralPath $statePath) {
    foreach ($line in Get-Content -LiteralPath $statePath) {
        if ($line -match '^JUST_GROUP=(.*)$') { $PrevGroup = $Matches[1]; break }
    }
}
if ($PrevGroup -and $PrevGroup -ne $Group) {
    Write-Info "группа меняется: $PrevGroup -> $Group"
}

# --- 3. основной justfile ---------------------------------------------------

Write-Step 'основной justfile'
$JustFile = Join-Path $ConfigDir 'justfile'
$EnvFile  = Join-Path $ConfigDir 'env'

# Пути пишем в одинарных кавычках: в just это «сырая» строка,
# обратные слэши Windows не превращаются в escape-последовательности.
$justfileText = @"
# Создан init.ps1 из $RepoDir — правки здесь перетираются при следующем запуске.
# Свои команды: local.just (машинные) или файлы репозитория (общие).

set shell := ["pwsh", "-NoLogo", "-NoProfile", "-Command"]
set allow-duplicate-recipes := true
set allow-duplicate-variables := true
set dotenv-path := '$EnvFile'

repo       := '$RepoDir'
group      := '$Group'
config_dir := '$ConfigDir'

# Приоритет задаёт порядок импортов: побеждает ПЕРВОЕ определение рецепта,
# поэтому local идёт первым и перекрывает group, а group — global.
import? 'local.just'
import  'group.just'
import  'global.just'

default:
    @just --list --unsorted
"@ -replace "`r`n", "`n"

$existing = if (Test-Path -LiteralPath $JustFile) {
    [IO.File]::ReadAllText($JustFile)
} else { $null }

if ($existing -and $existing -ne $justfileText) {
    Copy-Item -LiteralPath $JustFile -Destination "$JustFile.bak" -Force
    Write-Info 'прежний justfile сохранён как justfile.bak'
}
[IO.File]::WriteAllText($JustFile, $justfileText, [Text.UTF8Encoding]::new($false))
Write-Info "записан $JustFile"

# --- 4. симлинки на файлы репозитория ---------------------------------------

function New-RepoLink {
    param([string] $Source, [string] $Target)

    if (-not (Test-Path -LiteralPath $Source)) { Stop-WithError "нет файла $Source" }

    # Обычный файл на месте ссылки бэкапим только если он отличается от файла
    # репозитория — иначе это копия с прошлого запуска, и .bak ни к чему.
    $item = Get-Item -LiteralPath $Target -ErrorAction SilentlyContinue
    if ($item -and -not $item.LinkType) {
        $same = (Get-FileHash -LiteralPath $Target).Hash -eq (Get-FileHash -LiteralPath $Source).Hash
        if (-not $same) {
            Copy-Item -LiteralPath $Target -Destination "$Target.bak" -Force
            Write-Warn "$(Split-Path -Leaf $Target) был обычным файлом, копия — $(Split-Path -Leaf $Target).bak"
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force -ErrorAction Stop | Out-Null
        Write-Info "$(Split-Path -Leaf $Target) -> $Source"
    } catch {
        Write-Warn "не удалось создать симлинк $Target"
        Write-Warn 'Windows разрешает симлинки только с правами администратора или при'
        Write-Warn 'включённом режиме разработчика: Параметры → Система → Для разработчиков.'
        Write-Warn 'Жёсткая ссылка не поможет: репозиторий и профиль на разных томах.'
        Stop-WithError 'включите режим разработчика и повторите запуск'
    }
}

Write-Step 'файлы репозитория'
New-RepoLink -Source (Join-Path $RepoDir 'Config\global.just')  -Target (Join-Path $ConfigDir 'global.just')
New-RepoLink -Source (Join-Path $GroupDir 'group.just')         -Target (Join-Path $ConfigDir 'group.just')

# --- 5. локальный файл ------------------------------------------------------

Write-Step 'локальные алиасы'
$LocalFile = Join-Path $ConfigDir 'local.just'
if (Test-Path -LiteralPath $LocalFile) {
    Write-Info 'local.just уже есть — не трогаю'
} else {
    $localText = @"
# local.just — алиасы и переменные только этой машины.
# В репозиторий не попадает. Сюда же пишет just_new.
# Одноимённый рецепт здесь перекрывает такой же из group.just и global.just.
"@ -replace "`r`n", "`n"
    [IO.File]::WriteAllText($LocalFile, $localText, [Text.UTF8Encoding]::new($false))
    Write-Info "создан $LocalFile"
}

# --- 6. переменные окружения ------------------------------------------------

Write-Step 'переменные окружения'
$ExGlobal = Join-Path $RepoDir 'Config\env.example'
$ExGroup  = Join-Path $GroupDir 'env.example'

function Protect-File {
    param([string] $Path)
    # снять наследование и оставить доступ только текущему пользователю;
    # права выдаём по SID: имя вида LEGIONPC icacls принимает за домен
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls $Path /inheritance:r /grant:r "*${sid}:(F)" | Out-Null
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
    $parts = @(
        '# Локальные значения переменных. Собрано init.ps1 из *.example.',
        '# В репозиторий не возвращается.',
        ''
    )
    foreach ($ex in @($ExGlobal, $ExGroup)) {
        if (Test-Path -LiteralPath $ex) {
            $parts += (Get-Content -LiteralPath $ex)
            $parts += ''
        }
    }
    [IO.File]::WriteAllText($EnvFile, (($parts -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Protect-File -Path $EnvFile
    Write-Info "создан $EnvFile (доступ только вам) — заполните значения"
} else {
    Protect-File -Path $EnvFile
    Write-Info 'env уже есть — не трогаю'
    if ($PrevGroup -and $PrevGroup -ne $Group) {
        Write-Warn "группа сменилась ($PrevGroup -> $Group), а env остался прежним: переменные новой группы сами не появятся, лишние от старой не исчезнут"
    }
    $expected = @(Get-EnvKeys $ExGlobal) + @(Get-EnvKeys $ExGroup) | Sort-Object -Unique
    $actual   = @(Get-EnvKeys $EnvFile) | Sort-Object -Unique
    $missing  = @($expected | Where-Object { $_ -notin $actual })
    $extra    = @($actual   | Where-Object { $_ -notin $expected })
    if ($missing) { Write-Warn "в env нет ключей из *.example: $($missing -join ' ')" }
    if ($extra)   { Write-Info "в env есть ключи, которых нет в *.example: $($extra -join ' ')" }
}

# --- 7. состояние для just_new ----------------------------------------------

Write-Step 'состояние'
$stateText = @(
    "JUST_REPO=$RepoDir",
    "JUST_GROUP=$Group",
    "JUST_CONFIG_DIR=$ConfigDir"
) -join "`n"
[IO.File]::WriteAllText((Join-Path $ConfigDir 'state.env'), $stateText + "`n", [Text.UTF8Encoding]::new($false))
Write-Info "записан $(Join-Path $ConfigDir 'state.env')"

# --- 8. интеграция с шеллом -------------------------------------------------

$shellBlock = @(
    $MarkBegin,
    "function j { just --justfile `"$JustFile`" --working-directory . @args }",
    "Register-ArgumentCompleter -CommandName j -ScriptBlock {",
    "    param(`$wordToComplete)",
    "    (just --justfile `"$JustFile`" --summary) -split '\s+' |",
    "        Where-Object { `$_ -like `"`$wordToComplete*`" } |",
    "        ForEach-Object { [Management.Automation.CompletionResult]::new(`$_) }",
    "}",
    ". `"$RepoDir\just_new.ps1`"",
    $MarkEnd
)

Write-Step 'интеграция с шеллом'
if ($WithShell) {
    $profilePath = $PROFILE.CurrentUserAllHosts
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
    $lines = if (Test-Path -LiteralPath $profilePath) { @(Get-Content -LiteralPath $profilePath) } else { @() }

    if ($lines -contains $MarkBegin) {
        $kept = @()
        $skip = $false
        foreach ($line in $lines) {
            if ($line -eq $MarkBegin) { $skip = $true; continue }
            if ($line -eq $MarkEnd)   { $skip = $false; continue }
            if (-not $skip) { $kept += $line }
        }
        $lines = $kept
        Write-Info 'прежний блок в профиле заменён'
    }
    $lines += $shellBlock
    [IO.File]::WriteAllText($profilePath, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Write-Info "блок добавлен в $profilePath — перезапустите оболочку или выполните: . `$PROFILE.CurrentUserAllHosts"
} else {
    Write-Info 'добавьте в профиль (или перезапустите с ключом -WithShell):'
    Write-Host ''
    $shellBlock | ForEach-Object { Write-Host "      $_" }
}

# --- 9. проверка и отчёт о перекрытиях --------------------------------------

Write-Step 'проверка'
& just --justfile $JustFile --working-directory . --summary *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Info "конфигурация разбирается, список команд: just --justfile `"$JustFile`" --list"
} else {
    Write-Warn 'just не смог разобрать конфигурацию:'
    & just --justfile $JustFile --working-directory . --summary
}

$byName = @{}
foreach ($label in @('local', 'group', 'global')) {
    $path = Join-Path $ConfigDir "$label.just"
    foreach ($name in (Get-RecipeNames $path | Sort-Object -Unique)) {
        if (-not $byName.ContainsKey($name)) { $byName[$name] = @() }
        $byName[$name] += $label
    }
}
$shadowed = $byName.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | Sort-Object Name
if ($shadowed) {
    Write-Host ''
    Write-Host '   Перекрытые рецепты (побеждает первое определение: local > group > global):'
    foreach ($entry in $shadowed) {
        $winner = $entry.Value[0]
        Write-Host ("     {0,-20} определён в: {1} — работает {2}" -f $entry.Key, ($entry.Value -join ', '), $winner)
    }
}

Write-Host ''
Write-Host "Готово. Группа «$Group», конфигурация в $ConfigDir"
