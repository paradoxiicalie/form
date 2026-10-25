#!/bin/bash
# ==============================================================================
# FORM // SYSTEM — AUTO-RESIGN & KEEP-ALIVE DAEMON FOR iOS (7-DAY BYPASS)
# ==============================================================================
# Автоматически пересобирает, продлевает бесплатный 7-дневный профиль Apple
# и устанавливает приложение form на твой iPhone по воздуху (Wi-Fi) или USB.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/autoresign.log"
STATE_FILE="$SCRIPT_DIR/last_resign.txt"
PROJECT_FILE="$PROJECT_DIR/form.xcodeproj"
SCHEME="form"
MAX_AGE_DAYS=4 # Продлеваем каждые 4 дня (запас 3 дня до истечения 7-дневного лимита)
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
    # Ищем подключенный по проводу или Wi-Fi («планета» в Xcode) iPhone
    local line
    line=$(xcrun devicectl list devices 2>/dev/null | grep -i "available (paired)" | grep -i "iPhone" | head -n 1)
    if [[ -n "$line" ]]; then
        # Извлекаем UUID устройства
        local dev_id
        dev_id=$(echo "$line" | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | head -n 1)
        # Извлекаем имя устройства
        local dev_name
        dev_name=$(echo "$line" | awk -F'   ' '{print $1}' | xargs)
        echo "$dev_id|$dev_name"
    fi
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

    if [[ -f "$STATE_FILE" ]]; then
        local last_run
        last_run=$(cat "$STATE_FILE" 2>/dev/null)
        local now
        now=$(date +%s)
        local elapsed=$((now - last_run))
        local days=$((elapsed / 86400))
        local hours=$(((elapsed % 86400) / 3600))
        local remaining_days=$((7 - days))

        local last_date
        last_date=$(date -r "$last_run" "+%Y-%m-%d %H:%M:%S")

        echo -e "Последнее обновление: ${CLR_CYAN}$last_date${CLR_RESET} ($days дн. $hours ч. назад)"
        if [[ $remaining_days -gt 0 ]]; then
            echo -e "До истечения 7 дней: ${CLR_GREEN}осталось ~$remaining_days дн.${CLR_RESET}"
        else
            echo -e "До истечения 7 дней: ${CLR_RED}Сертификат мог истечь! Требуется запуск.${CLR_RESET}"
        fi

        if [[ $elapsed -ge $MAX_AGE_SECONDS ]]; then
            echo -e "План автообновления: ${CLR_YELLOW}ПОРА ОБНОВЛЯТЬ (прошло >= $MAX_AGE_DAYS дней)${CLR_RESET}"
        else
            local next_update=$(((MAX_AGE_SECONDS - elapsed) / 86400))
            echo -e "План автообновления: ${CLR_GREEN}В норме (плановое обновление через $next_update дн.)${CLR_RESET}"
        fi
    else
        echo -e "Последнее обновление: ${CLR_YELLOW}Еще не запускалось${CLR_RESET}"
    fi

    echo -e "${CLR_CYAN}------------------------------------------------------${CLR_RESET}"
    echo -e "Файл лога: ${CLR_GRAY}$LOG_FILE${CLR_RESET}"
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "Последние 3 записи лога:"
        tail -n 3 "$LOG_FILE" | sed 's/^/  /'
    fi
    echo -e "${CLR_CYAN}======================================================${CLR_RESET}"
}

run_autoresign() {
    local force_flag="$1"
    local now
    now=$(date +%s)

    # 1. Проверяем тайминг (нужно ли обновлять прямо сейчас)
    if [[ "$force_flag" != "--force" && -f "$STATE_FILE" ]]; then
        local last_run
        last_run=$(cat "$STATE_FILE" 2>/dev/null)
        local elapsed=$((now - last_run))
        if [[ $elapsed -lt $MAX_AGE_SECONDS ]]; then
            local days_left=$(((MAX_AGE_SECONDS - elapsed) / 86400))
            # Еще рано обновлять, тихо выходим
            exit 0
        fi
    fi

    # 2. Проверяем сопряжение с iPhone
    local dev_info
    dev_info=$(get_paired_device)
    if [[ -z "$dev_info" ]]; then
        if [[ "$force_flag" == "--force" ]]; then
            log_msg "${CLR_RED}❌ Ошибка: iPhone не найден в сети Wi-Fi или по USB.${CLR_RESET}"
            echo "Убедись, что iPhone и Mac в одной Wi-Fi сети и в Xcode горит сопряжение."
        fi
        exit 0
    fi

    local dev_id="${dev_info%%|*}"
    local dev_name="${dev_info##*|}"

    log_msg "🔄 Запуск автообновления form для $dev_name [$dev_id]..."

    # 3. Собираем проект с обновлением профилей (-allowProvisioningUpdates)
    local build_log="/tmp/form_xcodebuild.log"
    if ! xcodebuild -project "$PROJECT_FILE" \
         -scheme "$SCHEME" \
         -destination "id=$dev_id" \
         -allowProvisioningUpdates \
         build > "$build_log" 2>&1; then
        log_msg "❌ Ошибка xcodebuild. Подробности в $build_log"
        exit 1
    fi

    # 4. Находим путь к собранному form.app
    local app_dir
    app_dir=$(xcodebuild -project "$PROJECT_FILE" -scheme "$SCHEME" -destination "id=$dev_id" -showBuildSettings 2>/dev/null | grep -m 1 "TARGET_BUILD_DIR =" | awk '{print $3}')
    local app_path="$app_dir/form.app"

    if [[ ! -d "$app_path" ]]; then
        log_msg "❌ Ошибка: Не найден собранный бандл $app_path"
        exit 1
    fi

    # 5. Устанавливаем обновленный бандл на iPhone через devicectl
    local install_log="/tmp/form_devicectl.log"
    if ! xcrun devicectl device install app --device "$dev_id" "$app_path" > "$install_log" 2>&1; then
        log_msg "❌ Ошибка установки devicectl на $dev_name. Подробности в $install_log"
        exit 1
    fi

    # 6. Фиксируем успех
    echo "$now" > "$STATE_FILE"
    log_msg "✅ УСПЕХ: form переподписан и обновлен на $dev_name! 7-дневный сертификат продлен."
    notify_mac "FORM // SYSTEM" "Сертификат form продлен еще на 7 дней! Приложение обновлено на $dev_name."
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
