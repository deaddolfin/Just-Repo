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
# Перейти по нему: go_dir dir_app. Вся логика — в just_alias.sh (общая с just_file).
# ---------------------------------------------------------------------------

# return работает при source, exit — при прямом запуске
if ! command -v just >/dev/null 2>&1; then return 0 2>/dev/null || exit 1; fi

if ! declare -F _ja_add >/dev/null 2>&1; then
    # shellcheck source=just_alias.sh
    source "$(dirname "${BASH_SOURCE[0]}")/just_alias.sh"
fi

# справка для -h: шапка этого файла
_just_dir_usage() {
    sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

just_dir() { _ja_add just_dir go_dir dir "$@"; }

# Tab после just_dir дополняет каталоги (флаги набираются руками)
complete -o dirnames just_dir

# Запущен как скрипт (а не подключён через source) — работает так же, но каталог
# по умолчанию берётся из места запуска.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    just_dir "$@"
fi
