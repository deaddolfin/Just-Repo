#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# j_file.sh — работа с файлами по псевдониму: j_edit и j_tail.
# Парный к go_dir: тот переходит в каталог, эти открывают и читают файл.
#
# Подключается блоком из init.sh (--shell):
#     source /путь/к/репозиторию/Scripts/j_file.sh
#
# Использование:
#     j_edit                       список псевдонимов с описаниями
#     j_edit <псевдоним>           открыть файл в редакторе
#     j_tail <псевдоним>           напечатать файл целиком (cat)
#     j_tail <псевдоним> -n 50     последние 50 строк
#     j_tail <псевдоним> -f        последние 10 строк и следить за дополнениями
#     j_tail <псевдоним> -n 5 -f   последние 5 строк и следить
#
# Поддерживаются опции tail -n (--lines) и -f (--follow); число — только цифры.
# Остальные опции tail отклоняются.
#
# Редактор: $VISUAL, затем $EDITOR, иначе первый найденный из sensible-editor,
# editor, nano, vi. Значение с аргументами (EDITOR="code -w") допускается.
#
# Псевдоним — рецепт just из группы j_file (global.just, group.just или local.just),
# который печатает ОДИН путь к файлу:
#
#     # Конфиг nginx
#     [group('j_file')]
#     file_nginx:
#         @echo '/etc/nginx/nginx.conf'
#
# Запускается только рецепт из группы j_file. Разбор и запуск — в just_alias.sh;
# завести псевдоним помогает just_file.
# ---------------------------------------------------------------------------

command -v just >/dev/null 2>&1 || return 0

if ! declare -F _ja_resolve >/dev/null 2>&1; then
    # shellcheck source=just_alias.sh
    source "$(dirname "${BASH_SOURCE[0]}")/just_alias.sh"
fi

# j_edit <псевдоним>
j_edit() {
    local name="${1:-}" file ed c
    local -a cmd

    if [ -z "$name" ]; then
        _ja_show_list j_edit j_file
        return
    fi
    if [ $# -gt 1 ]; then
        printf 'j_edit: ожидается один аргумент — псевдоним\n' >&2
        return 1
    fi

    file="$(_ja_resolve j_edit j_file "$name")" || return $?
    if [ ! -f "$file" ]; then
        printf 'j_edit: файла нет: %s (псевдоним %s)\n' "$file" "$name" >&2
        return 1
    fi

    ed="${VISUAL:-${EDITOR:-}}"
    if [ -z "$ed" ]; then
        for c in sensible-editor editor nano vi; do
            if command -v "$c" >/dev/null 2>&1; then ed="$c"; break; fi
        done
    fi
    if [ -z "$ed" ]; then
        printf 'j_edit: редактор не найден — задайте $EDITOR\n' >&2
        return 1
    fi

    # значение вроде «code -w» — это команда с аргументами
    read -r -a cmd <<< "$ed"
    "${cmd[@]}" "$file"
}

# j_tail <псевдоним> [-n N] [-f]
j_tail() {
    local name="${1:-}" file v
    local -a opts=()

    if [ -z "$name" ]; then
        _ja_show_list j_tail j_file
        return
    fi
    shift

    # опции проверяются до запуска рецепта: tail получает только известное
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--lines)
                if [ $# -lt 2 ]; then
                    printf 'j_tail: у %s нужно число строк\n' "$1" >&2
                    return 1
                fi
                v="$2"; shift
                ;;
            -n[0-9]*)    v="${1#-n}" ;;
            --lines=*)   v="${1#--lines=}" ;;
            -f|--follow) opts+=(-f); shift; continue ;;
            *)
                printf 'j_tail: неподдерживаемая опция: %s\n' "$1" >&2
                printf '  Поддерживаются: -n N (--lines N), -f (--follow)\n' >&2
                return 1
                ;;
        esac
        case "$v" in
            ''|*[!0-9]*)
                printf 'j_tail: число строк должно состоять из цифр: «%s»\n' "$v" >&2
                return 1
                ;;
        esac
        opts+=(-n "$v")
        shift
    done

    file="$(_ja_resolve j_tail j_file "$name")" || return $?
    if [ ! -f "$file" ]; then
        printf 'j_tail: файла нет: %s (псевдоним %s)\n' "$file" "$name" >&2
        return 1
    fi

    if [ ${#opts[@]} -eq 0 ]; then
        cat -- "$file"
    else
        tail "${opts[@]}" -- "$file"
    fi
}

_j_edit_complete() { _ja_complete_names j_file; }

_j_tail_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        _ja_complete_names j_file
    else
        COMPREPLY=( $(compgen -W "-n -f --lines --follow" -- "$cur") )
    fi
}

complete -F _j_edit_complete j_edit
complete -F _j_tail_complete j_tail
