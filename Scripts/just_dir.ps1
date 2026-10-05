#requires -Version 7.0
<#
    just_dir.ps1 — сохранить каталог как псевдоним для go_dir.
    Парный к just_new: тот сохраняет команду, этот — каталог.

    Подключение (это делает init.ps1 -WithShell):
        . C:\путь\к\репозиторию\Scripts\just_dir.ps1

    Использование:
        just_dir                              псевдоним для текущего каталога
        just_dir C:\srv\app                   псевдоним для указанного каталога
        just_dir -Name app -Desc 'Проект'     имя и описание без вопросов
        just_dir -Print                       только напечатать блок, ничего не писать
        just_dir -Force                       не переспрашивать при конфликте имён

    Пишет ровно в один файл — local.just в каталоге конфигов (как just_new): путь
    принадлежит этой машине. Файлы репозитория (Config\global.just, Config\<группа>\
    group.just) правятся редактором из каталога проекта; для переноса туда есть -Print.

    Результат — рецепт группы go_dir, который печатает путь:

        # Проект
        [group('go_dir')]
        dir_app:
            @echo 'C:\srv\app'

    Перейти по нему: go_dir dir_app. Вся логика — в just_alias.ps1 (общая с just_file).
#>

if (-not (Get-Command just -CommandType Application -ErrorAction SilentlyContinue)) { return }

if (-not (Get-Command Add-JustAlias -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'just_alias.ps1')
}

function just_dir {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string] $Path,
        [string] $Name,
        [string] $Desc,
        [switch] $Print,
        [switch] $Force
    )
    Add-JustAlias -Caller 'just_dir' -Group 'go_dir' -Kind 'dir' @PSBoundParameters
}
