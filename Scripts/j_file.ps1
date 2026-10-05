#requires -Version 7.0
<#
    j_file.ps1 — работа с файлами по псевдониму: j_edit и j_tail.
    Парный к go_dir: тот переходит в каталог, эти открывают и читают файл.

    Подключается блоком из init.ps1 (-WithShell):
        . C:\путь\к\репозиторию\Scripts\j_file.ps1

    Использование:
        j_edit                       список псевдонимов с описаниями
        j_edit <псевдоним>           открыть файл в редакторе
        j_tail <псевдоним>           напечатать файл целиком
        j_tail <псевдоним> -n 50     последние 50 строк
        j_tail <псевдоним> -f        последние 10 строк и следить за дополнениями
        j_tail <псевдоним> -n 5 -f   последние 5 строк и следить

    Опции j_tail — в стиле tail: -n (--lines) и -f (--follow), число — только цифры.
    Остальные опции tail отклоняются. Аналог tail — Get-Content -Tail / -Wait; Ctrl-C
    прерывает слежение.

    Редактор: $env:VISUAL, затем $env:EDITOR, иначе notepad (как в рецептах elocal и
    egroup из global.just). Значение с аргументами (code -w) допускается.

    Псевдоним — рецепт just из группы j_file (global.just, group.just или local.just),
    который печатает ОДИН путь к файлу:

        # Лог приложения
        [group('j_file')]
        file_app_log:
            @echo 'C:\logs\app.log'

    Запускается только рецепт из группы j_file. Разбор и запуск — в just_alias.ps1;
    завести псевдоним помогает just_file.
#>

if (-not (Get-Command just -CommandType Application -ErrorAction SilentlyContinue)) { return }

if (-not (Get-Command Resolve-JaAlias -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'just_alias.ps1')
}

function j_edit {
    [CmdletBinding()]
    param([Parameter(Position = 0)] [string] $Alias)

    if (-not $Alias) { Show-JaList -Caller 'j_edit' -Group 'j_file'; return }

    $file = Resolve-JaAlias -Caller 'j_edit' -Group 'j_file' -Alias $Alias
    if (-not $file) { return }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Error "j_edit: файла нет: $file (псевдоним $Alias)"
        return
    }

    $ed = if ($env:VISUAL) { $env:VISUAL } elseif ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
    # путь к программе мог содержать пробелы; иначе значение — команда с аргументами («code -w»)
    if (Test-Path -LiteralPath $ed -PathType Leaf) {
        $exe = $ed; $edArgs = @()
    } else {
        $parts  = @($ed -split '\s+' | Where-Object { $_ })
        $exe    = $parts[0]
        $edArgs = @($parts | Select-Object -Skip 1)
    }
    & $exe @edArgs $file
}

# ValueFromRemainingArguments собирает -n, -f, --lines как обычные строки (PowerShell не
# пытается трактовать их как параметры функции); так же работает и Tab для опций.
function j_tail {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string] $Alias,
        [Parameter(ValueFromRemainingArguments)] [string[]] $TailArgs
    )

    if (-not $Alias) { Show-JaList -Caller 'j_tail' -Group 'j_file'; return }

    # опции проверяются до запуска рецепта: читаем только известное
    # не через конвейер и не через выражение if: пустой $TailArgs стал бы там одним пустым
    # элементом, а массив из одного элемента — строкой (и $rest[0] дал бы первый символ)
    [string[]] $rest = @()
    if ($TailArgs) { $rest = $TailArgs }
    $lines  = $null
    $follow = $false
    for ($i = 0; $i -lt $rest.Count; $i++) {
        $a = $rest[$i]
        if ($a -ceq '-n' -or $a -ceq '--lines') {
            if ($i + 1 -ge $rest.Count) { Write-Error "j_tail: у $a нужно число строк"; return }
            $i++
            $v = $rest[$i]
        } elseif ($a -cmatch '^-n([0-9].*)$') {
            $v = $Matches[1]
        } elseif ($a -cmatch '^--lines=(.*)$') {
            $v = $Matches[1]
        } elseif ($a -ceq '-f' -or $a -ceq '--follow') {
            $follow = $true
            continue
        } else {
            Write-Error ("j_tail: неподдерживаемая опция: $a`n  Поддерживаются: -n N (--lines N), -f (--follow)")
            return
        }
        if ($v -notmatch '^[0-9]+$' -or $v.Length -gt 9) {
            Write-Error "j_tail: число строк должно состоять из цифр (до 9): «$v»"
            return
        }
        $lines = [int]$v
    }

    $file = Resolve-JaAlias -Caller 'j_tail' -Group 'j_file' -Alias $Alias
    if (-not $file) { return }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Error "j_tail: файла нет: $file (псевдоним $Alias)"
        return
    }

    if ($null -eq $lines -and -not $follow) {
        Get-Content -LiteralPath $file
        return
    }
    $gc = @{ LiteralPath = $file; Tail = $(if ($null -ne $lines) { $lines } else { 10 }) }
    if ($follow) { $gc.Wait = $true }
    Get-Content @gc
}

Register-ArgumentCompleter -CommandName j_edit -ParameterName Alias -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-JaCompletion -Group 'j_file' -WordToComplete $wordToComplete
}

Register-ArgumentCompleter -CommandName j_tail -ParameterName Alias -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-JaCompletion -Group 'j_file' -WordToComplete $wordToComplete
}

# после псевдонима предлагаются опции tail (набранное «-» PowerShell трактует как имя
# параметра функции, поэтому надёжнее всего работает после пробела и с «--»)
Register-ArgumentCompleter -CommandName j_tail -ParameterName TailArgs -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    foreach ($o in '-n', '-f', '--lines', '--follow') {
        if ($o -like "$wordToComplete*") {
            [System.Management.Automation.CompletionResult]::new($o, $o, 'ParameterValue', $o)
        }
    }
}
