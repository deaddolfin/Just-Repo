#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# go_dir.sh — перейти в каталог по псевдониму.
#
# Подключается блоком из init.sh (--shell):
#     source /путь/к/репозиторию/Scripts/go_dir.sh
#
# Использование:
#     go_dir                 список псевдонимов с описаниями
#     go_dir <псевдоним>     cd в каталог, на который указывает псевдоним
#
# Это функция, а не скрипт: cd из дочернего процесса не меняет каталог оболочки.
#
# Псевдоним — рецепт just из группы go_dir (global.just, group.just или local.just),
# который печатает ОДИН путь:
#
#     # Папка проекта
#     [group('go_dir')]
#     dir_project:
#         @echo '/home/workers/ParserService'
#
# Рецепт без параметров и не [private] (приватные скрыты из `just --list`, по нему
# и строится список). Источник — всегда глобальный justfile (`just -g`).
#
# Запускается только рецепт из группы go_dir: иначе `go_dir restart` выполнил бы
# произвольный рецепт, а не перешёл в каталог. Разбор и запуск — в just_alias.sh;
# завести псевдоним помогает just_dir.
#
# JUST_ALIAS_JUSTFILE — служебная переменная для отладки: если задана, вместо -g
# берётся этот justfile.
# ---------------------------------------------------------------------------

command -v just >/dev/null 2>&1 || return 0

if ! declare -F _ja_resolve >/dev/null 2>&1; then
    # shellcheck source=just_alias.sh
    source "$(dirname "${BASH_SOURCE[0]}")/just_alias.sh"
fi

go_dir() {
    local name="${1:-}" dir

    if [ -z "$name" ]; then
        _ja_show_list go_dir go_dir
        return
    fi
    if [ $# -gt 1 ]; then
        printf 'go_dir: ожидается один аргумент — псевдоним\n' >&2
        return 1
    fi

    dir="$(_ja_resolve go_dir go_dir "$name")" || return $?
    if [ ! -d "$dir" ]; then
        printf 'go_dir: каталога нет: %s (псевдоним %s)\n' "$dir" "$name" >&2
        return 1
    fi
    cd -- "$dir"
}

_go_dir_complete() { _ja_complete_names go_dir; }

complete -F _go_dir_complete go_dir
