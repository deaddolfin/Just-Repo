#requires -Version 7.0
<#
    just_new.ps1 — сохранить только что выполненную команду как рецепт just.
    Аналог функции prev из pet, но для just.

    Подключение (это делает init.ps1 -WithShell):
        . C:\путь\к\репозиторию\just_new.ps1

    Использование:
        just_new                          взять последнюю команду из истории
        just_new -Command 'ls -la'        взять команду из аргумента
        just_new -Print                   только напечатать блок, ничего не писать
        just_new -Name logs -Desc 'логи'  имя и описание без вопросов
        just_new -Force                   не переспрашивать при конфликте имён

    Пишет ровно в один файл — local.just в каталоге конфигов. Файлы репозитория
    (Config\global.just, Config\<группа>\group.just) правятся редактором
    из каталога проекта, just_new их не трогает: для переноса туда есть -Print.
#>

function Get-JnConfigDir {
    if ($env:JUST_CONFIG_DIR) { return $env:JUST_CONFIG_DIR }
    return (Join-Path $env:APPDATA 'just')
}

function Get-JnState {
    param([string] $Key)
    $state = Join-Path (Get-JnConfigDir) 'state.env'
    if (-not (Test-Path -LiteralPath $state)) { return $null }
    foreach ($line in Get-Content -LiteralPath $state) {
        if ($line -match "^$Key=(.*)$") { return $Matches[1] }
    }
    return $null
}

# имена рецептов в just-файле (без alias, set, import и переменных)
function Get-JnRecipeNames {
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

function Get-JnAliasNames {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $names = foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^alias\s+([a-zA-Z_][a-zA-Z0-9_-]*)\s*:=') { $Matches[1] }
    }
    return @($names)
}

# блок рецепта: комментарий-описание + тело
function New-JnBlock {
    param([string] $Name, [string] $Desc, [string] $Command)

    # {{ }} в just — подстановка; литеральные скобки экранируются удвоением
    $cmd = $Command -replace '\{\{', '{{{{'

    $lines = @('')
    if ($Desc) { $lines += "# $Desc" }
    $lines += "${Name}:"
    if ($cmd -match "`n") {
        # многострочная команда — shebang-рецепт, иначе каждая строка уйдёт
        # в свой шелл и рабочий каталог не переживёт перевод строки
        $lines += '    #!/usr/bin/env pwsh'
        foreach ($l in ($cmd -split "`r?`n")) { $lines += "    $l" }
    } else {
        $lines += "    $cmd"
    }
    return $lines
}

# удалить прежнее определение рецепта вместе с описанием и телом
function Remove-JnRecipe {
    param([string] $Path, [string] $Name)

    $lines = @(Get-Content -LiteralPath $Path)
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^$([regex]::Escape($Name))(\s+[^:=]*)?:([^=].*)?$") { $start = $i; break }
    }
    if ($start -lt 0) { return $false }

    $b = $start
    while ($b -gt 0 -and ($lines[$b - 1] -match '^\s*#' -or $lines[$b - 1] -match '^\[')) { $b-- }

    $e = $start
    while ($e + 1 -lt $lines.Count -and ($lines[$e + 1] -eq '' -or $lines[$e + 1] -match '^\s')) { $e++ }

    $kept = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -ge $b -and $i -le $e) { continue }
        $kept += $lines[$i]
    }
    [IO.File]::WriteAllText($Path, (($kept -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    return $true
}

function Read-JnInput {
    param([string] $Prompt)
    # в неинтерактивной оболочке Read-Host бросает исключение — возвращаем $null,
    # чтобы вызывающий код подсказал нужный ключ вместо стектрейса
    try { return (Read-Host $Prompt) } catch { return $null }
}

function just_new {
    [CmdletBinding()]
    param(
        [string] $Command,
        [string] $Name,
        [string] $Desc,
        [switch] $Print,
        [switch] $Force
    )

    $configDir = Get-JnConfigDir
    $localFile = Join-Path $configDir 'local.just'
    $justFile  = Join-Path $configDir 'justfile'
    $repo      = Get-JnState 'JUST_REPO'

    if (-not (Test-Path -LiteralPath $justFile)) {
        Write-Error "нет $justFile — сначала выполните .\init.ps1 <группа>"
        return
    }

    # --- команда ---
    if (-not $Command) {
        $history = @(Get-History)
        for ($i = $history.Count - 1; $i -ge 0; $i--) {
            $candidate = $history[$i].CommandLine.Trim()
            if ($candidate -and $candidate -notmatch '^\s*just_new\b') {
                $Command = $candidate
                break
            }
        }
    }
    if (-not $Command) {
        Write-Error 'история пуста. Передайте команду явно: just_new -Command ''<команда>'''
        return
    }

    Write-Host "команда: $Command"

    # --- имя рецепта ---
    if (-not $Name) {
        $Name = Read-JnInput 'имя рецепта'
        if ($null -eq $Name) {
            Write-Error 'нет имени рецепта: в неинтерактивной оболочке передайте -Name'
            return
        }
        $Name = $Name.Trim()
    }
    if ($Name -notmatch '^[a-zA-Z_][a-zA-Z0-9_-]*$') {
        Write-Error "недопустимое имя рецепта: «$Name»"
        return
    }
    if (-not $PSBoundParameters.ContainsKey('Desc')) {
        $Desc = Read-JnInput 'описание (Enter — пропустить)'
        if ($null -eq $Desc) { $Desc = '' } else { $Desc = $Desc.Trim() }
    }

    # --- проверка имени по всем трём файлам ---
    $inLocal  = $Name -in (Get-JnRecipeNames (Join-Path $configDir 'local.just'))
    $inGroup  = $Name -in (Get-JnRecipeNames (Join-Path $configDir 'group.just'))
    $inGlobal = $Name -in (Get-JnRecipeNames (Join-Path $configDir 'global.just'))

    $aliasHit = $null
    foreach ($label in @('global', 'group', 'local')) {
        if ($Name -in (Get-JnAliasNames (Join-Path $configDir "$label.just"))) { $aliasHit = $label; break }
    }
    if ($aliasHit) {
        Write-Host "just_new: «$Name» — это alias в $aliasHit.just." -ForegroundColor Yellow
        Write-Host '  Дубликаты алиасов just не прощает: конфиг перестанет разбираться целиком.'
        Write-Host '  Возьмите другое имя.'
        return
    }

    if ($inGroup -or $inGlobal) {
        $src = if ($inGroup -and $inGlobal) { 'group.just и global.just' }
               elseif ($inGroup) { 'group.just' } else { 'global.just' }
        Write-Host ''
        Write-Host "  ВНИМАНИЕ: рецепт «$Name» приезжает из репозитория ($src)." -ForegroundColor Yellow
        Write-Host '  Запись в local.just создаст локальное переопределение: local импортируется'
        Write-Host '  первым, а just берёт первое определение. Общая команда на этой машине перестанет'
        Write-Host '  работать так же, как на других.'
        Write-Host "  Общую команду правят в $repo\Config — отсюда туда just_new не пишет."
        Write-Host ''
        if (-not $Print -and -not $Force) {
            $answer = Read-JnInput 'переопределить локально? [y/N/имя другого рецепта]'
            if ($null -eq $answer) {
                Write-Host 'отменено: подтвердить перекрытие в неинтерактивной оболочке можно ключом -Force'
                return
            }
            switch -Regex ($answer) {
                '^(y|Y|yes|да)$' { }
                '^(|n|N|no|нет)$' { Write-Host 'отменено'; return }
                default {
                    $Name = $answer.Trim()
                    if ($Name -notmatch '^[a-zA-Z_][a-zA-Z0-9_-]*$') {
                        Write-Error "недопустимое имя рецепта: «$Name»"
                        return
                    }
                    $inLocal = $Name -in (Get-JnRecipeNames $localFile)
                }
            }
        }
    }

    if ($inLocal -and -not $Print -and -not $Force) {
        $answer = Read-JnInput "рецепт «$Name» уже есть в local.just, заменить? [y/N]"
        if ($null -eq $answer) {
            Write-Host 'отменено: заменить в неинтерактивной оболочке можно ключом -Force'
            return
        }
        if ($answer -notmatch '^(y|Y|yes|да)$') { Write-Host 'отменено'; return }
    }

    # --- вывод или запись ---
    $block = New-JnBlock -Name $Name -Desc $Desc -Command $Command
    if ($Print) {
        Write-Host ''
        Write-Host '--- блок для вставки ---'
        $block | ForEach-Object { Write-Host $_ }
        Write-Host '------------------------'
        return
    }

    if (-not (Test-Path -LiteralPath $localFile)) {
        [IO.File]::WriteAllText($localFile, "# local.just — алиасы только этой машины.`n", [Text.UTF8Encoding]::new($false))
    }
    $backup = "$localFile.bak"
    Copy-Item -LiteralPath $localFile -Destination $backup -Force

    if ($inLocal) { [void] (Remove-JnRecipe -Path $localFile -Name $Name) }
    $current = [IO.File]::ReadAllText($localFile)
    if ($current -and -not $current.EndsWith("`n")) { $current += "`n" }
    [IO.File]::WriteAllText($localFile, $current + (($block -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

    & just --justfile $justFile --working-directory . --summary *> $null
    if ($LASTEXITCODE -eq 0) {
        Remove-Item -LiteralPath $backup -Force
        Write-Host "записано в $localFile"
        if ($inGroup -or $inGlobal) {
            $loser = if ($inGlobal) { 'global.just' } else { 'group.just' }
            Write-Host "${Name}: local.just перекрывает $loser"
        }
        Write-Host "проверить: just --justfile `"$justFile`" --list"
    } else {
        Copy-Item -LiteralPath $backup -Destination $localFile -Force
        Remove-Item -LiteralPath $backup -Force
        Write-Host 'just не разобрал результат, изменения отменены:' -ForegroundColor Red
        & just --justfile $justFile --working-directory . --summary
    }
}
