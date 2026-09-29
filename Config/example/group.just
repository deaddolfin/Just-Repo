# ---------------------------------------------------------------------------
# group.just — переменные и алиасы группы «example».
#
# Копируйте каталог Config/example под новым именем, чтобы завести свою группу:
# имя каталога и есть имя группы, которое принимает init.
#
# Одноимённые рецепты с атрибутами [unix] / [windows] — штатный способ развести
# платформы: just сам выберет подходящий вариант.
# ---------------------------------------------------------------------------

# хост группы; переопределяется переменной окружения H
host := env_var_or_default("H", "example-host")

# логи systemd-юнита: j logs app 500
[unix]
logs svc="nginx" n="200":
    journalctl -u {{svc}} -n {{n}} --no-pager

# занятые порты со слушающими процессами
[unix]
ports:
    ss -tulpn | grep LISTEN

[windows]
ports:
    Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Format-Table LocalPort, OwningProcess

# запрос к API: адрес и токен приходят из env, не из justfile
[unix]
api path="/health":
    curl -fsS --max-time 5 -H "Authorization: Bearer $API_TOKEN" "$API_BASE{{path}}" | jq .

[windows]
api path="/health":
    Invoke-RestMethod -Uri "$env:API_BASE{{path}}" -Headers @{ Authorization = "Bearer $env:API_TOKEN" } -TimeoutSec 5 | ConvertTo-Json -Depth 5

# выкатить тег: shebang-рецепт выполняется одним процессом, поэтому cd работает
[unix]
release tag:
    #!/usr/bin/env bash
    set -euo pipefail
    cd /srv/app
    git fetch --tags
    git checkout "{{tag}}"
    npm ci
    npm run build
    sudo systemctl restart app
    echo "выкачен {{tag}}"

# перезапуск сервиса на хосте группы
[unix]
[confirm("Перезапустить сервис на хосте группы?")]
restart svc="app":
    ssh {{host}} "sudo systemctl restart {{svc}}"

# ---------------------------------------------------------------------------
# Последовательность и параллель
# ---------------------------------------------------------------------------

# Последовательность just даёт сам: зависимости выполняются по порядку, падение
# любой прерывает цепочку и до тела рецепта дело не доходит. Внутри тела то же
# построчно — после ненулевого кода следующая строка не выполняется (кроме строк
# с префиксом «-»). Зависимости, указанные после &&, выполняются ПОСЛЕ тела и
# только если оно отработало успешно.
#
# Пустая строка ниже обязательна: описанием в --list становится последняя строка
# комментария, примыкающего к рецепту.

# проверить конфиг nginx и применить его только при успехе
[unix]
apply: check-config && reload
    @echo "конфигурация проверена и применена"

# синтаксическая проверка конфигурации
[unix]
check-config:
    sudo nginx -t

# мягкая перезагрузка без разрыва соединений
[unix]
reload:
    sudo systemctl reload nginx

# Параллель just не умеет: зависимости всегда последовательные, аналога make -j
# нет. Запускать разом приходится средствами шелла и только в shebang-рецепте —
# обычные строки тела выполняются каждая в своём шелле, фоновые задачи их
# не переживут.

# опросить хосты разом; рецепт падает, если недоступен хоть один
[unix]
uptime-all +hosts="web-1 web-2 db-1":
    #!/usr/bin/env bash
    set -euo pipefail
    pids=()
    for h in {{hosts}}; do
        ( ssh "$h" uptime | sed "s|^|$h: |" ) &
        pids+=($!)
    done
    fail=0
    for p in "${pids[@]}"; do
        # голый wait вернул бы 0 и скрыл ошибки — ждём каждый PID отдельно
        wait "$p" || fail=1
    done
    [ "$fail" -eq 0 ] || { echo "часть хостов недоступна" >&2; exit 1; }
    echo "все хосты ответили"

# то же короче, когда своя логика не нужна: код возврата отдаёт сам xargs
[unix]
collect-logs +svcs="nginx app":
    printf '%s\n' {{svcs}} | xargs -P 4 -I{} sh -c 'journalctl -u {} -n 200 --no-pager > "/tmp/{}.log"'
