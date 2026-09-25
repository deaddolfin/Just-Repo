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

# где что лежит
where:
    @echo "репозиторий:      {{repo}}"
    @echo "группа:           {{group}}"
    @echo "каталог конфигов: {{config_dir}}"

# подтянуть свежие алиасы из репозитория
sync:
    git -C "{{repo}}" pull --ff-only

# открыть локальный файл алиасов этой машины
[unix]
elocal:
    "${EDITOR:-vi}" "{{config_dir}}/local.just"

[windows]
elocal:
    & (if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }) "{{config_dir}}/local.just"

# открыть файл группы в репозитории
[unix]
egroup:
    "${EDITOR:-vi}" "{{repo}}/Config/{{group}}/group.just"

[windows]
egroup:
    & (if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }) "{{repo}}/Config/{{group}}/group.just"

# открыть общий файл алиасов в репозитории
[unix]
eglobal:
    "${EDITOR:-vi}" "{{repo}}/Config/global.just"

[windows]
eglobal:
    & (if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }) "{{repo}}/Config/global.just"

alias h := help
alias s := sync
alias el := elocal
alias eg := egroup
