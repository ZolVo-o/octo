#!/bin/bash

# Модуль UI - Красивые прогресс-бары и анимации для OCTO

# Цвета для UI
UI_RESET='\033[0m'
UI_RED='\033[31m'
UI_GREEN='\033[32m'
UI_YELLOW='\033[33m'
UI_BLUE='\033[36m'
UI_MAGENTA='\033[35m'
UI_WHITE='\033[37m'
UI_BOLD='\033[1m'
UI_DIM='\033[2m'

# Палитра OCTO 4.0: тёмный терминальный фон, cyan-контуры и цветовые акценты.
UI_CYAN='\033[38;5;51m'
UI_NAVY='\033[38;5;24m'
UI_ORANGE='\033[38;5;214m'
UI_PINK='\033[38;5;204m'
UI_GRAY='\033[38;5;245m'
UI_CLEAR='\033[2J\033[H'

ui_term_width() {
    local width
    width=$(tput cols 2>/dev/null || printf '160')
    ((width < 120)) && width=120
    printf '%s' "$width"
}

ui_repeat() {
    local char="$1"
    local count="$2"
    local out=""
    local i
    for ((i=0; i<count; i++)); do
        out+="$char"
    done
    printf '%s' "$out"
}

ui_pad() {
    local text="$1"
    local width="$2"
    local len=${#text}
    printf '%s' "$text"
    if ((len < width)); then
        printf '%*s' "$((width - len))" ''
    fi
}

ui_center() {
    local text="$1"
    local width="$2"
    local len=${#text}
    local left=$(((width - len) / 2))
    ((left < 0)) && left=0
    printf '%*s%s' "$left" '' "$text"
    if ((left + len < width)); then
        printf '%*s' "$((width - left - len))" ''
    fi
}

ui_box_line() {
    local text="$1"
    local width="${2:-78}"
    local color="${3:-$UI_CYAN}"
    printf '%b│%b %b %b│%b\n' "$color" "$UI_RESET" "$(ui_pad "$text" "$((width - 4))")" "$color" "$UI_RESET"
}

ui_box_top() {
    local width="${1:-78}"
    local color="${2:-$UI_CYAN}"
    printf '%b╭%s╮%b\n' "$color" "$(ui_repeat '─' "$((width - 2))")" "$UI_RESET"
}

ui_box_bottom() {
    local width="${1:-78}"
    local color="${2:-$UI_CYAN}"
    printf '%b╰%s╯%b\n' "$color" "$(ui_repeat '─' "$((width - 2))")" "$UI_RESET"
}

ui_box_sep() {
    local width="${1:-78}"
    local color="${2:-$UI_CYAN}"
    printf '%b├%s┤%b\n' "$color" "$(ui_repeat '─' "$((width - 2))")" "$UI_RESET"
}

# Общая шапка для всех экранов интерактивного режима.
octo_screen_header() {
    local title="${1:-OCTO 4.0}"
    local subtitle="${2:-Твой осьминог в мире Arch Linux}"
    local width=158

    printf '%b' "$UI_CLEAR"
    printf '%b\n' "${UI_NAVY}$(ui_repeat '▒' "$width")${UI_RESET}"
    ui_box_top "$width" "$UI_CYAN"
    ui_box_line "${UI_DIM}🐙 ARCH_OCTO_CORE${UI_RESET} ${UI_CYAN}│${UI_RESET} CPU: ${UI_GREEN}14%%${UI_RESET} ${UI_CYAN}│${UI_RESET} RAM: ${UI_ORANGE}1420MB / 16384MB${UI_RESET}                                                                                 ${UI_BLUE}[ 🌊 Ocean Blue ] [ 🔊 ЗВУК ON ] [ CRT: ON ] [ >_ CLI SHELL ]${UI_RESET}" "$width" "$UI_CYAN"
    ui_box_sep "$width" "$UI_CYAN"
    ui_box_line "" "$width" "$UI_CYAN"
    ui_box_line "$(ui_center "${UI_PINK}🐙${UI_RESET} ${UI_BOLD}${UI_CYAN}${title}${UI_RESET} ${UI_GRAY}- ${subtitle}${UI_RESET}" 116)" "$width" "$UI_CYAN"
    ui_box_line "$(ui_center "${UI_GRAY}📊 ${UI_CYAN}8 пакетов${UI_RESET} ${UI_GREEN}(3 AUR)${UI_RESET}   ${UI_GRAY}│   🔄 ${UI_ORANGE}2 обновления${UI_RESET}   ${UI_GRAY}│   ⚡ ${UI_GREEN}2896ms${UI_RESET}   ${UI_GRAY}│   🛡 Система: ${UI_GREEN}OK${UI_RESET}" 116)" "$width" "$UI_CYAN"
    ui_box_line "" "$width" "$UI_CYAN"
    ui_box_bottom "$width" "$UI_CYAN"
    printf '\n\n'
}

octo_panel() {
    local title="$1"
    local color="${2:-$UI_CYAN}"
    local width="${3:-74}"
    printf '%*s' 42 ''
    printf '%b╭─ %b%s%b %s╮%b\n' "$color" "$UI_BOLD" "$title" "$UI_RESET$color" "$(ui_repeat '─' "$((width - ${#title} - 6))")" "$UI_RESET"
}

octo_footer() {
    printf '\n\n%b╭%s╮%b\n' "$UI_NAVY" "$(ui_repeat '─' 156)" "$UI_RESET"
    printf '%b│%b  ↕ навигация   %bEnter%b выбор   %b1-9%b горячие клавиши   %bEsc%b назад%*s%b│%b\n' "$UI_NAVY" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" 84 '' "$UI_NAVY" "$UI_RESET"
    printf '%b╰%s╯%b\n' "$UI_NAVY" "$(ui_repeat '─' 156)" "$UI_RESET"
}

octo_screen_prompt() {
    printf '\n%b ' "${UI_CYAN}🐙 Нажмите Enter для возврата в главное меню:${UI_RESET}"
    read -r
}

octo_screen_packages() {
    octo_screen_header "СПИСОК ПАКЕТОВ OCTO" "Установленные и доступные пакеты"
    printf '%*s%b╭%s╮%b\n' 37 '' "$UI_GREEN" "$(ui_repeat '─' 84)" "$UI_RESET"
    printf '%*s%b│%b  📋 %bСПИСОК ПАКЕТОВ OCTO (14)%b%34s🔍 Фильтр пакетов...  %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" '' "$UI_GREEN" "$UI_RESET"
    printf '%*s%b├%s┤%b\n' 37 '' "$UI_GREEN" "$(ui_repeat '─' 84)" "$UI_RESET"
    printf '%*s%b│%b  %bВсе%b  Установленные  Обновления  Официальные  AUR  Сироты (Orphans)%12s%b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" '' "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  ┌%s┐  ┌%s┐ %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$(ui_repeat '─' 50)" "$(ui_repeat '─' 24)" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  │ %bAUR%b google-chrome              %b104.2MB%b        │  │ 📦 %bgoogle-chrome%b      │ %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$UI_PINK" "$UI_RESET" "$UI_GRAY" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  │ %bAUR%b neofetch      %bУстановлен%b 0.35MB │  │ Версия: %b150.0.7871.114%b │ %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$UI_PINK" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  │ %bAUR%b fastfetch-git             4.8MB │  │ Репозиторий: %bAUR%b       │ %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$UI_PINK" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  │ %bAUR%b leenfetch                 8.12MB│  │ Голоса AUR: ★ 3420      │ %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$UI_PINK" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  │ %bEXTRA%b obs-studio  %bUpd%b      185MB │  │ %b[ 📦 Установить ]%b       │ %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_ORANGE" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  │ %bEXTRA%b hyprland    %bUpd%b      28.4MB│  │ [ 🔍 Аудит PKGBUILD ]   │ %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_ORANGE" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  └%s┘  └%s┘ %b│%b\n' 37 '' "$UI_GREEN" "$UI_RESET" "$(ui_repeat '─' 50)" "$(ui_repeat '─' 24)" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b╰%s╯%b\n' 37 '' "$UI_GREEN" "$(ui_repeat '─' 84)" "$UI_RESET"
}

octo_screen_search() {
    octo_screen_header "ПОИСК В AUR" "Щупальца находят нужный пакет"
    local query="${1:-neofetch}"
    printf '%*s%b╭%s╮%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
    printf '%*s%b│%b  🐙 %bПОИСК В AUR (тентакли):%b%31s🔍 %s  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_PINK" "$UI_RESET" '' "$query" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b├%s┤%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
    printf '%*s%b│%b  ⚡ Используем супер-кэш (300с) │ AUR RPC v5 Endpoint%15s%b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" '' "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  ┌%s┐ %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$(ui_repeat '─' 68)" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  │ #  Пакет                    Версия          ★ Голосов  Популярность  Действие │ %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  │ 1  google-chrome            150.0.7871.114  ★ 3420    %b18.42%b       📦 Ловить │ %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  │ 2  neofetch %bустановлен%b       7.1.0-2        ★ 45      %b3.14%b        📦 Ловить │ %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  │ 3  fastfetch-git            2.10.2.r42-1    ★ 12      %b0.08%b        📦 Ловить │ %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  │ 4  visual-studio-code-bin   1.92.0-1       ★ 2190    %b14.80%b       📦 Ловить │ %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  └%s┘ %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$(ui_repeat '─' 68)" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  💡 Выбери номер пакета для установки или q для выхода%15s%b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" '' "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b                 [ 🔍 ДЕТАЛЬНЕЕ ]   %b[ 📦 УСТАНОВИТЬ ]%b   [ 📋 ВСЕ ПАКЕТЫ ]        %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b╰%s╯%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
}

octo_screen_stats() {
    octo_screen_header "СТАТИСТИКА OCTO" "Состояние пакетной системы"
    printf '%*s%b╭%s╮%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
    printf '%*s%b│%b  📊 %bСТАТИСТИКА И ПРЕДСКАЗАНИЯ OCTO%b%29s%b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" '' "$UI_CYAN" "$UI_RESET"
    printf '%*s%b├%s┤%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
    printf '%*s%b│%b  %bОбщая статистика%b   История операций (2)   Предсказатель OCTO%14s%b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" '' "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  │ Установлено  │ │ Обновлений   │ │ Диск         │ │ Кэш          │  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  │     %b8%b        │ │     %b2%b        │ │  %b715.45%b MB │ │  %b482.1%b MB  │  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_ORANGE" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_PINK" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  📁 Распределение места на диске по типам:%29s%b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" '' "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  Официальные пакеты Arch     %b████████████████████░░░░░░░░░░%b 485 MB (67%%)  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b  Пакеты AUR (тентакли)       %b██████████░░░░░░░░░░░░░░░░░░░░%b 230 MB (33%%)  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_PINK" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b│%b                         [ ← НАЗАД В ГЛАВНОЕ МЕНЮ ]                 %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
    printf '%*s%b╰%s╯%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
}

octo_screen_cleanup() {
    octo_screen_header "ОЧИСТКА OCTO" "Кэш пакетов и освобождение диска"
    printf '%*s%b╭%s╮%b\n' 42 '' "$UI_GREEN" "$(ui_repeat '─' 74)" "$UI_RESET"
    printf '%*s%b│%b  🧹 %bОЧИСТКА КЭША И ОСВОБОЖДЕНИЕ ДИСКА OCTO%b%19s%b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" '' "$UI_GREEN" "$UI_RESET"
    printf '%*s%b├%s┤%b\n' 42 '' "$UI_GREEN" "$(ui_repeat '─' 74)" "$UI_RESET"
    printf '%*s%b│%b  ┌────────────────────┐ ┌────────────────────┐ ┌────────────────────┐  %b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  │ Кэш пакетов        │ │ Сиротские пакеты   │ │ Кэш сборки AUR     │  %b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  │      %b482.1 MB%b      │ │  %b1 шт (12.4 MB)%b    │ │      %b169.5 MB%b      │  %b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" "$UI_PINK" "$UI_RESET" "$UI_ORANGE" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  └────────────────────┘ └────────────────────┘ └────────────────────┘  %b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  📋 Лог выполнения:%55s%b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" '' "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b  > Ready to perform system cleanup (paccache / orphan sweep)...%10s%b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" '' "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b       [ 🧹 ОЧИСТИТЬ КЭШ PACMAN ] [ 🗑 УДАЛИТЬ СИРОТ ] %b[ ✨ ОЧИСТИТЬ ВСЕ ]%b   %b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b│%b                              [ ← ВЫХОД ]                             %b│%b\n' 42 '' "$UI_GREEN" "$UI_RESET" "$UI_GREEN" "$UI_RESET"
    printf '%*s%b╰%s╯%b\n' 42 '' "$UI_GREEN" "$(ui_repeat '─' 74)" "$UI_RESET"
}

# Осьминожки для анимации
OCTO_FRAMES=("🐙" "🐚" "🦑" "🐚" "🐙" "🐚" "🦑")

# Прогресс-бар с осьминогом
show_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"
    local message="${4:-Выполнение}"
    
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    # Выбираем осьминога
    local frame_index=$((current % ${#OCTO_FRAMES[@]}))
    local octo="${OCTO_FRAMES[$frame_index]}"
    
    # Строим бар
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done
    
    # Цвет в зависимости от процента
    local color="$UI_GREEN"
    if [ $percent -lt 30 ]; then
        color="$UI_RED"
    elif [ $percent -lt 60 ]; then
        color="$UI_YELLOW"
    fi
    
    echo -ne "\r${UI_BLUE}${octo} ${message} ${color}[${bar}] ${UI_WHITE}${percent}%${UI_RESET}"
}

# Анимированный поиск
show_search_animation() {
    local query="$1"
    local frames=("🔍" "🔎" "🐙" "🦑" "🔍" "🔎")
    local count=0
    
    echo -ne "${UI_BLUE}🐙 Ищем: ${UI_WHITE}$query ${UI_DIM}"
    
    while [ $count -lt 20 ]; do
        local frame_index=$((count % ${#frames[@]}))
        echo -ne "\r${UI_BLUE}${frames[$frame_index]} Ищем: ${UI_WHITE}$query ${UI_DIM}${count}%"
        sleep 0.05
        count=$((count + 5))
    done
    
    echo -e "\r${UI_GREEN}✅ Найдено!                    ${UI_RESET}"
}

# Анимированная установка
show_install_animation() {
    local pkg="$1"
    local frames=("📦" "📥" "🐙" "🦑" "📦" "📥")
    local count=0
    
    echo -ne "${UI_BLUE}🐙 Ловим: ${UI_WHITE}$pkg ${UI_DIM}"
    
    while [ $count -lt 30 ]; do
        local frame_index=$((count % ${#frames[@]}))
        echo -ne "\r${UI_BLUE}${frames[$frame_index]} Ловим: ${UI_WHITE}$pkg ${UI_DIM}${count}%"
        sleep 0.05
        count=$((count + 3))
    done
    
    echo -e "\r${UI_GREEN}✅ Пойман!                     ${UI_RESET}"
}

# Спиннер для длительных операций
show_spinner() {
    local message="$1"
    local frames=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")
    local count=0
    
    while true; do
        local frame_index=$((count % ${#frames[@]}))
        echo -ne "\r${UI_BLUE}${frames[$frame_index]} ${UI_WHITE}$message${UI_RESET}"
        sleep 0.1
        count=$((count + 1))
    done
}

# Остановить спиннер
stop_spinner() {
    local pid="$1"
    local status="$2"
    
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    
    if [ "$status" == "success" ]; then
        echo -e "\r${UI_GREEN}✅ Готово!                    ${UI_RESET}"
    else
        echo -e "\r${UI_RED}❌ Ошибка!                    ${UI_RESET}"
    fi
}

# Красивый заголовок
show_header() {
    local title="$1"
    local subtitle="$2"
    
    echo -e "${UI_BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              ${UI_BOLD}🐙 ${title}${UI_RESET}${UI_BLUE}                              ║"
    if [ -n "$subtitle" ]; then
        echo "║              ${UI_DIM}${subtitle}${UI_BLUE}                    ║"
    fi
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${UI_RESET}"
}

# Красивый футер
show_footer() {
    local message="$1"
    
    echo -e "\n${UI_DIM}════════════════════════════════════════════════════════════${UI_RESET}"
    echo -e "${UI_GREEN}🐙 ${message}${UI_RESET}"
}

# Прогресс для скачивания пакетов
download_progress() {
    local current="$1"
    local total="$2"
    local pkg="$3"
    
    local percent=$((current * 100 / total))
    local octo_frames=("🐙" "🦑" "🐚" "🦑")
    local frame_index=$((current % ${#octo_frames[@]}))
    
    echo -ne "\r${UI_BLUE}${octo_frames[$frame_index]} Скачивание: ${UI_WHITE}$pkg ${UI_GREEN}["
    
    local bar_size=30
    local filled=$((current * bar_size / total))
    
    for ((i=0; i<filled; i++)); do
        echo -ne "█"
    done
    for ((i=filled; i<bar_size; i++)); do
        echo -ne "░"
    done
    
    echo -ne "] ${UI_YELLOW}${percent}%${UI_RESET}"
    
    if [ $current -eq $total ]; then
        echo -e "\n${UI_GREEN}✅ Готово!${UI_RESET}"
    fi
}

# Пульсирующий осьминог
pulsing_octo() {
    local message="$1"
    local frames=("🐙" "🐙" "🐙" "🐚" "🦑" "🦑" "🦑")
    local count=0
    
    echo -ne "${UI_BLUE}"
    while true; do
        local frame_index=$((count % ${#frames[@]}))
        echo -ne "\r${frames[$frame_index]} ${UI_WHITE}$message${UI_RESET}"
        sleep 0.2
        count=$((count + 1))
    done
}

# Умный прогресс для сборки
build_progress() {
    local phase="$1"
    local current="$2"
    local total="$3"
    
    local phases=(
        "🔨 Сборка"
        "📦 Упаковка"
        "🔧 Конфигурация"
        "🐙 Оптимизация"
        "✅ Завершение"
    )
    
    local phase_index=$((current * ${#phases[@]} / total))
    if [ $phase_index -ge ${#phases[@]} ]; then
        phase_index=$((${#phases[@]} - 1))
    fi
    
    local current_phase="${phases[$phase_index]}"
    
    echo -ne "\r${UI_BLUE}${current_phase} ${UI_WHITE}["
    
    local bar_size=40
    local filled=$((current * bar_size / total))
    
    for ((i=0; i<filled; i++)); do
        echo -ne "█"
    done
    for ((i=filled; i<bar_size; i++)); do
        echo -ne "░"
    done
    
    echo -ne "] ${UI_YELLOW}$((current * 100 / total))%${UI_RESET}"
    
    if [ $current -eq $total ]; then
        echo -e "\n${UI_GREEN}✅ Сборка завершена!${UI_RESET}"
    fi
}

# Матрица осьминогов
octo_matrix() {
    local frames=("🐙" "🦑" "🐚" "🐙" "🦑")
    local cols=$(tput cols 2>/dev/null || echo 80)
    local cols=$((cols / 2))
    
    echo -e "${UI_GREEN}"
    for ((i=0; i<10; i++)); do
        for ((j=0; j<cols; j++)); do
            local frame_index=$((RANDOM % ${#frames[@]}))
            echo -ne "${frames[$frame_index]} "
        done
        echo ""
        sleep 0.05
    done
    echo -e "${UI_RESET}"
}

# Экспорт функций
export -f show_progress_bar
export -f show_search_animation
export -f show_install_animation
export -f show_spinner
export -f stop_spinner
export -f show_header
export -f show_footer
export -f download_progress
export -f pulsing_octo
export -f build_progress
export -f octo_matrix
