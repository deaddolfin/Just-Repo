#requires -Version 7.0
<#
    just_complete.ps1 — автодополнение для `just` и для функции `j`.

    Подключается блоком из init.ps1 (-WithShell):
        $env:JUST_J_JUSTFILE = '<каталог конфигов>\justfile'
        . C:\путь\к\репозиторию\just_complete.ps1

    Всё, что умеет дополнять just, — флаги, рецепты, переменные — делает сам
    бинарник (`just --completions powershell`, динамическое дополнение с just 1.48):
    при нажатии Tab он разбирает набранную строку и отвечает списком. Здесь только
    подключение этого механизма и его переадресация для j.

    j — это `just --justfile <cfg>\justfile --working-directory .`, но в набранной
    строке этих флагов нет, поэтому рецепты искались бы в justfile текущего каталога.
    Обработчик перед вызовом подставляет --justfile в набранную строку.
#>

if (-not (Get-Command just -CommandType Application -ErrorAction SilentlyContinue)) { return }

# регистрирует обработчик для just
just --completions powershell | Out-String | Invoke-Expression

Register-ArgumentCompleter -Native -CommandName j -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $exe = (Get-Command just -CommandType Application | Select-Object -First 1).Source
    $justfile = if ($env:JUST_J_JUSTFILE) { $env:JUST_J_JUSTFILE } else { Join-Path $env:APPDATA 'just\justfile' }

    # строка до курсора без имени команды: `j sync --fo` -> `sync --fo`
    $text = $commandAst.Extent.Text
    $cut  = [math]::Min($cursorPosition - $commandAst.Extent.StartOffset, $text.Length)
    $text = $text.Substring(0, $cut)
    if ($wordToComplete -eq '') { $text += " ''" }
    $rest = $text -replace '^\s*\S+\s*', ''

    $prev = $env:JUST_COMPLETE
    $env:JUST_COMPLETE = 'powershell'
    try {
        $results = Invoke-Expression "& `"$exe`" -- just --justfile `"$justfile`" $rest"
    } finally {
        if ($null -eq $prev) { Remove-Item Env:\JUST_COMPLETE } else { $env:JUST_COMPLETE = $prev }
    }

    $results | ForEach-Object {
        $split = $_.Split("`t")
        $name  = $split[0]
        $help  = if ($split.Length -eq 2) { $split[1] } else { $split[0] }
        [System.Management.Automation.CompletionResult]::new($name, $name, 'ParameterValue', $help)
    }
}
