#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# init.sh — развернуть just-конфигурацию этого репозитория на текущей машине.
#
#   ./init.sh [--shell] <группа>
#
#   --shell   дописать интеграцию (алиас j, автодополнение, just_new)
#             в ~/.bashrc между маркерами; без флага блок просто печатается
#
# Скрипт идемпотентен: повторный запуск не трогает local.just и env.
# ---------------------------------------------------------------------------
set -euo pipefail

MIN_JUST="1.35.0"
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/just"
MARK_BEGIN="# >>> just-aliases >>>"
MARK_END="# <<< just-aliases <<<"

WITH_SHELL=0
GROUP=""

step() { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
die()  { printf '\nОшибка: %s\n' "$*" >&2; exit 1; }

groups_available() {
    local d
    for d in "$REPO_DIR"/Config/*/; do
        [ -d "$d" ] || continue
        basename "$d"
    done
}

usage() {
    printf 'Использование: ./init.sh [--shell] <группа>\n\n'
    printf 'Группы, доступные в этом репозитории:\n'
    groups_available | sed 's/^/  - /'
}

# имена рецептов в just-файле (без alias, set, import и переменных)
recipe_names() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -E -n 's/^([a-zA-Z_][a-zA-Z0-9_-]*)([[:space:]]+[^:=]*)?:([^=].*)?$/\1/p' "$f" \
        | grep -Ev '^(set|alias|import|export|mod)$' || true
}

env_keys() {
    local f="$1"
    [ -f "$f" ] || return 0
    grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$f" | sed 's/=$//' || true
}

version_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# --- разбор аргументов ------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --shell)   WITH_SHELL=1 ;;
        -h|--help) usage; exit 0 ;;
        -*)        die "неизвестный флаг: $1" ;;
        *)
            [ -z "$GROUP" ] || die "группа указана дважды: «$GROUP» и «$1»"
            GROUP="$1"
            ;;
    esac
    shift
done

if [ -z "$GROUP" ]; then
    usage >&2
    die "не указана группа"
fi
if [ ! -d "$REPO_DIR/Config/$GROUP" ]; then
    usage >&2
    die "группы «$GROUP» нет в $REPO_DIR/Config"
fi
if [ ! -f "$REPO_DIR/Config/$GROUP/group.just" ]; then
    die "в группе «$GROUP» нет файла group.just"
fi

# --- 1. just ----------------------------------------------------------------

install_just() {
    if command -v apt-get >/dev/null 2>&1; then
        local sudo_cmd=""
        if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
            sudo_cmd="sudo"
        fi
        if [ "$(id -u)" -eq 0 ] || [ -n "$sudo_cmd" ]; then
            info "пробую apt-get install just"
            $sudo_cmd apt-get install -y just >/dev/null 2>&1 || warn "apt-get не справился, иду дальше"
        else
            info "нет ни root, ни sudo — apt-get пропускаю"
        fi
    fi

    local v=""
    if command -v just >/dev/null 2>&1; then
        v="$(just --version 2>/dev/null | awk '{print $2}')"
    fi
    if [ -n "$v" ] && version_ge "$v" "$MIN_JUST"; then
        return 0
    fi

    info "ставлю just в ~/.local/bin официальным установщиком"
    mkdir -p "$HOME/.local/bin"
    curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
        | bash -s -- --to "$HOME/.local/bin" >/dev/null \
        || die "не удалось скачать и установить just"
    export PATH="$HOME/.local/bin:$PATH"
    warn "just поставлен в ~/.local/bin — убедитесь, что каталог есть в PATH после перелогина"
}

step "just"
if command -v just >/dev/null 2>&1; then
    JUST_VER="$(just --version | awk '{print $2}')"
    if version_ge "$JUST_VER" "$MIN_JUST"; then
        info "уже установлен: just $JUST_VER"
    else
        warn "just $JUST_VER старее требуемой $MIN_JUST (нужны allow-duplicate-variables и import?)"
        install_just
    fi
else
    info "не найден"
    install_just
fi
command -v just >/dev/null 2>&1 || die "just не появился в PATH"
JUST_VER="$(just --version | awk '{print $2}')"
version_ge "$JUST_VER" "$MIN_JUST" || die "установлен just $JUST_VER, нужна $MIN_JUST или новее"

# --- 2. каталог конфигов ----------------------------------------------------

step "каталог конфигов"
mkdir -p "$CONFIG_DIR"
info "$CONFIG_DIR"

# группа прошлого развёртывания — нужна, чтобы предупредить о смене
PREV_GROUP=""
if [ -f "$CONFIG_DIR/state.env" ]; then
    PREV_GROUP="$(sed -n 's/^JUST_GROUP=//p' "$CONFIG_DIR/state.env" | head -n 1)"
fi
if [ -n "$PREV_GROUP" ] && [ "$PREV_GROUP" != "$GROUP" ]; then
    info "группа меняется: $PREV_GROUP -> $GROUP"
fi

# --- 3. основной justfile ---------------------------------------------------

step "основной justfile"
JUSTFILE="$CONFIG_DIR/justfile"
TMP_JUSTFILE="$(mktemp)"
trap 'rm -f "$TMP_JUSTFILE"' EXIT

{
    printf '# Создан init.sh из %s — правки здесь перетираются при следующем запуске.\n' "$REPO_DIR"
    printf '# Свои команды: local.just (машинные) или файлы репозитория (общие).\n\n'
    printf 'set shell := ["bash", "-euo", "pipefail", "-c"]\n'
    printf 'set allow-duplicate-recipes := true\n'
    printf 'set allow-duplicate-variables := true\n'
    printf 'set dotenv-path := "%s/env"\n\n' "$CONFIG_DIR"
    printf 'repo       := "%s"\n' "$REPO_DIR"
    printf 'group      := "%s"\n' "$GROUP"
    printf 'config_dir := "%s"\n\n' "$CONFIG_DIR"
    printf '# Приоритет задаёт порядок импортов: побеждает ПЕРВОЕ определение рецепта,\n'
    printf '# поэтому local идёт первым и перекрывает group, а group — global.\n'
    printf "import? 'local.just'\n"
    printf "import  'group.just'\n"
    printf "import  'global.just'\n\n"
    printf 'default:\n'
    printf '    @just --list --unsorted\n'
} > "$TMP_JUSTFILE"

if [ -f "$JUSTFILE" ] && ! cmp -s "$TMP_JUSTFILE" "$JUSTFILE"; then
    cp "$JUSTFILE" "$JUSTFILE.bak"
    info "прежний justfile сохранён как justfile.bak"
fi
cat "$TMP_JUSTFILE" > "$JUSTFILE"
info "записан $JUSTFILE"

# --- 4. симлинки на файлы репозитория ---------------------------------------

link_file() {
    local src="$1" dst="$2"
    [ -e "$src" ] || die "нет файла $src"
    # Обычный файл на месте ссылки бэкапим — но только если он чем-то отличается
    # от файла репозитория: иначе это копия, оставленная прошлым запуском там,
    # где симлинки недоступны (например, Git Bash без winsymlinks), и плодить
    # .bak на каждом прогоне незачем.
    if [ -e "$dst" ] && [ ! -L "$dst" ] && ! cmp -s "$src" "$dst"; then
        cp "$dst" "$dst.bak"
        warn "$(basename "$dst") был обычным файлом, копия — $(basename "$dst").bak"
    fi
    ln -sfn "$src" "$dst"
    if [ -L "$dst" ]; then
        info "$(basename "$dst") -> $src"
    else
        info "$(basename "$dst") — копия $src (симлинки недоступны)"
    fi
}

step "файлы репозитория"
link_file "$REPO_DIR/Config/global.just"       "$CONFIG_DIR/global.just"
link_file "$REPO_DIR/Config/$GROUP/group.just" "$CONFIG_DIR/group.just"

# --- 5. локальный файл ------------------------------------------------------

step "локальные алиасы"
LOCAL_FILE="$CONFIG_DIR/local.just"
if [ -f "$LOCAL_FILE" ]; then
    info "local.just уже есть — не трогаю"
else
    {
        printf '# local.just — алиасы и переменные только этой машины.\n'
        printf '# В репозиторий не попадает. Сюда же пишет just_new.\n'
        printf '# Одноимённый рецепт здесь перекрывает такой же из group.just и global.just.\n'
    } > "$LOCAL_FILE"
    info "создан $LOCAL_FILE"
fi

# --- 6. переменные окружения ------------------------------------------------

step "переменные окружения"
ENV_FILE="$CONFIG_DIR/env"
EX_GLOBAL="$REPO_DIR/Config/env.example"
EX_GROUP="$REPO_DIR/Config/$GROUP/env.example"

if [ ! -f "$ENV_FILE" ]; then
    {
        printf '# Локальные значения переменных. Собрано init.sh из *.example.\n'
        printf '# В репозиторий не возвращается, права 600.\n\n'
        [ -f "$EX_GLOBAL" ] && cat "$EX_GLOBAL"
        printf '\n'
        [ -f "$EX_GROUP" ] && cat "$EX_GROUP"
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    info "создан $ENV_FILE (600) — заполните значения"
else
    chmod 600 "$ENV_FILE"
    info "env уже есть — не трогаю"
    if [ -n "$PREV_GROUP" ] && [ "$PREV_GROUP" != "$GROUP" ]; then
        warn "группа сменилась ($PREV_GROUP -> $GROUP), а env остался прежним:"
        warn "переменные новой группы сами не появятся, лишние от старой не исчезнут"
    fi
    EXPECTED="$( { env_keys "$EX_GLOBAL"; env_keys "$EX_GROUP"; } | sort -u )"
    ACTUAL="$( env_keys "$ENV_FILE" | sort -u )"
    MISSING="$( comm -23 <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ACTUAL") | grep -v '^$' || true )"
    EXTRA="$( comm -13 <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ACTUAL") | grep -v '^$' || true )"
    if [ -n "$MISSING" ]; then
        warn "в env нет ключей из *.example: $(printf '%s ' $MISSING)"
    fi
    if [ -n "$EXTRA" ]; then
        info "в env есть ключи, которых нет в *.example: $(printf '%s ' $EXTRA)"
    fi
fi

# --- 7. состояние для just_new ----------------------------------------------

step "состояние"
{
    printf 'JUST_REPO=%s\n' "$REPO_DIR"
    printf 'JUST_GROUP=%s\n' "$GROUP"
    printf 'JUST_CONFIG_DIR=%s\n' "$CONFIG_DIR"
} > "$CONFIG_DIR/state.env"
info "записан $CONFIG_DIR/state.env"

# --- 8. интеграция с шеллом -------------------------------------------------

shell_block() {
    printf '%s\n' "$MARK_BEGIN"
    printf "alias j='just --justfile \"%s/justfile\" --working-directory .'\n" "$CONFIG_DIR"
    printf 'complete -W "$(just --justfile "%s/justfile" --summary 2>/dev/null)" j\n' "$CONFIG_DIR"
    printf 'source "%s/just_new.sh"\n' "$REPO_DIR"
    printf '%s\n' "$MARK_END"
}

step "интеграция с шеллом"
BASHRC="$HOME/.bashrc"
if [ "$WITH_SHELL" -eq 1 ]; then
    touch "$BASHRC"
    if grep -qF "$MARK_BEGIN" "$BASHRC"; then
        TMP_RC="$(mktemp)"
        awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
            $0 == b { skip = 1; next }
            $0 == e { skip = 0; next }
            !skip   { print }
        ' "$BASHRC" > "$TMP_RC"
        cat "$TMP_RC" > "$BASHRC"
        rm -f "$TMP_RC"
        info "прежний блок в ~/.bashrc заменён"
    fi
    shell_block >> "$BASHRC"
    info "блок добавлен в $BASHRC — выполните: source ~/.bashrc"
else
    info "добавьте в ~/.bashrc (или перезапустите с флагом --shell):"
    printf '\n'
    shell_block | sed 's/^/      /'
fi

# --- 9. проверка и отчёт о перекрытиях --------------------------------------

step "проверка"
if just --justfile "$JUSTFILE" --working-directory . --summary >/dev/null 2>&1; then
    info "конфигурация разбирается, список команд: just --justfile \"$JUSTFILE\" --list"
else
    warn "just не смог разобрать конфигурацию:"
    just --justfile "$JUSTFILE" --working-directory . --summary || true
fi

SHADOW_TMP="$(mktemp)"
for label in local group global; do
    f="$CONFIG_DIR/$label.just"
    [ -f "$f" ] || continue
    recipe_names "$f" | sort -u | sed "s/\$/ $label/" >> "$SHADOW_TMP"
done
DUPS="$(awk '{print $1}' "$SHADOW_TMP" | sort | uniq -d || true)"
if [ -n "$DUPS" ]; then
    printf '\n   Перекрытые рецепты (побеждает первое определение: local > group > global):\n'
    for name in $DUPS; do
        where="$(awk -v n="$name" '$1 == n { printf "%s ", $2 }' "$SHADOW_TMP")"
        winner="$(awk -v n="$name" '$1 == n { print $2; exit }' "$SHADOW_TMP")"
        printf '     %-20s определён в: %s— работает %s\n' "$name" "$where" "$winner"
    done
fi
rm -f "$SHADOW_TMP"

printf '\nГотово. Группа «%s», конфигурация в %s\n' "$GROUP" "$CONFIG_DIR"
