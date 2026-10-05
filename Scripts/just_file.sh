#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# just_file.sh — сохранить файл как псевдоним для j_edit и j_tail.
# Парный к just_dir: тот сохраняет каталог, этот — файл.
#
# Подключение (это делает init.sh --shell):
#     source /путь/к/репозиторию/Scripts/just_file.sh
#
# Использование:
#     just_file /var/log/nginx/error.log    псевдоним для файла
#     just_file ./app.conf -n app -d "Конфиг"   имя и описание без вопросов
#     just_file /etc/hosts -p               только напечатать блок, ничего не писать
#     just_file /etc/hosts -f               не переспрашивать при конфликте имён
#
# Путь к файлу обязателен (у файла нет «текущего»), файл должен существовать.
#
# Пишет ровно в один файл — local.just в каталоге конфигов (как just_new): путь
# принадлежит этой машине. Файлы репозитория (Config/global.just, Config/<группа>/
# group.just) правятся редактором из каталога проекта; для переноса туда есть -p.
#
# Результат — рецепт группы j_file, который печатает путь:
#
#     # Лог nginx
#     [group('j_file')]
#     file_error_log:
#         @echo '/var/log/nginx/error.log'
#
# Открыть: j_edit file_error_log. Смотреть: j_tail file_error_log.
# Вся логика — в just_alias.sh (общая с just_dir).
# ---------------------------------------------------------------------------

# return работает при source, exit — при прямом запуске
if ! command -v just >/dev/null 2>&1; then return 0 2>/dev/null || exit 1; fi

if ! declare -F _ja_add >/dev/null 2>&1; then
    # shellcheck source=just_alias.sh
    source "$(dirname "${BASH_SOURCE[0]}")/just_alias.sh"
fi

# справка для -h: шапка этого файла
_just_file_usage() {
    sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

just_file() { _ja_add just_file j_file file "$@"; }

# Tab после just_file дополняет пути к файлам (флаги набираются руками)
complete -f just_file

# Запущен как скрипт (а не подключён через source) — работает так же.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    just_file "$@"
fi
