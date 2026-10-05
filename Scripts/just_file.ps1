#requires -Version 7.0
<#
    just_file.ps1 — сохранить файл как псевдоним для j_edit и j_tail.
    Парный к just_dir: тот сохраняет каталог, этот — файл.

    Подключение (это делает init.ps1 -WithShell):
        . C:\путь\к\репозиторию\Scripts\just_file.ps1

    Использование:
        just_file C:\logs\app.log                      псевдоним для файла
        just_file .\app.conf -Name app -Desc 'Конфиг'  имя и описание без вопросов
        just_file C:\logs\app.log -Print               только напечатать блок, ничего не писать
        just_file C:\logs\app.log -Force               не переспрашивать при конфликте имён

    Путь к файлу обязателен (у файла нет «текущего»), файл должен существовать.

    Пишет ровно в один файл — local.just в каталоге конфигов (как just_new): путь
    принадлежит этой машине. Файлы репозитория (Config\global.just, Config\<группа>\
    group.just) правятся редактором из каталога проекта; для переноса туда есть -Print.

    Результат — рецепт группы j_file, который печатает путь:

        # Лог приложения
        [group('j_file')]
        file_app_log:
            @echo 'C:\logs\app.log'

    Открыть: j_edit file_app_log. Смотреть: j_tail file_app_log.
    Вся логика — в just_alias.ps1 (общая с just_dir).
#>

if (-not (Get-Command just -CommandType Application -ErrorAction SilentlyContinue)) { return }

if (-not (Get-Command Add-JustAlias -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'just_alias.ps1')
}

function just_file {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string] $Path,
        [string] $Name,
        [string] $Desc,
        [switch] $Print,
        [switch] $Force
    )
    Add-JustAlias -Caller 'just_file' -Group 'j_file' -Kind 'file' @PSBoundParameters
}
