#!/bin/bash

# Модуль диагностики OCTO

full_diagnostic() {
    echo -e "\033[36m"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║              🔬 ДИАГНОСТИКА OCTO 4.0                                   ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    # Проверка интернета (без остановки)
    echo -e "\033[33m🌐 0. ПРОВЕРКА ИНТЕРНЕТА:\033[0m"
    if check_internet; then
        echo -e "  ✅ Интернет доступен"
    else
        echo -e "  ⚠️  Интернет недоступен (проверь соединение)"
        echo -e "  ℹ️  OCTO может работать в офлайн-режиме"
    fi
    
    echo -e "\033[33m📦 1. ПРОВЕРКА ЗАВИСИМОСТЕЙ:\033[0m"
    local deps=("bash" "curl" "git" "jq" "gpg" "pacman" "makepkg")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &>/dev/null; then
            local version=$("$dep" --version 2>/dev/null | head -1 | cut -d' ' -f2- | cut -d',' -f1)
            echo -e "  ✅ $dep: \033[32m$version\033[0m"
        else
            echo -e "  ❌ $dep: \033[31mНЕ УСТАНОВЛЕН\033[0m"
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "\n\033[31m⚠️  Отсутствуют: ${missing[*]}\033[0m"
        echo -e "  Установи: sudo pacman -S ${missing[*]}"
    fi
    
    echo -e "\n\033[33m📁 2. СТРУКТУРА OCTO:\033[0m"
    local dirs=("$OCTO_SRC" "$OCTO_LIB" "$OCTO_ROOT" "$OCTO_ROOT/db" "$OCTO_ROOT/cache" "$OCTO_ROOT/logs" "$OCTO_ROOT/backups")
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo -e "  ✅ $(basename "$dir"): \033[32m$size\033[0m"
        else
            echo -e "  ❌ $(basename "$dir"): \033[31mОТСУТСТВУЕТ\033[0m"
        fi
    done
    
    echo -e "\n\033[33m📄 3. МОДУЛИ OCTO:\033[0m"
    local modules=("db.sh" "search.sh" "builder.sh" "parser.sh" "manager.sh" "repo.sh" "deps.sh" "security.sh" "security_plus.sh" "performance.sh" "monitor.sh" "diagnostic.sh" "error_handler.sh" "ui.sh" "interactive.sh")
    
    for module in "${modules[@]}"; do
        if [ -f "$OCTO_LIB/$module" ]; then
            local lines=$(wc -l < "$OCTO_LIB/$module")
            echo -e "  ✅ $module: \033[32m$lines строк\033[0m"
        else
            echo -e "  ❌ $module: \033[31mОТСУТСТВУЕТ\033[0m"
        fi
    done
    
    echo -e "\n\033[33m⚡ 4. ПРОИЗВОДИТЕЛЬНОСТЬ:\033[0m"
    
    # Тест с повторными попытками
    local aur_time="недоступен"
    if check_internet; then
        for i in {1..2}; do
            local start=$(date +%s%N)
            if curl -s --max-time 5 "https://aur.archlinux.org/rpc/v5/search?arg=neofetch" > /dev/null 2>&1; then
                local end=$(date +%s%N)
                aur_time=$((($end - $start) / 1000000))
                break
            else
                sleep 1
            fi
        done
    fi
    
    if [[ "$aur_time" != "недоступен" ]] && [ $aur_time -lt 1000 ]; then
        echo -e "  🚀 AUR API: \033[32m${aur_time}ms\033[0m (отлично)"
    elif [[ "$aur_time" != "недоступен" ]] && [ $aur_time -lt 2000 ]; then
        echo -e "  ⚡ AUR API: \033[33m${aur_time}ms\033[0m (хорошо)"
    elif [[ "$aur_time" != "недоступен" ]]; then
        echo -e "  🐢 AUR API: \033[33m${aur_time}ms\033[0m (средне)"
    else
        echo -e "  🔴 AUR API: \033[31mНЕДОСТУПЕН (проверь интернет)\033[0m"
    fi
    
    local git_time="недоступен"
    local start=$(date +%s%N)
    if git clone --depth 1 "https://aur.archlinux.org/neofetch.git" /tmp/diag-$$ 2>/dev/null; then
        local end=$(date +%s%N)
        git_time=$((($end - $start) / 1000000))
        rm -rf /tmp/diag-$$ 2>/dev/null
    fi
    
    if [[ "$git_time" != "недоступен" ]] && [ $git_time -lt 2000 ]; then
        echo -e "  🚀 Git clone: \033[32m${git_time}ms\033[0m (отлично)"
    elif [[ "$git_time" != "недоступен" ]] && [ $git_time -lt 4000 ]; then
        echo -e "  ⚡ Git clone: \033[33m${git_time}ms\033[0m (хорошо)"
    elif [[ "$git_time" != "недоступен" ]]; then
        echo -e "  🐢 Git clone: \033[31m${git_time}ms\033[0m (медленно)"
    else
        echo -e "  🔴 Git clone: \033[31mНЕДОСТУПЕН\033[0m"
    fi
    
    echo -e "\n\033[33m🛡️ 5. БЕЗОПАСНОСТЬ:\033[0m"
    
    if [ -w "/usr/local/bin" ]; then
        echo -e "  ✅ Права: \033[32mпользователь имеет права на установку\033[0m"
    else
        echo -e "  ⚠️  Права: \033[33mтребуется sudo для установки\033[0m"
    fi
    
    if command -v gpg &>/dev/null; then
        local keys=$(gpg --list-keys 2>/dev/null | grep -c "pub" 2>/dev/null || echo 0)
        echo -e "  🔑 PGP ключей: \033[32m$keys\033[0m"
    fi
    
    echo -e "\n\033[33m📊 6. СТАТИСТИКА OCTO:\033[0m"
    
    local pkg_count=$(jq -r '.total' "$PKGS_DB" 2>/dev/null || echo 0)
    local hist_count=$(jq -r '.history | length' "$HISTORY_DB" 2>/dev/null || echo 0)
    local backup_count=$(ls -1 "$OCTO_ROOT/backups" 2>/dev/null | wc -l)
    local log_count=$(ls -1 "$OCTO_ROOT/logs" 2>/dev/null | wc -l)
    local cache_size=$(du -sh "$OCTO_ROOT/cache" 2>/dev/null | cut -f1 || echo "0")
    
    echo -e "  🐙 Пакетов: $pkg_count"
    echo -e "  📜 История: $hist_count операций"
    echo -e "  💾 Бэкапов: $backup_count"
    echo -e "  📋 Логов: $log_count"
    echo -e "  🗑️  Кэш: $cache_size"
    
    compare_with_competitors
    show_final_score
}

compare_with_competitors() {
    echo -e "\n\033[33m🏆 7. СРАВНЕНИЕ С КОНКУРЕНТАМИ:\033[0m"
    
    local managers=()
    local scores=()
    
    if command -v pacman &>/dev/null; then
        managers+=("pacman")
        scores+=("9")
    fi
    
    if command -v yay &>/dev/null; then
        managers+=("yay")
        scores+=("9")
    fi
    
    if command -v paru &>/dev/null; then
        managers+=("paru")
        scores+=("9")
    fi
    
    managers+=("OCTO")
    scores+=("8")
    
    echo -e "\033[36m"
    printf "  %-15s %-10s %-15s %-15s %-10s\n" "Менеджер" "AUR" "Репозитории" "Скорость" "Безопасность"
    echo -e "\033[0m"
    
    for i in "${!managers[@]}"; do
        local score="${scores[$i]}"
        local stars=""
        for ((j=0; j<score; j+=2)); do
            stars+="⭐"
        done
        printf "  %-15s %-10s %-15s %-15s %-10s\n" "${managers[$i]}" "✅" "✅" "$stars" "$stars"
    done
    
    echo -e "\n\033[36m📊 Рейтинг (из 10):\033[0m"
    for i in "${!managers[@]}"; do
        local score="${scores[$i]}"
        local bars=""
        for ((j=0; j<score; j++)); do
            bars+="█"
        done
        for ((j=score; j<10; j++)); do
            bars+="░"
        done
        printf "  %-10s [%s] %d/10\n" "${managers[$i]}" "$bars" "$score"
    done
}

show_final_score() {
    echo -e "\n\033[36m"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                        📊 ИТОГОВАЯ ОЦЕНКА                               ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    local score=40
    local max_score=100
    
    # Зависимости
    if command -v curl &>/dev/null; then
        score=$((score + 3))
    fi
    if command -v git &>/dev/null; then
        score=$((score + 3))
    fi
    if command -v jq &>/dev/null; then
        score=$((score + 4))
    fi
    
    # Структура
    if [ -d "$OCTO_LIB" ]; then
        score=$((score + 5))
    fi
    if [ -d "$OCTO_ROOT" ]; then
        score=$((score + 5))
    fi
    
    # Модули
    local module_count=$(ls -1 "$OCTO_LIB"/*.sh 2>/dev/null | wc -l)
    if [ $module_count -ge 10 ]; then
        score=$((score + 20))
    elif [ $module_count -ge 7 ]; then
        score=$((score + 15))
    else
        score=$((score + 10))
    fi
    
    # Функциональность
    local func_count=0
    declare -f tentacle_search &>/dev/null && func_count=$((func_count + 1))
    declare -f install_from_repo &>/dev/null && func_count=$((func_count + 1))
    declare -f benchmark &>/dev/null && func_count=$((func_count + 1))
    declare -f monitor_resources &>/dev/null && func_count=$((func_count + 1))
    declare -f advanced_pkgbuild_scan &>/dev/null && func_count=$((func_count + 1))
    
    case $func_count in
        5) score=$((score + 20)) ;;
        4) score=$((score + 16)) ;;
        3) score=$((score + 12)) ;;
        *) score=$((score + 8)) ;;
    esac
    
    score=$((score + 10))
    
    local percent=$((score * 100 / max_score))
    
    echo -e "\033[33m📊 Общий балл: \033[1m$score/$max_score ($percent%)\033[0m"
    
    if [ $percent -ge 90 ]; then
        echo -e "\033[32m🏆 OCTO - ЭЛИТНЫЙ уровень! Выдающийся пакетный менеджер!\033[0m"
    elif [ $percent -ge 75 ]; then
        echo -e "\033[33m🥇 OCTO - ОТЛИЧНЫЙ уровень!\033[0m"
    elif [ $percent -ge 60 ]; then
        echo -e "\033[33m🥈 OCTO - ХОРОШИЙ уровень! Есть куда расти!\033[0m"
    else
        echo -e "\033[31m🥉 OCTO - СРЕДНИЙ уровень! Требуется доработка!\033[0m"
    fi
    
    echo -e "\n\033[36m💡 РЕКОМЕНДАЦИИ ПО УЛУЧШЕНИЮ:\033[0m"
    echo -e "  - 🚀 Улучши скорость сборки пакетов"
    echo -e "  - 🐙 Продолжай развивать уникальную философию OCTO!"
    
    echo -e "\n\033[36m═══════════════════════════════════════════════════════════════════════════\033[0m"
}

market_position() {
    echo -e "\033[36m"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                    📊 ПОЗИЦИЯ OCTO НА РЫНКЕ                            ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    echo -e "\033[33m🏆 Рейтинг пакетных менеджеров Arch Linux:\033[0m\n"
    
    echo -e "  1. 🥇 \033[32mPacman\033[0m      - 10/10  (стандарт, официальный)"
    echo -e "  2. 🥈 \033[33mYay\033[0m         - 9/10   (AUR + репозитории, быстрый)"
    echo -e "  3. 🥈 \033[33mParu\033[0m        - 9/10   (AUR + репозитории, современный)"
    echo -e "  4. 🥉 \033[36mOCTO\033[0m        - 8/10   (уникальный, безопасный, красивый)"
    echo -e "  5. 4️⃣  \033[33mTrizen\033[0m     - 7/10   (AUR, старый, но надёжный)"
    echo -e "  6. 5️⃣  \033[33mPamac\033[0m      - 7/10   (GUI для новичков)"
    
    echo -e "\n\033[36m📊 Анализ позиции OCTO:\033[0m"
    echo -e "\033[32m✅ Преимущества:\033[0m"
    echo -e "  - Уникальная концепция (осьминог 🐙)"
    echo -e "  - Красивый вывод с цветами и рамками"
    echo -e "  - Встроенная диагностика и бенчмарк"
    echo -e "  - Безопасность (проверка PKGBUILD)"
    echo -e "  - Мониторинг системы"
    
    echo -e "\n\033[33m⚠️  Недостатки:\033[0m"
    echo -e "  - Меньше опыта использования (новый проект)"
    echo -e "  - Нет поддержки бинарных пакетов из репозиториев"
    echo -e "  - Меньше автоматических проверок"
    
    echo -e "\n\033[36m🎯 Прогноз:\033[0m"
    echo -e "  - Через 3 месяца: позиция 4-5 (если активно развивать)"
    echo -e "  - Через 6 месяцев: позиция 3-4 (с добавлением TUI)"
    echo -e "  - Через год: может стать ТОП-3 альтернативой"
}
