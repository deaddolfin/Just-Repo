#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# just_complete.sh — автодополнение для `just` и для алиасов `j` и `jg`.
#
# Подключается блоком из init.sh (--shell):
#     alias j='just'
#     alias jg='just -g'
#     source /путь/к/репозиторию/Scripts/just_complete.sh
#
# Всё, что умеет дополнять just, — флаги, рецепты, переменные — делает сам
# бинарник (`just --completions bash`, динамическое дополнение с just 1.48):
# при нажатии Tab он разбирает набранную строку и отвечает списком. Здесь только
# подключение этого механизма и его переадресация для алиасов.
#
# Бинарник должен видеть в строке настоящую команду, а не имя алиаса: для jg в
# набранной строке нет ключа -g, и рецепты искались бы в justfile текущего каталога.
# Обёртка перед вызовом заменяет первое слово: j -> just, jg -> just -g.
# ---------------------------------------------------------------------------

command -v just >/dev/null 2>&1 || return 0

# регистрирует _clap_complete_just для just
source <(just --completions bash)

# версии до 1.48 отдают статический скрипт без этой функции — алиасы тогда не трогаем
declare -F _clap_complete_just >/dev/null 2>&1 || {
    printf 'just_complete: для дополнения j и jg нужен just 1.48+ (сейчас %s)\n' \
        "$(just --version | awk '{print $2}')" >&2
    return 0
}

_just_alias_complete() {
    # ключи, которые алиас добавляет к just
    local -a extra=()
    [[ "${COMP_WORDS[0]}" == jg ]] && extra=(-g)

    # локальные копии переменных, которые читает _clap_complete_just: на время
    # вызова вместо `jg ...` она видит `just -g ...`
    local -a rest=("${COMP_WORDS[@]:1}")
    local cword=$((COMP_CWORD + ${#extra[@]}))
    local lead="${COMP_LINE%%[![:space:]]*}"
    local tail="${COMP_LINE#"$lead"}"
    tail="${tail#"${COMP_WORDS[0]}"}"
    local line="just${extra[*]:+ ${extra[*]}}$tail"

    local -a COMP_WORDS=(just "${extra[@]}" "${rest[@]}")
    local COMP_CWORD=$cword
    local COMP_LINE="$line"
    _clap_complete_just
}

if [[ "${BASH_VERSINFO[0]}" -gt 4 || ( "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 4 ) ]]; then
    complete -o nospace -o bashdefault -o nosort -F _just_alias_complete j jg
else
    complete -o nospace -o bashdefault -F _just_alias_complete j jg
fi
