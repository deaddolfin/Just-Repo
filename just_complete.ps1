#requires -Version 7.0
<#
    just_complete.ps1 — автодополнение для `just` и для функций `j` и `jg`.

    Подключается блоком из init.ps1 (-WithShell):
        function j  { just @args }
        function jg { just -g @args }
        . C:\путь\к\репозиторию\just_complete.ps1

    Всё, что умеет дополнять just, — флаги, рецепты, переменные — делает сам
    бинарник (`just --completions powershell`, динамическое дополнение с just 1.48):
    при нажатии Tab он разбирает набранную строку и отвечает списком. Здесь только
    подключение этого механизма и его переадресация для функций.

    Бинарник должен видеть в строке настоящую команду, а не имя функции: для jg в
    набранной строке нет ключа -g, и рецепты искались бы в justfile текущего каталога.
    Обработчик перед вызовом подставляет его: j -> just, jg -> just -g.
#>

if (-not (Get-Command just -CommandType Application -ErrorAction SilentlyContinue)) { return }

# регистрирует обработчик для just
just --completions powershell | Out-String | Invoke-Expression

Register-ArgumentCompleter -Native -CommandName j, jg -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $exe   = (Get-Command just -CommandType Application | Select-Object -First 1).Source
    $extra = if ($commandAst.CommandElements[0].Value -eq 'jg') { '-g ' } else { '' }

    # строка до курсора без имени команды: `jg sync --fo` -> `sync --fo`
    $text = $commandAst.Extent.Text
    $cut  = [math]::Min($cursorPosition - $commandAst.Extent.StartOffset, $text.Length)
    $text = $text.Substring(0, $cut)
    if ($wordToComplete -eq '') { $text += " ''" }
    $rest = $text -replace '^\s*\S+\s*', ''

    $prev = $env:JUST_COMPLETE
    $env:JUST_COMPLETE = 'powershell'
    try {
        $results = Invoke-Expression "& `"$exe`" -- just $extra$rest"
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
