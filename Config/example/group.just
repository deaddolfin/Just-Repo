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
