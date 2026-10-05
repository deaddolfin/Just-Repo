#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# just_alias.sh — общий код для команд, работающих с псевдонимами из just:
#   go_dir, j_edit, j_tail   — ЧИТАЮТ псевдоним (рецепт группы печатает путь);
#   just_dir, just_file      — ДОБАВЛЯЮТ псевдоним в local.just.
#
# Сам по себе ничего не делает: его подключают эти команды (каждая сама, через
# source рядом лежащего файла). Псевдоним — рецепт just из группы, который печатает
# ОДИН путь:
#
#     # Проект
#     [group('j_file')]
#     file_nginx:
#         @echo '/etc/nginx/nginx.conf'
#
# Рецепт без параметров и не [private] (приватные скрыты из `just --list`, по нему
# и строится список). Источник — всегда глобальный justfile (`just -g`).
#
# JUST_ALIAS_JUSTFILE — служебная переменная для отладки: если задана, вместо -g
# берётся этот justfile.
# ---------------------------------------------------------------------------

# хелперы just_new: каталог конфигов, разбор имён рецептов, удаление рецепта
if ! declare -F _jn_config_dir >/dev/null 2>&1; then
    # shellcheck source=just_new.sh
    source "$(dirname "${BASH_SOURCE[0]}")/just_new.sh"
fi

# ===========================================================================
# Чтение
# ===========================================================================

# just с глобальным justfile либо с файлом из JUST_ALIAS_JUSTFILE
_ja_just() {
    if [ -n "${JUST_ALIAS_JUSTFILE:-}" ]; then
        command just --justfile "$JUST_ALIAS_JUSTFILE" --working-directory . "$@"
    else
        command just -g "$@"
    fi
}

# строки «имя<TAB>описание» для рецептов группы $1
_ja_list() {
    _ja_just --list --unsorted --color never --list-heading '' --list-prefix '' 2>/dev/null \
        | tr -d '\r' \
        | awk -v g="$1" '
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

# «имя  описание» с отступом — для вывода списка
_ja_format() {
    awk -F'\t' '{ printf "  %-20s %s\n", $1, $2 }'
}

# команда вызвана без аргумента: список псевдонимов группы $2 (для команды $1)
_ja_show_list() {
    local caller="$1" group="$2" names
    names="$(_ja_list "$group")"
    if [ -z "$names" ]; then
        printf '%s: в justfile нет рецептов группы %s\n' "$caller" "$group" >&2
        return 1
    fi
    printf '%s\n' "$names" | _ja_format
}

# Путь, на который указывает псевдоним $3 из группы $2 (для команды $1).
# Путь — в stdout, сообщения — в stderr. Запускается только рецепт этой группы:
# иначе `go_dir restart` выполнил бы произвольный рецепт, а не перешёл в каталог.
_ja_resolve() {
    local caller="$1" group="$2" name="$3" names out errf rc nlines

    names="$(_ja_list "$group")"
    if ! printf '%s\n' "$names" | cut -f1 | grep -Fxq -- "$name"; then
        printf '%s: «%s» — не псевдоним (группа %s).' "$caller" "$name" "$group" >&2
        if [ -n "$names" ]; then
            printf ' Доступные:\n' >&2
            printf '%s\n' "$names" | _ja_format >&2
        else
            printf ' В justfile нет таких рецептов.\n' >&2
        fi
        return 1
    fi

    # stdout рецепта — путь; stderr (строка `echo ...` без @) показываем только при ошибке
    errf="$(mktemp)"
    out="$(_ja_just -- "$name" 2>"$errf")"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '%s: рецепт %s завершился с ошибкой (код %s):\n' "$caller" "$name" "$rc" >&2
        cat "$errf" >&2
        rm -f "$errf"
        return "$rc"
    fi
    rm -f "$errf"

    out="$(printf '%s\n' "$out" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')"
    nlines="$(printf '%s\n' "$out" | grep -c .)"
    if [ "$nlines" -ne 1 ]; then
        printf '%s: рецепт %s должен печатать один путь, а напечатал строк: %s\n' "$caller" "$name" "$nlines" >&2
        return 1
    fi

    # кавычки в `echo '~/x'` блокируют раскрытие тильды — делаем это сами
    case "$out" in
        "~")   out="$HOME" ;;
        "~/"*) out="$HOME/${out#\~/}" ;;
    esac
    printf '%s\n' "$out"
}

# дополнение первого аргумента именами псевдонимов группы $1 (для complete -F)
_ja_complete_names() {
    [ "$COMP_CWORD" -eq 1 ] || return 0
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "$(_ja_list "$1" | cut -f1)" -- "$cur") )
}

# ===========================================================================
# Запись (just_dir, just_file)
# ===========================================================================

# имя по умолчанию: <префикс><последний компонент пути>, только допустимые символы
_ja_default_name() {
    local prefix="$1" leaf slug
    leaf="$(basename -- "$2")"
    slug="$(printf '%s' "$leaf" | sed 's/[^a-zA-Z0-9_-]\{1,\}/_/g; s/^_*//; s/_*$//')"
    [ -n "$slug" ] || slug="root"
    printf '%s%s\n' "$prefix" "$slug"
}

# блок рецепта: описание, атрибут группы, имя, путь
_ja_block() {
    local name="$1" desc="$2" target="$3" group="$4"
    # {{ }} в just — подстановка; литеральные скобки экранируются удвоением
    target="$(printf '%s' "$target" | sed 's/{{/{{{{/g')"
    printf '\n'
    if [ -n "$desc" ]; then
        printf '# %s\n' "$desc"
    fi
    printf "[group('%s')]\n" "$group"
    printf '%s:\n' "$name"
    printf "    @echo '%s'\n" "$target"
}

# _ja_add <команда> <группа> <вид: dir|file> [аргументы команды]
#
# Разбирает аргументы, проверяет путь и имя и дописывает рецепт в local.just.
# Вид задаёт отличия: у dir путь по умолчанию — текущий каталог и проверяется каталог;
# у file путь обязателен и проверяется обычный файл.
_ja_add() {
    local caller="$1" group="$2" kind="$3"
    shift 3
    local arg="" target="" name="" desc="" print=0 force=0 answer default
    local config_dir local_file justfile repo have_arg=0 noun prefix

    case "$kind" in
        dir)  noun="каталог"; prefix="dir_" ;;
        file) noun="файл";    prefix="file_" ;;
        *)    printf '_ja_add: неизвестный вид: %s\n' "$kind" >&2; return 2 ;;
    esac

    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--print) print=1 ;;
            -f|--force) force=1 ;;
            -n|--name)  shift; name="${1:-}" ;;
            -d|--desc)  shift; desc="${1:-}" ;;
            -h|--help)
                # справка лежит в шапке файла команды: функция _<команда>_usage
                if declare -F "_${caller}_usage" >/dev/null 2>&1; then "_${caller}_usage"; fi
                return 0
                ;;
            --)         shift; if [ $# -gt 0 ]; then arg="$1"; have_arg=1; fi; break ;;
            -*)         printf '%s: неизвестный флаг: %s\n' "$caller" "$1" >&2; return 1 ;;
            *)
                if [ "$have_arg" -eq 1 ]; then
                    printf '%s: ожидается один путь, получено несколько\n' "$caller" >&2
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
        printf '%s: нет %s — сначала выполните init.sh <группа>\n' "$caller" "$justfile" >&2
        return 1
    fi

    # --- путь ---
    if [ "$kind" = file ] && { [ "$have_arg" -eq 0 ] || [ -z "$arg" ]; }; then
        printf '%s: укажите файл: %s <файл>\n' "$caller" "$caller" >&2
        return 1
    fi
    if [ "$have_arg" -eq 0 ] || [ -z "$arg" ]; then
        target="$PWD"
    else
        # кавычки блокируют раскрытие тильды — делаем это сами
        case "$arg" in
            "~")   arg="$HOME" ;;
            "~/"*) arg="$HOME/${arg#\~/}" ;;
        esac
        if [ "$kind" = dir ]; then
            if ! target="$(cd -- "$arg" 2>/dev/null && pwd)"; then
                printf '%s: каталога нет: %s\n' "$caller" "$arg" >&2
                return 1
            fi
        else
            if [ -d "$arg" ]; then
                printf '%s: это каталог, а не файл: %s (для каталогов есть just_dir)\n' "$caller" "$arg" >&2
                return 1
            fi
            if [ ! -f "$arg" ]; then
                printf '%s: файла нет: %s\n' "$caller" "$arg" >&2
                return 1
            fi
            local d
            d="$(cd -- "$(dirname -- "$arg")" && pwd)"
            [ "$d" = "/" ] && d=""
            target="$d/$(basename -- "$arg")"
        fi
    fi
    case "$target" in
        *"'"*)
            printf '%s: в пути есть одинарная кавычка, такой путь не поддерживается: %s\n' "$caller" "$target" >&2
            return 1
            ;;
        *$'\n'*)
            printf '%s: в пути есть перевод строки, такой путь не поддерживается\n' "$caller" >&2
            return 1
            ;;
    esac
    printf '%s: %s\n' "$noun" "$target"

    # --- имя псевдонима ---
    default="$(_ja_default_name "$prefix" "$target")"
    if [ -z "$name" ]; then
        if [ -t 0 ]; then
            read -r -p "имя псевдонима [$default]: " name
            name="${name:-$default}"
        else
            printf '%s: нет имени псевдонима (ключ -n) и нет терминала для вопроса\n' "$caller" >&2
            return 1
        fi
    fi
    if ! printf '%s' "$name" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_-]*$'; then
        printf '%s: недопустимое имя псевдонима: «%s»\n' "$caller" "$name" >&2
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
        printf '%s: «%s» — это alias в %s.just.\n' "$caller" "$name" "$alias_hit" >&2
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
        printf '  в другое место, чем на остальных.\n'
        printf '  Общий псевдоним правят в %s/Config — отсюда туда %s не пишет.\n\n' "${repo:-<репозиторий>}" "$caller"
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
                            printf '%s: недопустимое имя псевдонима: «%s»\n' "$caller" "$name" >&2
                            return 1
                        fi
                        in_local=0
                        _jn_has_recipe "$local_file" "$name" && in_local=1
                        ;;
                esac
            else
                printf '%s: конфликт имени, нужен ключ -f для подтверждения\n' "$caller" >&2
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
                printf '%s: «%s» уже есть в local.just, нужен ключ -f\n' "$caller" "$name" >&2
                return 1
            fi
        fi
    fi

    # --- вывод или запись ---
    if [ "$print" -eq 1 ]; then
        printf '\n--- блок для вставки ---\n'
        _ja_block "$name" "$desc" "$target" "$group"
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
    _ja_block "$name" "$desc" "$target" "$group" >> "$local_file"

    if just --justfile "$justfile" --working-directory . --summary >/dev/null 2>&1; then
        rm -f "$local_file.bak"
        printf 'записано в %s\n' "$local_file"
        if [ "$in_group" -eq 1 ] || [ "$in_global" -eq 1 ]; then
            local loser="group.just"
            [ "$in_global" -eq 1 ] && loser="global.just"
            printf '%s: local.just перекрывает %s\n' "$name" "$loser"
        fi
        case "$kind" in
            dir)  printf 'перейти: go_dir %s\n' "$name" ;;
            file) printf 'открыть: j_edit %s\nсмотреть: j_tail %s\n' "$name" "$name" ;;
        esac
    else
        cat "$local_file.bak" > "$local_file"
        rm -f "$local_file.bak"
        printf '%s: just не разобрал результат, изменения отменены:\n' "$caller" >&2
        just --justfile "$justfile" --working-directory . --summary >&2 || true
        return 1
    fi
}
