#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# just_dir.sh — сохранить каталог как псевдоним для go_dir.
# Парный к just_new: тот сохраняет команду, этот — каталог.
#
# Подключение (это делает init.sh --shell):
#     source /путь/к/репозиторию/Scripts/just_dir.sh
#
# Использование:
#     just_dir                      псевдоним для текущего каталога ($PWD)
#     just_dir /srv/app             псевдоним для указанного каталога
#     just_dir -n app -d "Проект"   имя и описание без вопросов
#     just_dir -p                   только напечатать блок, ничего не писать
#     just_dir -f                   не переспрашивать при конфликте имён
#
# Пишет ровно в один файл — local.just в каталоге конфигов (как just_new): путь
# принадлежит этой машине. Файлы репозитория (Config/global.just, Config/<группа>/
# group.just) правятся редактором из каталога проекта; для переноса туда есть -p.
#
# Результат — рецепт группы go_dir, который печатает путь:
#
#     # Проект
#     [group('go_dir')]
#     dir_app:
#         @echo '/srv/app'
#
# Перейти по нему: go_dir dir_app.
# ---------------------------------------------------------------------------

# хелперы just_new: каталог конфигов, разбор имён рецептов, удаление рецепта
if ! declare -F _jn_config_dir >/dev/null 2>&1; then
    # shellcheck source=just_new.sh
    source "$(dirname "${BASH_SOURCE[0]}")/just_new.sh"
fi

# имя по умолчанию: dir_<последний компонент пути>, только допустимые символы
_jd_default_name() {
    local leaf slug
    leaf="$(basename -- "$1")"
    slug="$(printf '%s' "$leaf" | sed 's/[^a-zA-Z0-9_-]\{1,\}/_/g; s/^_*//; s/_*$//')"
    [ -n "$slug" ] || slug="root"
    printf 'dir_%s\n' "$slug"
}

# блок рецепта: описание, атрибут группы, имя, путь
_jd_block() {
    local name="$1" desc="$2" dir="$3"
    # {{ }} в just — подстановка; литеральные скобки экранируются удвоением
    dir="$(printf '%s' "$dir" | sed 's/{{/{{{{/g')"
    printf '\n'
    if [ -n "$desc" ]; then
        printf '# %s\n' "$desc"
    fi
    printf "[group('go_dir')]\n"
    printf '%s:\n' "$name"
    printf "    @echo '%s'\n" "$dir"
}

_jd_usage() {
    sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

just_dir() {
    local arg="" dir="" name="" desc="" print=0 force=0 answer default
    local config_dir local_file justfile repo have_arg=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--print) print=1 ;;
            -f|--force) force=1 ;;
            -n|--name)  shift; name="${1:-}" ;;
            -d|--desc)  shift; desc="${1:-}" ;;
            -h|--help)  _jd_usage; return 0 ;;
            --)         shift; if [ $# -gt 0 ]; then arg="$1"; have_arg=1; fi; break ;;
            -*)         printf 'just_dir: неизвестный флаг: %s\n' "$1" >&2; return 1 ;;
            *)
                if [ "$have_arg" -eq 1 ]; then
                    printf 'just_dir: ожидается один путь, получено несколько\n' >&2
                    return 1
                fi
                arg="$1"; have_arg=1
                ;;
        esac
        shift
    done

    config_dir="$(_jn_config_dir)"
    local_file="$config_dir/local.just"
    justfile="$config_dir/justfile"
    repo="$(_jn_state_value JUST_REPO)"

    if [ ! -f "$justfile" ]; then
        printf 'just_dir: нет %s — сначала выполните init.sh <группа>\n' "$justfile" >&2
        return 1
    fi

    # --- путь: аргумент или текущий каталог ---
    if [ "$have_arg" -eq 0 ] || [ -z "$arg" ]; then
        dir="$PWD"
    else
        # кавычки блокируют раскрытие тильды — делаем это сами
        case "$arg" in
            "~")   arg="$HOME" ;;
            "~/"*) arg="$HOME/${arg#\~/}" ;;
        esac
        if ! dir="$(cd -- "$arg" 2>/dev/null && pwd)"; then
            printf 'just_dir: каталога нет: %s\n' "$arg" >&2
            return 1
        fi
    fi
    case "$dir" in
        *"'"*)
            printf 'just_dir: в пути есть одинарная кавычка, такой путь не поддерживается: %s\n' "$dir" >&2
            return 1
            ;;
        *$'\n'*)
            printf 'just_dir: в пути есть перевод строки, такой путь не поддерживается\n' >&2
            return 1
            ;;
    esac
    printf 'каталог: %s\n' "$dir"

    # --- имя псевдонима ---
    default="$(_jd_default_name "$dir")"
    if [ -z "$name" ]; then
        if [ -t 0 ]; then
            read -r -p "имя псевдонима [$default]: " name
            name="${name:-$default}"
        else
            printf 'just_dir: нет имени псевдонима (ключ -n) и нет терминала для вопроса\n' >&2
            return 1
        fi
    fi
    if ! printf '%s' "$name" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_-]*$'; then
        printf 'just_dir: недопустимое имя псевдонима: «%s»\n' "$name" >&2
        return 1
    fi
    if [ -z "$desc" ] && [ -t 0 ]; then
        read -r -p 'описание (Enter — пропустить): ' desc
    fi

    # --- проверка имени по всем трём файлам ---
    local in_local=0 in_group=0 in_global=0 alias_hit=""
    _jn_has_recipe "$config_dir/local.just"  "$name" && in_local=1
    _jn_has_recipe "$config_dir/group.just"  "$name" && in_group=1
    _jn_has_recipe "$config_dir/global.just" "$name" && in_global=1
    local f label
    for label in global group local; do
        f="$config_dir/$label.just"
        if _jn_has_alias "$f" "$name"; then
            alias_hit="$label"
            break
        fi
    done

    if [ -n "$alias_hit" ]; then
        printf 'just_dir: «%s» — это alias в %s.just.\n' "$name" "$alias_hit" >&2
        printf '  Дубликаты алиасов just не прощает: конфиг перестанет разбираться целиком.\n' >&2
        printf '  Возьмите другое имя.\n' >&2
        return 1
    fi

    if [ "$in_group" -eq 1 ] || [ "$in_global" -eq 1 ]; then
        local src="group.just"
        [ "$in_global" -eq 1 ] && src="global.just"
        [ "$in_group" -eq 1 ] && [ "$in_global" -eq 1 ] && src="group.just и global.just"
        printf '\n  ВНИМАНИЕ: рецепт «%s» приезжает из репозитория (%s).\n' "$name" "$src"
        printf '  Запись в local.just создаст локальное переопределение: local импортируется\n'
        printf '  первым, а just берёт первое определение. На этой машине псевдоним поведёт\n'
        printf '  в другой каталог, чем на остальных.\n'
        printf '  Общий псевдоним правят в %s/Config — отсюда туда just_dir не пишет.\n\n' "${repo:-<репозиторий>}"
        if [ "$print" -eq 0 ] && [ "$force" -eq 0 ]; then
            if [ -t 0 ]; then
                read -r -p 'переопределить локально? [y/N/имя другого псевдонима]: ' answer
                case "$answer" in
                    y|Y|yes|да) ;;
                    ''|n|N|no|нет)
                        printf 'отменено\n'
                        return 1
                        ;;
                    *)
                        name="$answer"
                        if ! printf '%s' "$name" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_-]*$'; then
                            printf 'just_dir: недопустимое имя псевдонима: «%s»\n' "$name" >&2
                            return 1
                        fi
                        in_local=0
                        _jn_has_recipe "$local_file" "$name" && in_local=1
                        ;;
                esac
            else
                printf 'just_dir: конфликт имени, нужен ключ -f для подтверждения\n' >&2
                return 1
            fi
        fi
    fi

    if [ "$in_local" -eq 1 ] && [ "$print" -eq 0 ]; then
        if [ "$force" -eq 0 ]; then
            if [ -t 0 ]; then
                read -r -p "рецепт «$name» уже есть в local.just, заменить? [y/N]: " answer
                case "$answer" in
                    y|Y|yes|да) ;;
                    *) printf 'отменено\n'; return 1 ;;
                esac
            else
                printf 'just_dir: «%s» уже есть в local.just, нужен ключ -f\n' "$name" >&2
                return 1
            fi
        fi
    fi

    # --- вывод или запись ---
    if [ "$print" -eq 1 ]; then
        printf '\n--- блок для вставки ---\n'
        _jd_block "$name" "$desc" "$dir"
        printf -- '------------------------\n'
        return 0
    fi

    [ -f "$local_file" ] || printf '# local.just — алиасы только этой машины.\n' > "$local_file"
    cp "$local_file" "$local_file.bak"
    if [ "$in_local" -eq 1 ]; then
        _jn_remove_recipe "$local_file" "$name" || true
        # после удаления в конце файла остаются пустые строки, а блок начинается
        # с пустой — без этого между рецептами получилось бы две
        awk 'NF { last = NR } { line[NR] = $0 } END { for (i = 1; i <= last; i++) print line[i] }' \
            "$local_file" > "$local_file.tmp" && cat "$local_file.tmp" > "$local_file"
        rm -f "$local_file.tmp"
    fi
    _jd_block "$name" "$desc" "$dir" >> "$local_file"

    if just --justfile "$justfile" --working-directory . --summary >/dev/null 2>&1; then
        rm -f "$local_file.bak"
        printf 'записано в %s\n' "$local_file"
        if [ "$in_group" -eq 1 ] || [ "$in_global" -eq 1 ]; then
            local loser="group.just"
            [ "$in_global" -eq 1 ] && loser="global.just"
            printf '%s: local.just перекрывает %s\n' "$name" "$loser"
        fi
        printf 'перейти: go_dir %s\n' "$name"
    else
        cat "$local_file.bak" > "$local_file"
        rm -f "$local_file.bak"
        printf 'just_dir: just не разобрал результат, изменения отменены:\n' >&2
        just --justfile "$justfile" --working-directory . --summary >&2 || true
        return 1
    fi
}

# Tab после just_dir дополняет каталоги (флаги набираются руками)
complete -o dirnames just_dir

# Запущен как скрипт (а не подключён через source) — работает так же, но каталог
# по умолчанию берётся из места запуска.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    just_dir "$@"
fi
