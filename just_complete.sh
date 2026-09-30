#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# just_complete.sh — автодополнение для `just` и для алиаса `j`.
#
# Подключается блоком из init.sh (--shell):
#     JUST_J_JUSTFILE="<каталог конфигов>/justfile"
#     source /путь/к/репозиторию/just_complete.sh
#
# Всё, что умеет дополнять just, — флаги, рецепты, переменные — делает сам
# бинарник (`just --completions bash`, динамическое дополнение с just 1.48):
# при нажатии Tab он разбирает набранную строку и отвечает списком. Здесь только
# подключение этого механизма и его переадресация для j.
#
# j — это `just --justfile <cfg>/justfile --working-directory .`, но в набранной
# строке этих флагов нет, поэтому рецепты искались бы в justfile текущего каталога.
# Обёртка перед вызовом подставляет --justfile в список слов.
# ---------------------------------------------------------------------------

command -v just >/dev/null 2>&1 || return 0

# регистрирует _clap_complete_just для just
source <(just --completions bash)

# версии до 1.48 отдают статический скрипт без этой функции — j тогда не трогаем
declare -F _clap_complete_just >/dev/null 2>&1 || {
    printf 'just_complete: для дополнения j нужен just 1.48+ (сейчас %s)\n' \
        "$(just --version | awk '{print $2}')" >&2
    return 0
}

_just_j_complete() {
    local jf="${JUST_J_JUSTFILE:-${JUST_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/just}/justfile}"

    # локальные копии переменных, которые читает _clap_complete_just: на время
    # вызова вместо `j ...` она видит `just --justfile <jf> ...`
    local -a rest=("${COMP_WORDS[@]:1}")
    local cword=$((COMP_CWORD + 2))
    local lead="${COMP_LINE%%[![:space:]]*}"
    local tail="${COMP_LINE#"$lead"}"
    tail="${tail#"${COMP_WORDS[0]}"}"
    local line="just --justfile \"$jf\"$tail"

    local -a COMP_WORDS=(just --justfile "$jf" "${rest[@]}")
    local COMP_CWORD=$cword
    local COMP_LINE="$line"
    _clap_complete_just
}

if [[ "${BASH_VERSINFO[0]}" -gt 4 || ( "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 4 ) ]]; then
    complete -o nospace -o bashdefault -o nosort -F _just_j_complete j
else
    complete -o nospace -o bashdefault -F _just_j_complete j
fi
