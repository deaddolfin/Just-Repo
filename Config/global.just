# ---------------------------------------------------------------------------
# global.just — переменные и алиасы, общие для всех машин.
#
# Файл репозитория. На машине подключён симлинком из каталога конфигов just,
# правится только здесь, в каталоге проекта, и разъезжается через `git pull`.
#
# Переменные repo / group / config_dir определены в основном justfile,
# который создаёт init.
# ---------------------------------------------------------------------------

# показать все доступные команды
help:
    @just --list

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
