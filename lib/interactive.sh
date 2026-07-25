#!/bin/bash

# Интерактивный режим OCTO

# Интерактивный выбор пакетов
interactive_select() {
    local results=("$@")
    local selected=()
    
    echo -e "${UI_BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              🐙 ИНТЕРАКТИВНЫЙ ВЫБОР                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${UI_RESET}"
    
    local i=1
    for result in "${results[@]}"; do
        echo -e "  ${UI_YELLOW}$i)${UI_RESET} $result"
        ((i++))
    done
    
    echo -e "\n${UI_BLUE}Выберите номера через пробел (или 'q' для выхода):${UI_RESET}"
    read -r selection
    
    if [ "$selection" = "q" ] || [ -z "$selection" ]; then
        echo -e "${UI_RED}❌ Отменено${UI_RESET}"
        return 1
    fi
    
    for num in $selection; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#results[@]} ]; then
            selected+=("${results[$((num-1))]}")
        fi
    done
    
    echo "${selected[@]}"
}

# Интерактивная установка
interactive_install() {
    local search_query="$1"
    
    echo -e "${UI_BLUE}🐙 Ищем пакеты: ${UI_WHITE}$search_query${UI_RESET}"
    
    local results=$(fast_aur_search "$search_query" 2>/dev/null | grep -E "^  " | head -20)
    
    if [ -z "$results" ]; then
        echo -e "${UI_RED}❌ Ничего не найдено${UI_RESET}"
        return 1
    fi
    
    local packages=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
            packages+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$results"
    
    if [ ${#packages[@]} -eq 0 ]; then
        echo -e "${UI_RED}❌ Не удалось распарсить результаты${UI_RESET}"
        return 1
    fi
    
    echo -e "\n${UI_GREEN}Найдено пакетов: ${#packages[@]}${UI_RESET}"
    
    local i=1
    for pkg in "${packages[@]}"; do
        echo -e "  ${UI_YELLOW}$i)${UI_RESET} $pkg"
        ((i++))
    done
    
    echo -e "\n${UI_BLUE}Выберите номера через пробел (или 'q' для выхода):${UI_RESET}"
    read -r selection
    
    if [ "$selection" = "q" ] || [ -z "$selection" ]; then
        echo -e "${UI_RED}❌ Отменено${UI_RESET}"
        return 1
    fi
    
    for num in $selection; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#packages[@]} ]; then
            local pkg="${packages[$((num-1))]}"
            echo -e "${UI_GREEN}🐙 Устанавливаем: $pkg${UI_RESET}"
            show_install_animation "$pkg"
            catch_package "$pkg"
        fi
    done
}

# Интерактивное меню
interactive_menu() {
    while true; do
        octo_screen_header "OCTO 4.0" "Твой осьминог в мире Arch Linux"
        printf '%*s%b╭%s╮%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
        printf '%*s%b│%b  📊 Статистика: %b8 пакетов%b │ %b2 обновления%b │ %b2896ms%b%27s%b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_ORANGE" "$UI_RESET" "$UI_GREEN" "$UI_RESET" '' "$UI_CYAN" "$UI_RESET"
        printf '%*s%b├%s┤%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
        printf '%*s%b│%b%74s%b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" '' "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b  %b1.%b  📦 %bУСТАНОВИТЬ ПАКЕТ%b%39s%b[Enter]%b  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_BOLD$UI_GREEN" "$UI_RESET" '' "$UI_DIM" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b  %b2.%b  🗑  %bУДАЛИТЬ ПАКЕТ%b%42s%b[Enter]%b  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_PINK" "$UI_RESET" '' "$UI_DIM" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b  %b3.%b  🔄 %bОБНОВИТЬ СИСТЕМУ%b%38s%b[Enter]%b  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_ORANGE" "$UI_RESET" '' "$UI_DIM" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b  %b4.%b  📋 %bСПИСОК ПАКЕТОВ%b%41s%b[Enter]%b  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" '' "$UI_DIM" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b  %b5.%b  🐙 %bПОИСК В AUR (тентакли)%b%31s%b[Enter]%b  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_PINK" "$UI_RESET" '' "$UI_DIM" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b  %b6.%b  ⚡ %bБЕНЧМАРК%b%48s%b[Enter]%b  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_ORANGE" "$UI_RESET" '' "$UI_DIM" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b  %b7.%b  📊 %bСТАТИСТИКА%b%45s%b[Enter]%b  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" '' "$UI_DIM" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b  %b8.%b  🧹 %bОЧИСТКА%b%50s%b[Enter]%b  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_CYAN" "$UI_RESET" "$UI_GREEN" "$UI_RESET" '' "$UI_DIM" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b%b  🐙 9. ❌ ВЫХОД / CLI SHELL%38s[Enter]  %b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" "$UI_BLUE" '' "$UI_CYAN" "$UI_RESET"
        printf '%*s%b│%b%74s%b│%b\n' 42 '' "$UI_CYAN" "$UI_RESET" '' "$UI_CYAN" "$UI_RESET"
        printf '%*s%b╰%s╯%b\n' 42 '' "$UI_CYAN" "$(ui_repeat '─' 74)" "$UI_RESET"
        octo_footer
        printf '\n%b ' "${UI_CYAN}🐙 Выбери действие:${UI_RESET}"
        read -r choice
        
        case $choice in
            1)
                echo -e "${UI_BLUE}Введите поисковый запрос:${UI_RESET}"
                read -r query
                interactive_install "$query"
                ;;
            2)
                octo_screen_header "ОСВОБОЖДЕНИЕ ПАКЕТА" "Удаление установленного пакета"
                printf '%b ' "${UI_PINK}Введите имя пакета:${UI_RESET}"
                read -r pkg
                printf '%b ' "${UI_RED}Удалить $pkg? [да/нет]${UI_RESET}"
                read -r confirm
                if [[ "$confirm" =~ ^(да|Да|y|Y)$ ]]; then
                    release_package "$pkg"
                fi
                ;;
            3)
                octo_screen_header "ОБНОВЛЕНИЕ СИСТЕМЫ" "Pacman + AUR army"
                full_system_update
                ;;
            4)
                octo_screen_packages
                ;;
            5)
                printf '%b ' "${UI_PINK}Введите запрос для AUR:${UI_RESET}"
                read -r query
                octo_screen_search "$query"
                printf '\n%b' "${UI_DIM}Нажмите Enter, чтобы выполнить реальный AUR-поиск...${UI_RESET}"
                read -r
                fast_aur_search "$query"
                ;;
            6)
                benchmark
                ;;
            7)
                octo_screen_stats
                ;;
            8)
                octo_screen_cleanup
                printf '\n%b\n' "${UI_BLUE}Очистить: 1) Кэш  2) Бэкапы  3) Всё${UI_RESET}"
                read -r clean_choice
                case $clean_choice in
                    1) clean_cache ;;
                    2) clean_backups ;;
                    3) clean_cache && clean_backups ;;
                    *) echo -e "${UI_RED}❌ Неверный выбор${UI_RESET}" ;;
                esac
                ;;
            9)
                octo_shell
                ;;
            0)
                echo -e "${UI_GREEN}🐙 До свидания!${UI_RESET}"
                break
                ;;
            *)
                echo -e "${UI_RED}❌ Неверный выбор${UI_RESET}"
                ;;
        esac
        
        printf '\n%b' "${UI_DIM}Нажмите Enter для продолжения...${UI_RESET}"
        read -r
    done
}
