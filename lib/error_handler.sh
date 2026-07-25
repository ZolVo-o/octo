#!/bin/bash

# Модуль обработки ошибок OCTO

ERROR_RED='\033[31m'
ERROR_YELLOW='\033[33m'
ERROR_BLUE='\033[36m'
ERROR_GREEN='\033[32m'
ERROR_RESET='\033[0m'

show_error() {
    local code="$1"
    local message="$2"
    local suggestion="$3"
    
    echo -e "\n${ERROR_RED}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                      ❌ ОШИБКА                            ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${ERROR_RESET}"
    
    echo -e "${ERROR_RED}📋 Код ошибки: ${ERROR_RESET}$code"
    echo -e "${ERROR_RED}📝 Описание: ${ERROR_RESET}$message"
    
    if [ -n "$suggestion" ]; then
        echo -e "\n${ERROR_YELLOW}💡 Решение:${ERROR_RESET}"
        echo -e "  $suggestion"
    fi
    
    mkdir -p "$OCTO_ROOT/logs"
    echo "$(date): ERROR[$code] $message" >> "$OCTO_ROOT/logs/errors.log"
}

show_warning() {
    local message="$1"
    local suggestion="$2"
    
    echo -e "\n${ERROR_YELLOW}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                      ⚠️  ПРЕДУПРЕЖДЕНИЕ                  ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${ERROR_RESET}"
    
    echo -e "${ERROR_YELLOW}⚠️  $message${ERROR_RESET}"
    
    if [ -n "$suggestion" ]; then
        echo -e "\n${ERROR_BLUE}💡 Рекомендация:${ERROR_RESET}"
        echo -e "  $suggestion"
    fi
}

show_success() {
    local message="$1"
    
    echo -e "\n${ERROR_GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                      ✅ УСПЕХ                            ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${ERROR_RESET}"
    
    echo -e "${ERROR_GREEN}✅ $message${ERROR_RESET}"
}

show_info() {
    local message="$1"
    
    echo -e "${ERROR_BLUE}ℹ️  $message${ERROR_RESET}"
}

check_dependencies() {
    local deps=("$@")
    local missing=()
    
    echo -e "\n${ERROR_BLUE}🔍 Проверка зависимостей...${ERROR_RESET}"
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &>/dev/null; then
            echo -e "  ${ERROR_GREEN}✅ $dep${ERROR_RESET}"
        else
            echo -e "  ${ERROR_RED}❌ $dep${ERROR_RESET}"
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        show_error "DEP-001" "Отсутствуют зависимости: ${missing[*]}" \
            "Установите: sudo pacman -S ${missing[*]}"
        return 1
    fi
    
    return 0
}

handle_network_error() {
    local url="$1"
    
    show_error "NET-001" "Не удалось подключиться к $url" \
        "1. Проверьте интернет-соединение\n  2. Попробуйте позже\n  3. Используйте зеркало\n  4. Проверьте DNS: ping -c 3 aur.archlinux.org"
    
    echo -e "\n${ERROR_YELLOW}🔧 Диагностика:${ERROR_RESET}"
    echo -e "  ping -c 3 $(echo "$url" | cut -d/ -f3)"
    echo -e "  curl -I $url"
    echo -e "  Проверьте /etc/resolv.conf"
}

check_internet() {
    # Проверяем через curl (более надёжно)
    if curl -s --max-time 3 -I https://aur.archlinux.org > /dev/null 2>&1; then
        return 0
    fi
    
    # Пробуем через ping на aur
    if ping -c 1 -W 2 aur.archlinux.org > /dev/null 2>&1; then
        return 0
    fi
    
    # Пробуем через ping на 8.8.8.8
    if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        return 0
    fi
    
    # Пробуем через 1.1.1.1 (Cloudflare)
    if ping -c 1 -W 2 1.1.1.1 > /dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

trap_error() {
    local line="$1"
    local command="$2"
    local code="$3"
    
    show_error "EXEC-001" "Ошибка в строке $line: $command (код: $code)" \
        "1. Проверьте синтаксис команды\n  2. Убедитесь в наличии прав\n  3. Попробуйте запустить с sudo"
}

safe_exec() {
    local cmd="$1"
    local error_msg="$2"
    
    echo -e "${ERROR_BLUE}▶️  Выполнение: $cmd${ERROR_RESET}"
    
    if eval "$cmd" 2>/tmp/octo_error_$$; then
        rm -f /tmp/octo_error_$$ 2>/dev/null
        return 0
    else
        local error_output=$(cat /tmp/octo_error_$$ 2>/dev/null)
        show_error "EXEC-002" "Ошибка выполнения: $error_msg" \
            "Команда: $cmd\nОшибка: $error_output"
        rm -f /tmp/octo_error_$$ 2>/dev/null
        return 1
    fi
}
