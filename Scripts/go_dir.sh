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
# произвольный рецепт, а не перешёл в каталог.
#
# GO_DIR_JUSTFILE — служебная переменная для отладки: если задана, вместо -g
# берётся этот justfile.
# ---------------------------------------------------------------------------

command -v just >/dev/null 2>&1 || return 0

_GO_DIR_GROUP=go_dir

# just с глобальным justfile либо с файлом из GO_DIR_JUSTFILE
_go_dir_just() {
    if [ -n "${GO_DIR_JUSTFILE:-}" ]; then
        command just --justfile "$GO_DIR_JUSTFILE" --working-directory . "$@"
    else
        command just -g "$@"
    fi
}

# строки «имя<TAB>описание» для рецептов группы go_dir
_go_dir_list() {
    _go_dir_just --list --unsorted --color never --list-heading '' --list-prefix '' 2>/dev/null \
        | tr -d '\r' \
        | awk -v g="$_GO_DIR_GROUP" '
            /^\[.*\]$/ { cur = substr($0, 2, length($0) - 2); next }
            /^[[:space:]]*$/ { next }
            # NF == 1 — рецепт без параметров; $2 == "#" — то же, но с описанием
            cur == g && (NF == 1 || $2 == "#") {
                desc = ""
                i = index($0, "#")
                if (i > 0) desc = substr($0, i + 2)
                sub(/ ?\[alias: [^]]*\]$/, "", desc)
                if (desc ~ /^\[alias: /) desc = ""
                print $1 "\t" desc
            }'
}

go_dir() {
    local name="${1:-}" names dir out errf rc nlines

    names="$(_go_dir_list)"

    if [ -z "$name" ]; then
        if [ -z "$names" ]; then
            printf 'go_dir: в justfile нет рецептов группы %s\n' "$_GO_DIR_GROUP" >&2
            return 1
        fi
        printf '%s\n' "$names" | awk -F'\t' '{ printf "  %-20s %s\n", $1, $2 }'
        return 0
    fi

    if [ $# -gt 1 ]; then
        printf 'go_dir: ожидается один аргумент — псевдоним\n' >&2
        return 1
    fi

    if ! printf '%s\n' "$names" | cut -f1 | grep -Fxq -- "$name"; then
        printf 'go_dir: «%s» — не псевдоним (группа %s).' "$name" "$_GO_DIR_GROUP" >&2
        if [ -n "$names" ]; then
            printf ' Доступные:\n' >&2
            printf '%s\n' "$names" | awk -F'\t' '{ printf "  %-20s %s\n", $1, $2 }' >&2
        else
            printf ' В justfile нет таких рецептов.\n' >&2
        fi
        return 1
    fi

    # stdout рецепта — путь; stderr (строка `echo ...` без @) показываем только при ошибке
    errf="$(mktemp)"
    out="$(_go_dir_just -- "$name" 2>"$errf")"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'go_dir: рецепт %s завершился с ошибкой (код %s):\n' "$name" "$rc" >&2
        cat "$errf" >&2
        rm -f "$errf"
        return "$rc"
    fi
    rm -f "$errf"

    out="$(printf '%s\n' "$out" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')"
    nlines="$(printf '%s\n' "$out" | grep -c .)"
    if [ "$nlines" -ne 1 ]; then
        printf 'go_dir: рецепт %s должен печатать один путь, а напечатал строк: %s\n' "$name" "$nlines" >&2
        return 1
    fi
    dir="$out"

    # кавычки в `echo '~/x'` блокируют раскрытие тильды — делаем это сами
    case "$dir" in
        "~")   dir="$HOME" ;;
        "~/"*) dir="$HOME/${dir#\~/}" ;;
    esac

    if [ ! -d "$dir" ]; then
        printf 'go_dir: каталога нет: %s (псевдоним %s)\n' "$dir" "$name" >&2
        return 1
    fi
    cd -- "$dir"
}

_go_dir_complete() {
    [ "$COMP_CWORD" -eq 1 ] || return 0
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "$(_go_dir_list | cut -f1)" -- "$cur") )
}

complete -F _go_dir_complete go_dir
