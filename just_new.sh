#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# just_new.sh — сохранить только что выполненную команду как рецепт just.
# Аналог функции prev из pet, но для just.
#
# Подключение (это делает init.sh --shell):
#     source /путь/к/репозиторию/just_new.sh
#
# Использование:
#     just_new                      взять последнюю команду из истории
#     just_new -- ls -la /srv       взять команду из аргументов
#     just_new -p                   только напечатать блок, ничего не писать
#     just_new -n logs -d "логи"    имя и описание без вопросов
#     just_new -f                   не переспрашивать при конфликте имён
#
# Пишет ровно в один файл — local.just в каталоге конфигов. Файлы репозитория
# (Config/global.just, Config/<группа>/group.just) правятся редактором
# из каталога проекта, just_new их не трогает: для переноса туда есть режим -p.
# ---------------------------------------------------------------------------

_jn_config_dir() {
    if [ -n "${JUST_CONFIG_DIR:-}" ]; then
        printf '%s\n' "$JUST_CONFIG_DIR"
        return 0
    fi
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/just"
}

_jn_state_value() {
    local key="$1" state
    state="$(_jn_config_dir)/state.env"
    [ -f "$state" ] || return 0
    sed -n "s/^${key}=//p" "$state" | head -n 1
}

# имена рецептов в just-файле (без alias, set, import и переменных)
_jn_recipe_names() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -E -n 's/^([a-zA-Z_][a-zA-Z0-9_-]*)([[:space:]]+[^:=]*)?:([^=].*)?$/\1/p' "$f" \
        | grep -Ev '^(set|alias|import|export|mod)$' || true
}

_jn_alias_names() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -E -n 's/^alias[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*:=.*/\1/p' "$f" || true
}

_jn_has_recipe() {
    _jn_recipe_names "$1" | grep -qx -- "$2"
}

_jn_has_alias() {
    _jn_alias_names "$1" | grep -qx -- "$2"
}

# собрать блок рецепта: комментарий-описание + тело
_jn_block() {
    local name="$1" desc="$2" cmd="$3"
    # {{ }} в just — подстановка; литеральные скобки экранируются удвоением
    cmd="$(printf '%s' "$cmd" | sed 's/{{/{{{{/g')"
    printf '\n'
    if [ -n "$desc" ]; then
        printf '# %s\n' "$desc"
    fi
    printf '%s:\n' "$name"
    case "$cmd" in
        *$'\n'*)
            # многострочная команда — shebang-рецепт, иначе каждая строка уйдёт
            # в свой шелл и cd/переменные не переживут перевод строки
            printf '    #!/usr/bin/env bash\n'
            printf '    set -euo pipefail\n'
            printf '%s\n' "$cmd" | sed 's/^/    /'
            ;;
        *)
            printf '    %s\n' "$cmd"
            ;;
    esac
}

# удалить прежнее определение рецепта вместе с описанием и телом
_jn_remove_recipe() {
    local file="$1" name="$2"
    local -a lines=()
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        lines+=("$line")
    done < "$file"

    local n=${#lines[@]} start=-1 i
    for (( i = 0; i < n; i++ )); do
        if printf '%s' "${lines[$i]}" | grep -qE "^${name}([[:space:]]+[^:=]*)?:([^=].*)?$"; then
            start=$i
            break
        fi
    done
    [ "$start" -ge 0 ] || return 1

    local b=$start e=$start prev nxt
    while [ "$b" -gt 0 ]; do
        prev="${lines[$((b - 1))]}"
        case "$prev" in
            '#'*|'['*) b=$((b - 1)) ;;
            *) break ;;
        esac
    done
    while [ $((e + 1)) -lt "$n" ]; do
        nxt="${lines[$((e + 1))]}"
        case "$nxt" in
            ''|' '*|$'\t'*) e=$((e + 1)) ;;
            *) break ;;
        esac
    done

    local tmp
    tmp="$(mktemp)"
    for (( i = 0; i < n; i++ )); do
        if [ "$i" -ge "$b" ] && [ "$i" -le "$e" ]; then
            continue
        fi
        printf '%s\n' "${lines[$i]}"
    done > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

_jn_usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

just_new() {
    local cmd="" name="" desc="" print=0 force=0 answer
    local config_dir local_file justfile repo group

    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--print) print=1 ;;
            -f|--force) force=1 ;;
            -n|--name)  shift; name="${1:-}" ;;
            -d|--desc)  shift; desc="${1:-}" ;;
            -h|--help)  _jn_usage; return 0 ;;
            --)         shift; cmd="$*"; break ;;
            -*)         printf 'just_new: неизвестный флаг: %s\n' "$1" >&2; return 1 ;;
            *)          cmd="$*"; break ;;
        esac
        shift
    done

    config_dir="$(_jn_config_dir)"
    local_file="$config_dir/local.just"
    justfile="$config_dir/justfile"
    repo="$(_jn_state_value JUST_REPO)"
    group="$(_jn_state_value JUST_GROUP)"

    if [ ! -f "$justfile" ]; then
        printf 'just_new: нет %s — сначала выполните init.sh <группа>\n' "$justfile" >&2
        return 1
    fi

    # --- команда ---
    if [ -z "$cmd" ]; then
        if [ -z "${BASH_VERSION:-}" ] || ! fc -l -1 >/dev/null 2>&1; then
            printf 'just_new: история недоступна. Передайте команду явно:\n' >&2
            printf '    just_new -- <команда>\n' >&2
            printf 'или подключите функцию: source %s/just_new.sh\n' "${repo:-<репозиторий>}" >&2
            return 1
        fi
        # bash кладёт команду в историю ДО её выполнения, поэтому первой строкой
        # идёт сам вызов just_new — берём первую строку, которая им не является
        cmd="$(fc -lrn 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -vE '^(just_new|jnew)([[:space:]]|$)' | head -n 1)"
    fi
    if [ -z "$cmd" ]; then
        printf 'just_new: команды нет — история пуста или недоступна.\n' >&2
        printf '  Передайте команду явно:  just_new -- <команда>\n' >&2
        printf '  Из истории команда берётся только в интерактивном bash,\n' >&2
        printf '  где функция подключена:  source %s/just_new.sh\n' "${repo:-<репозиторий>}" >&2
        return 1
    fi
    printf 'команда: %s\n' "$cmd"

    # --- имя рецепта ---
    if [ -z "$name" ]; then
        if [ -t 0 ]; then
            read -r -p 'имя рецепта: ' name
        else
            printf 'just_new: нет имени рецепта (ключ -n) и нет терминала для вопроса\n' >&2
            return 1
        fi
    fi
    if ! printf '%s' "$name" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_-]*$'; then
        printf 'just_new: недопустимое имя рецепта: «%s»\n' "$name" >&2
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
        printf 'just_new: «%s» — это alias в %s.just.\n' "$name" "$alias_hit" >&2
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
        printf '  первым, а just берёт первое определение. Общая команда на этой машине перестанет\n'
        printf '  работать так же, как на других.\n'
        printf '  Общую команду правят в %s/Config — отсюда туда just_new не пишет.\n\n' "${repo:-<репозиторий>}"
        if [ "$print" -eq 0 ] && [ "$force" -eq 0 ]; then
            if [ -t 0 ]; then
                read -r -p 'переопределить локально? [y/N/имя другого рецепта]: ' answer
                case "$answer" in
                    y|Y|yes|да) ;;
                    ''|n|N|no|нет)
                        printf 'отменено\n'
                        return 1
                        ;;
                    *)
                        name="$answer"
                        if ! printf '%s' "$name" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_-]*$'; then
                            printf 'just_new: недопустимое имя рецепта: «%s»\n' "$name" >&2
                            return 1
                        fi
                        in_local=0
                        _jn_has_recipe "$local_file" "$name" && in_local=1
                        ;;
                esac
            else
                printf 'just_new: конфликт имени, нужен ключ -f для подтверждения\n' >&2
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
                printf 'just_new: «%s» уже есть в local.just, нужен ключ -f\n' "$name" >&2
                return 1
            fi
        fi
    fi

    # --- вывод или запись ---
    if [ "$print" -eq 1 ]; then
        printf '\n--- блок для вставки ---\n'
        _jn_block "$name" "$desc" "$cmd"
        printf -- '------------------------\n'
        return 0
    fi

    [ -f "$local_file" ] || printf '# local.just — алиасы только этой машины.\n' > "$local_file"
    cp "$local_file" "$local_file.bak"
    if [ "$in_local" -eq 1 ]; then
        _jn_remove_recipe "$local_file" "$name" || true
    fi
    _jn_block "$name" "$desc" "$cmd" >> "$local_file"

    if just --justfile "$justfile" --working-directory . --summary >/dev/null 2>&1; then
        rm -f "$local_file.bak"
        printf 'записано в %s\n' "$local_file"
        if [ "$in_group" -eq 1 ] || [ "$in_global" -eq 1 ]; then
            local loser="group.just"
            [ "$in_global" -eq 1 ] && loser="global.just"
            printf '%s: local.just перекрывает %s\n' "$name" "$loser"
        fi
        printf 'проверить: just --justfile "%s" --list\n' "$justfile"
    else
        cat "$local_file.bak" > "$local_file"
        rm -f "$local_file.bak"
        printf 'just_new: just не разобрал результат, изменения отменены:\n' >&2
        just --justfile "$justfile" --working-directory . --summary >&2 || true
        return 1
    fi
}

# Запущен как скрипт (а не подключён через source) — истории родительского
# шелла не видно, поэтому работаем только с командой из аргументов.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    just_new "$@"
fi
