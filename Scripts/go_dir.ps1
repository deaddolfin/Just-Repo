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
    произвольный рецепт, а не перешёл в каталог. Разбор и запуск — в just_alias.ps1;
    завести псевдоним помогает just_dir.

    JUST_ALIAS_JUSTFILE — служебная переменная для отладки: если задана, вместо -g
    берётся этот justfile.
#>

if (-not (Get-Command just -CommandType Application -ErrorAction SilentlyContinue)) { return }

if (-not (Get-Command Resolve-JaAlias -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'just_alias.ps1')
}

function go_dir {
    [CmdletBinding()]
    param([Parameter(Position = 0)] [string] $Alias)

    if (-not $Alias) { Show-JaList -Caller 'go_dir' -Group 'go_dir'; return }

    $dir = Resolve-JaAlias -Caller 'go_dir' -Group 'go_dir' -Alias $Alias
    if (-not $dir) { return }

    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Write-Error "go_dir: каталога нет: $dir (псевдоним $Alias)"
        return
    }
    Set-Location -LiteralPath $dir
}

Register-ArgumentCompleter -CommandName go_dir -ParameterName Alias -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-JaCompletion -Group 'go_dir' -WordToComplete $wordToComplete
}
