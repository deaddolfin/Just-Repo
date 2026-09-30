# ---------------------------------------------------------------------------
# global.just — переменные и алиасы, общие для всех машин.
#
# Файл репозитория. На машине подключён симлинком из каталога конфигов just,
# правится только здесь, в каталоге проекта, и разъезжается через `git pull`.
#
# Переменные repo / group / config_dir определены в основном justfile,
# который создаёт init.
# ---------------------------------------------------------------------------

# Путь к конфигу обязателен: голый `just --list` ищет justfile в текущем
# каталоге и выше, а глобальный без -g не берёт. config_dir приходит
# из основного justfile, поэтому рецепт не зависит от места развёртывания.
# Пустая строка ниже обязательна: описанием в --list становится последняя
# строка комментария, примыкающего к рецепту.

# показать все доступные команды
help:
    @just --list --justfile "{{config_dir}}/justfile"

# Рецептом по умолчанию становится не тот, что назван default, а помеченный
# атрибутом [default] (just 1.43+): без него just запустил бы первый рецепт
# корневого файла, а импортированные в расчёт не берёт. Определение default
# в основном justfile перекрыло бы это, поэтому init его туда не пишет.

# список команд по порядку объявления (вызов just без аргументов)
[default]
default:
    @just --list --unsorted --justfile "{{config_dir}}/justfile"

# где что лежит
where:
    @echo "репозиторий:      {{repo}}"
    @echo "группа:           {{group}}"
    @echo "каталог конфигов: {{config_dir}}"

# подтянуть свежие алиасы из репозитория
sync:
    git -C "{{repo}}" pull --ff-only

# Редактор выбирается заранее отдельным присваиванием: `& (if ...)` PowerShell
# не разбирает — if там читается как имя команды, а не как выражение.

# открыть локальный файл алиасов этой машины
[unix]
elocal:
    @"${EDITOR:-vi}" "{{config_dir}}/local.just"

[windows]
elocal:
    @$ed = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }; & $ed "{{config_dir}}/local.just"

# открыть файл группы в репозитории
[unix]
egroup:
    @"${EDITOR:-vi}" "{{repo}}/Config/{{group}}/group.just"

[windows]
egroup:
    @$ed = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }; & $ed "{{repo}}/Config/{{group}}/group.just"

# открыть общий файл алиасов в репозитории
[unix]
eglobal:
    @"${EDITOR:-vi}" "{{repo}}/Config/global.just"

[windows]
eglobal:
    @$ed = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }; & $ed "{{repo}}/Config/global.just"

alias h := help
alias s := sync
alias el := elocal
alias eg := egroup
