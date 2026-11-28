#!/bin/bash
# ==============================================================================
# FORM // SYSTEM — AUTO-RESIGN & KEEP-ALIVE DAEMON FOR iOS (7-DAY BYPASS)
# ==============================================================================
# Автоматически пересобирает, продлевает бесплатный 7-дневный профиль Apple
# и устанавливает приложение form на твой iPhone по воздуху (Wi-Fi) или USB.
# ==============================================================================

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/autoresign.log"
STATE_FILE="$SCRIPT_DIR/last_resign.txt"
ALERT_FILE="$SCRIPT_DIR/last_alert.txt"
PROJECT_FILE="$PROJECT_DIR/form.xcodeproj"
SCHEME="form"
MAX_AGE_DAYS=2 # Продлеваем каждые 2 дня (запас 5 дней гарантирует, что профиль никогда не истечет)
MAX_AGE_SECONDS=$((MAX_AGE_DAYS * 86400))
LOG_MAX_BYTES=1048576

LOCK_DIR="/tmp/form_autoresign.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
LOCK_OWNED=0
PROV_BACKUP_DIR="/tmp/form_prov_backup_$$"
PLUGINS_BACKUP_DIR="/tmp/form_plugins_backup_$$"
WIDGET_ENT_FILE="/tmp/form_widget_entitlements_$$.plist"
MAIN_ENT_FILE="/tmp/form_entitlements_$$.plist"
ACTIVE_APP_PATH=""
MOVED_MAIN_PROV_NAME=""
MOVED_WIDGET_PROV_NAME=""

# Цвета для красивого вывода в терминал
CLR_RESET="\033[0m"
CLR_RED="\033[1;31m"
CLR_GREEN="\033[1;32m"
CLR_YELLOW="\033[1;33m"
CLR_CYAN="\033[1;36m"
CLR_GRAY="\033[0;90m"

rotate_log_if_needed() {
    if [[ -f "$LOG_FILE" ]]; then
        local log_size
        log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ "$log_size" =~ ^[0-9]+$ && $log_size -gt $LOG_MAX_BYTES ]]; then
            local tmp_log="${LOG_FILE}.tmp.$$"
            tail -n 500 "$LOG_FILE" > "$tmp_log" 2>/dev/null && mv -f "$tmp_log" "$LOG_FILE"
            rm -f "$tmp_log" 2>/dev/null || true
        fi
    fi
}

log_msg() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] $1"
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

notify_mac() {
    local title="${1//\\/\\\\}"
    title="${title//\"/\\\"}"
    local message="${2//\\/\\\\}"
    message="${message//\"/\\\"}"
    osascript -e 'on run argv' \
              -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name "Glass"' \
              -e 'end run' -- "$1" "$2" 2>/dev/null || true
}

acquire_lock() {
    local force_flag="$1"
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        local old_pid=""
        [[ -f "$LOCK_PID_FILE" ]] && old_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
            log_msg "⏳ Другой процесс autoresign.sh (PID $old_pid) уже выполняется. Выход."
            [[ "$force_flag" == "--force" ]] && exit 1 || exit 0
        fi
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            log_msg "❌ Ошибка: Не удалось захватить lock $LOCK_DIR."
            exit 1
        fi
    fi
    echo "$$" > "$LOCK_PID_FILE"
    LOCK_OWNED=1
}

cleanup_autoresign() {
    local prof_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

    if [[ -d "$PROV_BACKUP_DIR" ]]; then
        if [[ -n "$MOVED_MAIN_PROV_NAME" && -f "$PROV_BACKUP_DIR/$MOVED_MAIN_PROV_NAME" ]]; then
            local cur_main_prov cur_main_info cur_main_rem
            cur_main_prov=$(find_newest_profile "com.form.app.form")
            cur_main_info=$(get_profile_info "$cur_main_prov")
            cur_main_rem="${cur_main_info#*|}"
            cur_main_rem="${cur_main_rem%%|*}"
            if [[ -z "$cur_main_prov" || ! "$cur_main_rem" =~ ^[0-9]+$ || $cur_main_rem -le 0 ]]; then
                mkdir -p "$prof_dir" 2>/dev/null || true
                cp -f "$PROV_BACKUP_DIR/$MOVED_MAIN_PROV_NAME" "$prof_dir/" 2>/dev/null || true
            fi
        fi
        if [[ -n "$MOVED_WIDGET_PROV_NAME" && -f "$PROV_BACKUP_DIR/$MOVED_WIDGET_PROV_NAME" ]]; then
            local cur_w_prov cur_w_info cur_w_rem
            cur_w_prov=$(find_newest_profile "com.form.app.form.FormWidget")
            cur_w_info=$(get_profile_info "$cur_w_prov")
            cur_w_rem="${cur_w_info#*|}"
            cur_w_rem="${cur_w_rem%%|*}"
            if [[ -z "$cur_w_prov" || ! "$cur_w_rem" =~ ^[0-9]+$ || $cur_w_rem -le 0 ]]; then
                mkdir -p "$prof_dir" 2>/dev/null || true
                cp -f "$PROV_BACKUP_DIR/$MOVED_WIDGET_PROV_NAME" "$prof_dir/" 2>/dev/null || true
            fi
        fi
        rm -rf "$PROV_BACKUP_DIR" 2>/dev/null || true
    fi

    if [[ -d "$PLUGINS_BACKUP_DIR/PlugIns" && -n "$ACTIVE_APP_PATH" && -d "$ACTIVE_APP_PATH" && ! -d "$ACTIVE_APP_PATH/PlugIns" ]]; then
        mv -f "$PLUGINS_BACKUP_DIR/PlugIns" "$ACTIVE_APP_PATH/PlugIns" 2>/dev/null || true
    fi

    rm -rf "$PLUGINS_BACKUP_DIR" 2>/dev/null || true
    rm -f "$WIDGET_ENT_FILE" "$MAIN_ENT_FILE" 2>/dev/null || true

    if [[ $LOCK_OWNED -eq 1 ]]; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
    fi
}

get_paired_device() {
    # Ищем подключенный по проводу или Wi-Fi («планета» в Xcode) iPhone с 3 попытками
    local attempts=3
    for ((i=1; i<=attempts; i++)); do
        local line
        line=$(xcrun devicectl list devices 2>/dev/null | grep -i "available (paired)" | grep -i "iPhone" | head -n 1)
        if [[ -n "$line" ]]; then
            local dev_id
            dev_id=$(echo "$line" | grep -oE '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40})' | head -n 1)
            local dev_name
            dev_name=$(echo "$line" | awk -F'   ' '{print $1}' | xargs)
            if [[ -n "$dev_id" ]]; then
                echo "$dev_id|$dev_name"
                return 0
            fi
        fi
        if [[ $i -lt $attempts ]]; then
            sleep 2
        fi
    done
    return 1
}

get_profile_info() {
    local prof_path="$1"
    if [[ ! -f "$prof_path" ]]; then
        echo "0|0|none"
        return
    fi
    security cms -D -i "$prof_path" 2>/dev/null | python3 -c "
import sys, plistlib, datetime
try:
    data = sys.stdin.buffer.read()
    if data:
        pl = plistlib.loads(data)
        exp = pl.get('ExpirationDate')
        if exp:
            if exp.tzinfo is None:
                exp = exp.replace(tzinfo=datetime.timezone.utc)
            exp_local = exp.astimezone()
            exp_ts = int(exp_local.timestamp())
            now_ts = int(datetime.datetime.now(datetime.timezone.utc).timestamp())
            rem_sec = max(0, exp_ts - now_ts)
            exp_str = exp_local.strftime('%Y-%m-%d %H:%M')
            print(f'{exp_ts}|{rem_sec}|{exp_str}')
            sys.exit(0)
except Exception:
    pass
print('0|0|none')
" 2>/dev/null || echo "0|0|none"
}

find_newest_profile() {
    local bundle_suffix="$1"
    local prof_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    [[ ! -d "$prof_dir" ]] && return
    python3 -c "
import os, glob, subprocess, plistlib, datetime, sys
prof_dir = sys.argv[1]
suffix = sys.argv[2]
best_path = ''
best_ts = -1
for p in glob.glob(os.path.join(prof_dir, '*.mobileprovision')):
    try:
        res = subprocess.run(['security', 'cms', '-D', '-i', p], capture_output=True)
        if res.returncode != 0 or not res.stdout:
            continue
        pl = plistlib.loads(res.stdout)
        app_id = pl.get('Entitlements', {}).get('application-identifier', '')
        if app_id.endswith('.' + suffix):
            exp = pl.get('ExpirationDate')
            if exp:
                if exp.tzinfo is None:
                    exp = exp.replace(tzinfo=datetime.timezone.utc)
                ts = int(exp.timestamp())
                if ts > best_ts:
                    best_ts = ts
                    best_path = p
    except Exception:
        pass
if best_path:
    print(best_path)
" "$prof_dir" "$bundle_suffix" 2>/dev/null
}

show_status() {
    echo -e "${CLR_CYAN}======================================================${CLR_RESET}"
    echo -e "${CLR_CYAN}        FORM // SYSTEM — СТАТУС СЕРТИФИКАТА И АВТОМАТИЗАЦИИ${CLR_RESET}"
    echo -e "${CLR_CYAN}======================================================${CLR_RESET}"

    local dev_info
    dev_info=$(get_paired_device)
    if [[ -n "$dev_info" ]]; then
        local dev_id="${dev_info%%|*}"
        local dev_name="${dev_info##*|}"
        echo -e "Устройство: ${CLR_GREEN}✓ $dev_name${CLR_RESET} [${CLR_GRAY}$dev_id${CLR_RESET}]"
        echo -e "Сопряжение: ${CLR_GREEN}Подключено (Wi-Fi / USB «Планета» активна)${CLR_RESET}"
    else
        echo -e "Устройство: ${CLR_YELLOW}Не найдено в текущей сети Wi-Fi / USB${CLR_RESET}"
        echo -e "Сопряжение: ${CLR_YELLOW}Ожидание сопряжения с iPhone...${CLR_RESET}"
    fi

    # Ищем самый свежий профиль form.app и FormWidget
    local main_prov
    main_prov=$(find_newest_profile "com.form.app.form")

    if [[ -n "$main_prov" && -f "$main_prov" ]]; then
        local prof_info
        prof_info=$(get_profile_info "$main_prov")
        local exp_ts="${prof_info%%|*}"
        local rest="${prof_info#*|}"
        local rem_sec="${rest%%|*}"
        local exp_str="${rest#*|}"
        local rem_days=$((rem_sec / 86400))
        local rem_hours=$(((rem_sec % 86400) / 3600))

        if [[ $rem_sec -gt 0 ]]; then
            echo -e "Профиль Apple: ${CLR_GREEN}АКТИВЕН до $exp_str${CLR_RESET} (осталось: $rem_days дн. $rem_hours ч.)"
        else
            echo -e "Профиль Apple: ${CLR_RED}ИСТЕК ($exp_str)${CLR_RESET}. Запусти --force или открой Xcode -> Settings -> Accounts."
        fi
    else
        echo -e "Профиль Apple: ${CLR_YELLOW}Не найден в UserData/Provisioning Profiles${CLR_RESET}"
    fi

    local widget_prov_status
    widget_prov_status=$(find_newest_profile "com.form.app.form.FormWidget")
    if [[ -n "$widget_prov_status" && -f "$widget_prov_status" ]]; then
        local w_status_info w_status_rest w_status_rem w_status_str w_status_days w_status_hours
        w_status_info=$(get_profile_info "$widget_prov_status")
        w_status_rest="${w_status_info#*|}"
        w_status_rem="${w_status_rest%%|*}"
        w_status_str="${w_status_rest#*|}"
        w_status_days=$((w_status_rem / 86400))
        w_status_hours=$(((w_status_rem % 86400) / 3600))
        if [[ $w_status_rem -gt 0 ]]; then
            echo -e "Профиль виджета: ${CLR_GREEN}АКТИВЕН до $w_status_str${CLR_RESET} (осталось: $w_status_days дн. $w_status_hours ч.)"
        else
            echo -e "Профиль виджета: ${CLR_RED}ИСТЕК ($w_status_str)${CLR_RESET}. Запусти --force."
        fi
    else
        echo -e "Профиль виджета: ${CLR_YELLOW}Не найден в UserData/Provisioning Profiles${CLR_RESET}"
    fi

    if [[ -f "$STATE_FILE" ]]; then
        local last_run
        last_run=$(cat "$STATE_FILE" 2>/dev/null)
        local now
        now=$(date +%s)
        if [[ "$last_run" =~ ^[0-9]+$ ]]; then
            local elapsed=$((now - last_run))
            local days=$((elapsed / 86400))
            local hours=$(((elapsed % 86400) / 3600))
            local last_date
            last_date=$(date -r "$last_run" "+%Y-%m-%d %H:%M:%S")
            echo -e "Последняя установка: ${CLR_CYAN}$last_date${CLR_RESET} ($days дн. $hours ч. назад)"
        else
            echo -e "Последняя установка: ${CLR_YELLOW}Еще не запускалось${CLR_RESET}"
        fi
    else
        echo -e "Последняя установка: ${CLR_YELLOW}Еще не запускалось${CLR_RESET}"
    fi

    echo -e "${CLR_CYAN}------------------------------------------------------${CLR_RESET}"
    echo -e "Файл лога: ${CLR_GRAY}$LOG_FILE${CLR_RESET}"
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "Последние 5 записей лога:"
        tail -n 5 "$LOG_FILE" | sed 's/^/  /'
    fi
    echo -e "${CLR_CYAN}======================================================${CLR_RESET}"
}

extract_profile_entitlements() {
    local prov_path="$1"
    local out_plist="$2"
    rm -f "$out_plist"
    if [[ ! -f "$prov_path" ]]; then
        return 1
    fi
    security cms -D -i "$prov_path" 2>/dev/null | python3 -c '
import sys, plistlib
data = sys.stdin.buffer.read()
if not data:
    sys.exit(1)
plist = plistlib.loads(data)
ents = plist.get("Entitlements", {})
if not isinstance(ents, dict) or not ents:
    sys.exit(1)
with open(sys.argv[1], "wb") as f:
    plistlib.dump(ents, f)
' "$out_plist" 2>/dev/null || return 1
    [[ -s "$out_plist" ]]
}

sign_nested_items() {
    local root_dir="$1"
    local cert_id="$2"
    local exclude_plugins="$3"
    local target=""
    if [[ "$exclude_plugins" -eq 1 ]]; then
        while IFS= read -r -d '' target; do
            if ! codesign --force --sign "$cert_id" "$target" >/dev/null 2>&1; then
                log_msg "❌ Ошибка codesign для $target"
                return 1
            fi
        done < <(find "$root_dir" -path "$root_dir/PlugIns" -prune -o -type f -name "*.dylib" -print0)
        if [[ -d "$root_dir/Frameworks" ]]; then
            while IFS= read -r -d '' target; do
                if ! codesign --force --sign "$cert_id" "$target" >/dev/null 2>&1; then
                    log_msg "❌ Ошибка codesign для framework $target"
                    return 1
                fi
            done < <(find "$root_dir/Frameworks" -type d -name "*.framework" -print0)
        fi
    else
        while IFS= read -r -d '' target; do
            if ! codesign --force --sign "$cert_id" "$target" >/dev/null 2>&1; then
                log_msg "❌ Ошибка codesign для $target"
                return 1
            fi
        done < <(find "$root_dir" -type f -name "*.dylib" -print0)
    fi
    return 0
}

run_autoresign() {
    local force_flag="$1"
    rotate_log_if_needed
    trap cleanup_autoresign EXIT INT TERM
    acquire_lock "$force_flag"

    local now
    now=$(date +%s)

    # 1. Проверяем остаток жизни обоих профилей (app + FormWidget) и тайминг
    local pre_main_prov pre_info pre_rest pre_rem_sec
    pre_main_prov=$(find_newest_profile "com.form.app.form")
    pre_info=$(get_profile_info "$pre_main_prov")
    pre_rest="${pre_info#*|}"
    pre_rem_sec="${pre_rest%%|*}"

    local pre_widget_prov pre_w_info pre_w_rest pre_w_rem_sec
    pre_widget_prov=$(find_newest_profile "com.form.app.form.FormWidget")
    pre_w_info=$(get_profile_info "$pre_widget_prov")
    pre_w_rest="${pre_w_info#*|}"
    pre_w_rem_sec="${pre_w_rest%%|*}"

    if [[ "$force_flag" != "--force" && -f "$STATE_FILE" && $pre_rem_sec -gt 172800 && $pre_w_rem_sec -gt 172800 ]]; then
        local last_run
        last_run=$(cat "$STATE_FILE" 2>/dev/null)
        if [[ "$last_run" =~ ^[0-9]+$ ]]; then
            local elapsed=$((now - last_run))
            if [[ $elapsed -lt $MAX_AGE_SECONDS ]]; then
                # Оба профиля свежие (>48ч) и недавно ставили, тихо выходим
                exit 0
            fi
        fi
    fi

    # 2. Проверяем сопряжение с iPhone (3 попытки для стабилизации Wi-Fi Bonjour)
    local dev_info
    dev_info=$(get_paired_device)
    if [[ -z "$dev_info" ]]; then
        if [[ -f "$STATE_FILE" ]]; then
            local last_run
            last_run=$(cat "$STATE_FILE" 2>/dev/null)
            if [[ "$last_run" =~ ^[0-9]+$ ]]; then
                local elapsed=$((now - last_run))
                if [[ $elapsed -ge $((4 * 86400)) ]]; then
                    local days_ago=$((elapsed / 86400))
                    log_msg "⚠️ Внимание: Сертификат не обновлялся уже $days_ago дн., а iPhone не обнаружен по Wi-Fi/USB."
                    local last_alert=0
                    [[ -f "$ALERT_FILE" ]] && last_alert=$(cat "$ALERT_FILE" 2>/dev/null)
                    [[ ! "$last_alert" =~ ^[0-9]+$ ]] && last_alert=0
                    if [[ $((now - last_alert)) -ge 86400 ]]; then
                        echo "$now" > "$ALERT_FILE"
                        notify_mac "FORM // ВНИМАНИЕ" "Сертификат form не обновлялся $days_ago дн.! Подключи iPhone к одной Wi-Fi сети с Mac или по USB."
                    fi
                fi
            fi
        fi

        if [[ "$force_flag" == "--force" ]]; then
            log_msg "${CLR_RED}❌ Ошибка: iPhone не найден в сети Wi-Fi или по USB.${CLR_RESET}"
            echo "Убедись, что iPhone и Mac в одной Wi-Fi сети и в Xcode горит сопряжение."
            exit 1
        fi
        exit 0
    fi

    local dev_id="${dev_info%%|*}"
    local dev_name="${dev_info##*|}"

    log_msg "🔄 Запуск автообновления form для $dev_name [$dev_id]..."

    # Проверка расхождения web-ядра index.html <-> form/index.html перед компиляцией
    if ! diff -q "$PROJECT_DIR/index.html" "$PROJECT_DIR/form/index.html" >/dev/null 2>&1; then
        log_msg "⚠️ Расхождение index.html и form/index.html — синхронизируем index.html -> form/index.html перед сборкой"
        cp -f "$PROJECT_DIR/index.html" "$PROJECT_DIR/form/index.html"
    fi

    # 3. Проверяем остаток жизни текущего профиля form.app и виджета
    local main_prov
    main_prov=$(find_newest_profile "com.form.app.form")
    local widget_user_prov
    widget_user_prov=$(find_newest_profile "com.form.app.form.FormWidget")

    local prof_info
    prof_info=$(get_profile_info "$main_prov")
    local exp_ts="${prof_info%%|*}"
    local rest="${prof_info#*|}"
    local rem_sec="${rest%%|*}"
    local exp_str="${rest#*|}"
    local rem_hours=$((rem_sec / 3600))
    local rem_days=$((rem_sec / 86400))
    local rem_hours_mod=$(((rem_sec % 86400) / 3600))

    local w_pre_info
    w_pre_info=$(get_profile_info "$widget_user_prov")
    local w_pre_rest="${w_pre_info#*|}"
    local w_pre_rem_sec="${w_pre_rest%%|*}"

    # Запрашиваем обновление у Apple через -allowProvisioningUpdates при <= 48 часов до конца профиля.
    local prov_flag=""
    local moved_provs=0
    if [[ -z "$main_prov" || $rem_sec -le 172800 || -z "$widget_user_prov" || $w_pre_rem_sec -le 172800 ]]; then
        prov_flag="-allowProvisioningUpdates"
        log_msg "⏰ До истечения одного из профилей Apple <= 48ч (app: $rem_hours ч., widget: $((w_pre_rem_sec / 3600)) ч.). Запрашиваем свежий 7-дневный профиль..."
        mkdir -p "$PROV_BACKUP_DIR"
        if [[ -n "$main_prov" && -f "$main_prov" && $rem_sec -le 172800 ]]; then
            MOVED_MAIN_PROV_NAME="$(basename "$main_prov")"
            mv -f "$main_prov" "$PROV_BACKUP_DIR/$MOVED_MAIN_PROV_NAME"
            moved_provs=1
        fi
        if [[ -n "$widget_user_prov" && -f "$widget_user_prov" && $w_pre_rem_sec -le 172800 ]]; then
            MOVED_WIDGET_PROV_NAME="$(basename "$widget_user_prov")"
            mv -f "$widget_user_prov" "$PROV_BACKUP_DIR/$MOVED_WIDGET_PROV_NAME"
            moved_provs=1
        fi
    else
        log_msg "🛡️ Профиль Apple в норме (до $exp_str, осталось $rem_days дн. $rem_hours_mod ч.). Сборка без запроса к Apple."
    fi

    # 4. Собираем проект
    local build_log="/tmp/form_xcodebuild.log"
    local build_ok=1
    if ! xcodebuild -project "$PROJECT_FILE" \
         -scheme "$SCHEME" \
         -destination "id=$dev_id" \
         $prov_flag \
         build > "$build_log" 2>&1; then
        build_ok=0
        log_msg "⚠️ xcodebuild завершился с кодом ошибки. Проверяем профили..."
    fi

    # Проверяем, выдал ли Apple свежий профиль; если нет (оффлайн / разлогин Xcode) — откатываем backup
    if [[ $moved_provs -eq 1 ]]; then
        local prof_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
        local post_main_prov post_info post_rem_sec
        post_main_prov=$(find_newest_profile "com.form.app.form")
        post_info=$(get_profile_info "$post_main_prov")
        post_rem_sec="${post_info#*|}"
        post_rem_sec="${post_rem_sec%%|*}"

        local post_widget_prov post_w_info post_w_rem_sec
        post_widget_prov=$(find_newest_profile "com.form.app.form.FormWidget")
        post_w_info=$(get_profile_info "$post_widget_prov")
        post_w_rem_sec="${post_w_info#*|}"
        post_w_rem_sec="${post_w_rem_sec%%|*}"

        local restored_any=0
        if [[ -n "$MOVED_MAIN_PROV_NAME" && -f "$PROV_BACKUP_DIR/$MOVED_MAIN_PROV_NAME" ]] && [[ -z "$post_main_prov" || $post_rem_sec -le 0 ]]; then
            log_msg "⚠️ Apple не выдал новый профиль приложения. Восстанавливаем резервную копию $MOVED_MAIN_PROV_NAME..."
            cp -f "$PROV_BACKUP_DIR/$MOVED_MAIN_PROV_NAME" "$prof_dir/" 2>/dev/null || true
            restored_any=1
        fi
        if [[ -n "$MOVED_WIDGET_PROV_NAME" && -f "$PROV_BACKUP_DIR/$MOVED_WIDGET_PROV_NAME" ]] && [[ -z "$post_widget_prov" || $post_w_rem_sec -le 0 ]]; then
            log_msg "⚠️ Apple не выдал новый профиль виджета. Восстанавливаем резервную копию $MOVED_WIDGET_PROV_NAME..."
            cp -f "$PROV_BACKUP_DIR/$MOVED_WIDGET_PROV_NAME" "$prof_dir/" 2>/dev/null || true
            restored_any=1
        fi
        if [[ $restored_any -eq 0 ]]; then
            log_msg "✨ Apple выдал свежий 7-дневный профиль!"
        fi
        MOVED_MAIN_PROV_NAME=""
        MOVED_WIDGET_PROV_NAME=""
        rm -rf "$PROV_BACKUP_DIR" 2>/dev/null || true
    fi

    # Строгий запрет на установку старого .app при ошибке xcodebuild
    if [[ $build_ok -eq 0 ]]; then
        log_msg "❌ Ошибка сборки xcodebuild (см. $build_log). Установка прервана, старый бандл не используется."
        tail -n 15 "$build_log" 2>/dev/null | sed 's/^/  /'
        exit 1
    fi

    # 5. Находим путь к собранному form.app динамически
    local app_dir
    app_dir=$(xcodebuild -project "$PROJECT_FILE" -scheme "$SCHEME" -destination "id=$dev_id" -showBuildSettings 2>/dev/null | sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p' | head -n 1)
    if [[ -z "$app_dir" ]]; then
        app_dir=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData"/form-*/Build/Products/Debug-iphoneos 2>/dev/null | head -n 1)
    fi
    if [[ -z "$app_dir" ]]; then
        log_msg "❌ Ошибка: Не удалось определить TARGET_BUILD_DIR или путь в DerivedData."
        exit 1
    fi
    local app_path="$app_dir/form.app"
    ACTIVE_APP_PATH="$app_path"

    if [[ ! -d "$app_path" ]]; then
        log_msg "❌ Ошибка: Не найден собранный бандл $app_path"
        exit 1
    fi

    # Всегда синхронизируем свежий index.html в бандл
    cp -f "$PROJECT_DIR/index.html" "$app_path/index.html"

    # Определяем сертификат подписи динамически
    local cert_id
    cert_id=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)
    [[ -z "$cert_id" ]] && cert_id="Apple Development: paradoxicalie@gmail.com (2X34LYF2JH)"

    # Управление виджетом: если профиль виджета активен — строго подписываем, иначе временно прячем PlugIns с откатом через trap
    local widget_appex="$app_path/PlugIns/FormWidgetExtension.appex"
    if [[ -d "$widget_appex" ]]; then
        local widget_prov="$widget_appex/embedded.mobileprovision"
        local user_widget_prov
        user_widget_prov=$(find_newest_profile "com.form.app.form.FormWidget")
        if [[ -n "$user_widget_prov" && -f "$user_widget_prov" ]]; then
            cp -f "$user_widget_prov" "$widget_prov"
        fi

        local widget_info
        widget_info=$(get_profile_info "$widget_prov")
        local w_rem_sec="${widget_info#*|}"
        w_rem_sec="${w_rem_sec%%|*}"

        if [[ $w_rem_sec -gt 0 ]]; then
            log_msg "📱 Профиль FormWidgetExtension активен. Подписываем виджет..."
            if ! extract_profile_entitlements "$widget_prov" "$WIDGET_ENT_FILE"; then
                log_msg "❌ Ошибка извлечения entitlements виджета FormWidgetExtension"
                exit 1
            fi
            if ! sign_nested_items "$widget_appex" "$cert_id" 0; then
                exit 1
            fi
            if ! codesign --force --sign "$cert_id" --entitlements "$WIDGET_ENT_FILE" "$widget_appex" >/dev/null 2>&1; then
                log_msg "❌ Ошибка подписи FormWidgetExtension.appex"
                exit 1
            fi
        else
            log_msg "⚠️ Профиль FormWidgetExtension истек или отсутствует. Временно переносим PlugIns в backup (откат через trap)."
            mkdir -p "$PLUGINS_BACKUP_DIR"
            mv -f "$app_path/PlugIns" "$PLUGINS_BACKUP_DIR/PlugIns"
        fi
    fi

    # Гарантируем наличие самого свежего активного provisioning profile для form.app
    local latest_main_prov
    latest_main_prov=$(find_newest_profile "com.form.app.form")
    if [[ -n "$latest_main_prov" && -f "$latest_main_prov" ]]; then
        cp -f "$latest_main_prov" "$app_path/embedded.mobileprovision"
    fi

    # Проверяем итоговый срок действия профиля перед установкой на устройство
    local final_info
    final_info=$(get_profile_info "$app_path/embedded.mobileprovision")
    local final_exp_ts="${final_info%%|*}"
    local final_rest="${final_info#*|}"
    local final_rem_sec="${final_rest%%|*}"
    local final_exp_str="${final_rest#*|}"
    local final_days=$((final_rem_sec / 86400))
    local final_hours=$(((final_rem_sec % 86400) / 3600))

    if [[ $final_rem_sec -le 0 ]]; then
        log_msg "❌ Ошибка: Устанавливаемый профиль истек ($final_exp_str). Откройте Xcode -> Settings -> Accounts!"
        notify_mac "FORM // ВНИМАНИЕ" "Профиль приложения истек! Войдите в Apple ID в Xcode."
        exit 1
    fi

    # Извлекаем полные entitlements из активного профиля form.app и строго переподписываем
    if [[ -f "$app_path/embedded.mobileprovision" ]]; then
        if ! extract_profile_entitlements "$app_path/embedded.mobileprovision" "$MAIN_ENT_FILE"; then
            log_msg "❌ Ошибка извлечения entitlements из embedded.mobileprovision"
            exit 1
        fi
        if ! sign_nested_items "$app_path" "$cert_id" 1; then
            exit 1
        fi
        if ! codesign --force --sign "$cert_id" --entitlements "$MAIN_ENT_FILE" "$app_path" >/dev/null 2>&1; then
            log_msg "❌ Ошибка подписи бандла $app_path"
            exit 1
        fi
    fi

    # Строгая финальная проверка подписи всего бандла перед установкой на iPhone
    if ! codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
        log_msg "❌ Ошибка проверки подписи codesign --verify --deep --strict для $app_path"
        exit 1
    fi

    # 6. Устанавливаем обновленный бандл на iPhone через devicectl
    local install_log="/tmp/form_devicectl.log"
    if ! xcrun devicectl device install app --device "$dev_id" "$app_path" > "$install_log" 2>&1; then
        log_msg "❌ Ошибка установки devicectl на $dev_name. Подробности в $install_log"
        tail -n 10 "$install_log" 2>/dev/null | sed 's/^/  /'
        exit 1
    fi

    # 7. Фиксируем успех
    echo "$now" > "$STATE_FILE"
    rm -f "$ALERT_FILE" 2>/dev/null || true
    log_msg "✅ УСПЕХ: form обновлен и установлен на $dev_name! Профиль Apple активен до $final_exp_str (осталось $final_days дн. $final_hours ч.)."
    notify_mac "FORM // SYSTEM" "Приложение form обновлено на $dev_name (профиль активен до $final_exp_str)."
}

# Обработка аргументов командной строки
case "$1" in
    --status|-s)
        show_status
        ;;
    --force|-f)
        run_autoresign "--force"
        ;;
    *)
        run_autoresign
        ;;
esac
