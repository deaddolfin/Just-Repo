#requires -Version 7.0
<#
    go_dir.ps1 — перейти в каталог по псевдониму.

    Подключается блоком из init.ps1 (-WithShell):
        . C:\путь\к\репозиторию\Scripts\go_dir.ps1

    Использование:
        go_dir                 список псевдонимов с описаниями
        go_dir <псевдоним>     Set-Location в каталог, на который указывает псевдоним

    Это функция, а не скрипт: каталог меняется в текущей оболочке.

    Псевдоним — рецепт just из группы go_dir (global.just, group.just или local.just),
    который печатает ОДИН путь:

        # Папка проекта
        [group('go_dir')]
        dir_project:
            @echo '/home/workers/ParserService'

    Рецепт без параметров и не [private] (приватные скрыты из `just --list`, по нему
    и строится список). Источник — всегда глобальный justfile (`just -g`).

    Запускается только рецепт из группы go_dir: иначе `go_dir restart` выполнил бы
    произвольный рецепт, а не перешёл в каталог.

    GO_DIR_JUSTFILE — служебная переменная для отладки: если задана, вместо -g
    берётся этот justfile.
#>

if (-not (Get-Command just -CommandType Application -ErrorAction SilentlyContinue)) { return }

# just с глобальным justfile либо с файлом из GO_DIR_JUSTFILE
function Invoke-GoDirJust {
    param([string[]] $JustArgs)
    $exe = (Get-Command just -CommandType Application | Select-Object -First 1).Source
    if ($env:GO_DIR_JUSTFILE) {
        & $exe --justfile $env:GO_DIR_JUSTFILE --working-directory . @JustArgs
    } else {
        & $exe -g @JustArgs
    }
}

# рецепты группы go_dir: объекты {Name, Description}
function Get-GoDirAlias {
    param([string] $Group = 'go_dir')

    $lines = Invoke-GoDirJust -JustArgs @('--list', '--unsorted', '--color', 'never',
                                          '--list-heading', '', '--list-prefix', '') 2>$null
    $cur = $null
    foreach ($raw in $lines) {
        $line = "$raw".TrimEnd("`r")
        if ($line -match '^\[(.+)\]$') { $cur = $Matches[1]; continue }
        if ($line -match '^\s*$')      { continue }
        if ($cur -ne $Group)           { continue }
        # имя без параметров, затем необязательное « # описание»
        if ($line -match '^(\S+)(?:\s+#\s*(.*))?$') {
            $desc = "$($Matches[2])" -replace '\s*\[alias: [^\]]*\]$', ''
            [pscustomobject]@{ Name = $Matches[1]; Description = $desc }
        }
    }
}

function go_dir {
    [CmdletBinding()]
    param([Parameter(Position = 0)] [string] $Alias)

    $aliases = @(Get-GoDirAlias)

    if (-not $Alias) {
        if (-not $aliases) { Write-Error 'go_dir: в justfile нет рецептов группы go_dir'; return }
        $aliases | ForEach-Object { '  {0,-20} {1}' -f $_.Name, $_.Description }
        return
    }

    if ($Alias -notin $aliases.Name) {
        $msg = "go_dir: «$Alias» — не псевдоним (группа go_dir)."
        if ($aliases) {
            $msg += " Доступные:`n" + (($aliases | ForEach-Object { '  {0,-20} {1}' -f $_.Name, $_.Description }) -join "`n")
        } else {
            $msg += ' В justfile нет таких рецептов.'
        }
        Write-Error $msg
        return
    }

    # stdout рецепта — путь; stderr (строка `echo ...` без @) показываем только при ошибке
    $raw  = Invoke-GoDirJust -JustArgs @('--', $Alias) 2>&1
    $code = $LASTEXITCODE
    $err  = @($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $out  = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
                     ForEach-Object { "$_".Trim() } | Where-Object { $_ })

    if ($code -ne 0) {
        Write-Error ("go_dir: рецепт $Alias завершился с ошибкой (код $code):`n" + ($err -join "`n"))
        return
    }
    if ($out.Count -ne 1) {
        Write-Error "go_dir: рецепт $Alias должен печатать один путь, а напечатал строк: $($out.Count)"
        return
    }

    $dir = $out[0]
    # кавычки в `echo '~/x'` блокируют раскрытие тильды — делаем это сами
    if ($dir -eq '~' -or $dir.StartsWith('~/') -or $dir.StartsWith('~\')) { $dir = $HOME + $dir.Substring(1) }

    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Write-Error "go_dir: каталога нет: $dir (псевдоним $Alias)"
        return
    }
    Set-Location -LiteralPath $dir
}

Register-ArgumentCompleter -CommandName go_dir -ParameterName Alias -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-GoDirAlias | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
        $tip = if ($_.Description) { $_.Description } else { $_.Name }
        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $tip)
    }
}
