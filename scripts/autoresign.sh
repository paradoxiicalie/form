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

# Цвета для красивого вывода в терминал
CLR_RESET="\033[0m"
CLR_RED="\033[1;31m"
CLR_GREEN="\033[1;32m"
CLR_YELLOW="\033[1;33m"
CLR_CYAN="\033[1;36m"
CLR_GRAY="\033[0;90m"

log_msg() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] $1"
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

notify_mac() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || true
}

get_paired_device() {
    # Ищем подключенный по проводу или Wi-Fi («планета» в Xcode) iPhone с 3 попытками
    local attempts=3
    for ((i=1; i<=attempts; i++)); do
        local line
        line=$(xcrun devicectl list devices 2>/dev/null | grep -i "available (paired)" | grep -i "iPhone" | head -n 1)
        if [[ -n "$line" ]]; then
            local dev_id
            dev_id=$(echo "$line" | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | head -n 1)
            local dev_name
            dev_name=$(echo "$line" | awk -F'   ' '{print $1}' | xargs)
            echo "$dev_id|$dev_name"
            return 0
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

    # Ищем самый свежий профиль form.app
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

    if [[ -f "$STATE_FILE" ]]; then
        local last_run
        last_run=$(cat "$STATE_FILE" 2>/dev/null)
        local now
        now=$(date +%s)
        local elapsed=$((now - last_run))
        local days=$((elapsed / 86400))
        local hours=$(((elapsed % 86400) / 3600))

        local last_date
        last_date=$(date -r "$last_run" "+%Y-%m-%d %H:%M:%S")

        echo -e "Последняя установка: ${CLR_CYAN}$last_date${CLR_RESET} ($days дн. $hours ч. назад)"
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

run_autoresign() {
    local force_flag="$1"
    local now
    now=$(date +%s)

    # 1. Проверяем остаток жизни профиля и тайминг (продлеваем досрочно при <= 48ч, даже если --force был недавно)
    local pre_main_prov
    pre_main_prov=$(find_newest_profile "com.form.app.form")
    local pre_info
    pre_info=$(get_profile_info "$pre_main_prov")
    local pre_rest="${pre_info#*|}"
    local pre_rem_sec="${pre_rest%%|*}"

    if [[ "$force_flag" != "--force" && -f "$STATE_FILE" && $pre_rem_sec -gt 172800 ]]; then
        local last_run
        last_run=$(cat "$STATE_FILE" 2>/dev/null)
        local elapsed=$((now - last_run))
        if [[ $elapsed -lt $MAX_AGE_SECONDS ]]; then
            # Профиль свежий (>48ч) и недавно ставили, тихо выходим
            exit 0
        fi
    fi

    # 2. Проверяем сопряжение с iPhone (3 попытки для стабилизации Wi-Fi Bonjour)
    local dev_info
    dev_info=$(get_paired_device)
    if [[ -z "$dev_info" ]]; then
        if [[ -f "$STATE_FILE" ]]; then
            local last_run
            last_run=$(cat "$STATE_FILE" 2>/dev/null)
            local elapsed=$((now - last_run))
            if [[ $elapsed -ge $((4 * 86400)) ]]; then
                local days_ago=$((elapsed / 86400))
                log_msg "⚠️ Внимание: Сертификат не обновлялся уже $days_ago дн., а iPhone не обнаружен по Wi-Fi/USB."
                local last_alert=0
                [[ -f "$ALERT_FILE" ]] && last_alert=$(cat "$ALERT_FILE" 2>/dev/null)
                if [[ $((now - last_alert)) -ge 86400 ]]; then
                    echo "$now" > "$ALERT_FILE"
                    notify_mac "FORM // ВНИМАНИЕ" "Сертификат form не обновлялся $days_ago дн.! Подключи iPhone к одной Wi-Fi сети с Mac или по USB."
                fi
            fi
        fi

        if [[ "$force_flag" == "--force" ]]; then
            log_msg "${CLR_RED}❌ Ошибка: iPhone не найден в сети Wi-Fi или по USB.${CLR_RESET}"
            echo "Убедись, что iPhone и Mac в одной Wi-Fi сети и в Xcode горит сопряжение."
        fi
        exit 0
    fi

    local dev_id="${dev_info%%|*}"
    local dev_name="${dev_info##*|}"

    log_msg "🔄 Запуск автообновления form для $dev_name [$dev_id]..."

    # Синхронизация web-ядра index.html -> form/index.html перед компиляцией
    if ! cmp -s "$PROJECT_DIR/index.html" "$PROJECT_DIR/form/index.html"; then
        log_msg "Синхронизация web-ядра: index.html -> form/index.html"
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
    # ВАЖНО: xcodebuild НЕ обновляет еще не истекший профиль, пока он лежит в Provisioning Profiles!
    # Поэтому временно убираем истекающий профиль в backup, чтобы Xcode реально запросил свежий 7-дневный у Apple.
    local prov_flag=""
    local prov_backup_dir="/tmp/form_prov_backup_$$"
    local moved_provs=0
    if [[ -z "$main_prov" || $rem_sec -le 172800 || -z "$widget_user_prov" || $w_pre_rem_sec -le 172800 ]]; then
        prov_flag="-allowProvisioningUpdates"
        log_msg "⏰ До истечения профиля Apple осталось $rem_hours ч. (<= 48ч). Запрашиваем свежий 7-дневный профиль у Apple..."
        mkdir -p "$prov_backup_dir"
        if [[ -n "$main_prov" && -f "$main_prov" && $rem_sec -le 172800 ]]; then
            mv -f "$main_prov" "$prov_backup_dir/"
            moved_provs=1
        fi
        if [[ -n "$widget_user_prov" && -f "$widget_user_prov" && $w_pre_rem_sec -le 172800 ]]; then
            mv -f "$widget_user_prov" "$prov_backup_dir/"
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
        log_msg "⚠️ xcodebuild завершился с кодом ошибки. Проверяем профили и fallback..."
    fi

    # Проверяем, выдал ли Apple свежий профиль; если нет (оффлайн / разлогин Xcode) — откатываем backup
    local post_main_prov
    post_main_prov=$(find_newest_profile "com.form.app.form")
    local post_info
    post_info=$(get_profile_info "$post_main_prov")
    local post_rem_sec="${post_info#*|}"
    post_rem_sec="${post_rem_sec%%|*}"

    if [[ $moved_provs -eq 1 ]]; then
        if [[ -z "$post_main_prov" || $post_rem_sec -le 0 ]]; then
            log_msg "⚠️ Apple не выдал новый профиль (проверь интернет или сессию в Xcode -> Settings -> Accounts). Восстанавливаем резервную копию..."
            cp -f "$prov_backup_dir"/*.mobileprovision "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/" 2>/dev/null || true
        else
            log_msg "✨ Apple выдал свежий 7-дневный профиль!"
        fi
        rm -rf "$prov_backup_dir" 2>/dev/null || true
    fi

    # 5. Находим путь к собранному form.app
    local app_dir
    app_dir=$(xcodebuild -project "$PROJECT_FILE" -scheme "$SCHEME" -destination "id=$dev_id" -showBuildSettings 2>/dev/null | grep -m 1 "TARGET_BUILD_DIR =" | awk '{print $3}')
    [[ -z "$app_dir" ]] && app_dir="/Users/alexeytikunov/Library/Developer/Xcode/DerivedData/form-fpxkpcjqfxaqpcahuyayortcbknp/Build/Products/Debug-iphoneos"
    local app_path="$app_dir/form.app"

    if [[ ! -d "$app_path" ]]; then
        log_msg "❌ Ошибка: Не найден собранный бандл $app_path"
        exit 1
    fi

    # Всегда синхронизируем свежий index.html в бандл
    cp -f "$PROJECT_DIR/index.html" "$app_path/index.html"

    # Управление виджетом: если профиль виджета активен — подписываем и оставляем его, иначе временно отключаем PlugIns, чтобы devicectl не блокировал приложение
    local cert_id="Apple Development: paradoxicalie@gmail.com (2X34LYF2JH)"
    local widget_appex="$app_path/PlugIns/FormWidgetExtension.appex"
    if [[ -d "$widget_appex" ]]; then
        local widget_prov="$widget_appex/embedded.mobileprovision"
        # Подкладываем самый свежий профиль виджета из Xcode, если он новее встроенного
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
            local widget_ent="/tmp/form_widget_entitlements_extracted.plist"
            security cms -D -i "$widget_prov" 2>/dev/null | python3 -c "
import sys, plistlib
data = sys.stdin.buffer.read()
if data:
    plist = plistlib.loads(data)
    ents = plist.get('Entitlements', {})
    with open('$widget_ent', 'wb') as f:
        plistlib.dump(ents, f)
" 2>/dev/null || true
            if [[ -f "$widget_ent" ]]; then
                find "$widget_appex" -type f -name "*.dylib" -exec codesign --force --sign "$cert_id" {} + 2>/dev/null || true
                codesign --force --sign "$cert_id" --entitlements "$widget_ent" "$widget_appex" >/dev/null 2>&1 || true
            fi
        else
            log_msg "⚠️ Профиль FormWidgetExtension истек или отсутствует. Чтобы виджет заработал на экране iPhone, войдите в Apple ID в Xcode (Настройки -> Accounts)."
            rm -rf "$app_path/PlugIns"
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

    # Извлекаем полные entitlements из активного профиля form.app и переподписываем
    if [[ -f "$app_path/embedded.mobileprovision" ]]; then
        local ent_file="/tmp/form_entitlements_extracted.plist"
        security cms -D -i "$app_path/embedded.mobileprovision" 2>/dev/null | python3 -c "
import sys, plistlib
data = sys.stdin.buffer.read()
if data:
    plist = plistlib.loads(data)
    ents = plist.get('Entitlements', {})
    with open('$ent_file', 'wb') as f:
        plistlib.dump(ents, f)
" 2>/dev/null || true

        if [[ -f "$ent_file" ]]; then
            find "$app_path" -type f -name "*.dylib" -exec codesign --force --sign "$cert_id" {} + 2>/dev/null || true
            find "$app_path/Frameworks" -type d -name "*.framework" -exec codesign --force --sign "$cert_id" {} + 2>/dev/null || true
            codesign --force --sign "$cert_id" --entitlements "$ent_file" "$app_path" >/dev/null 2>&1 || true
        fi
    fi

    # 6. Устанавливаем обновленный бандл на iPhone через devicectl
    local install_log="/tmp/form_devicectl.log"
    if ! xcrun devicectl device install app --device "$dev_id" "$app_path" > "$install_log" 2>&1; then
        log_msg "❌ Ошибка установки devicectl на $dev_name. Подробности в $install_log"
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
