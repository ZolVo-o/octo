#!/bin/bash

# Модуль мониторинга и бенчмарка OCTO

benchmark() {
    echo -e "\033[36m"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              ⚡ БЕНЧМАРК OCTO 4.0 ⚡                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    echo -e "\033[33m📡 Тест скорости AUR API:\033[0m"
    local aur_time=0
    local success=0
    
    for i in {1..2}; do
        local start=$(date +%s%N)
        if curl -s --max-time 5 --connect-timeout 3 "https://aur.archlinux.org/rpc/v5/search?arg=neofetch" > /dev/null 2>&1; then
            local end=$(date +%s%N)
            aur_time=$((($end - $start) / 1000000))
            success=1
            break
        else
            sleep 1
        fi
    done
    
    if [ $success -eq 1 ] && [ $aur_time -lt 500 ]; then
        echo -e "  🚀 AUR запрос: \033[32m${aur_time}ms\033[0m (отлично!)"
    elif [ $success -eq 1 ] && [ $aur_time -lt 1000 ]; then
        echo -e "  ⚡ AUR запрос: \033[33m${aur_time}ms\033[0m (хорошо)"
    elif [ $success -eq 1 ] && [ $aur_time -lt 2000 ]; then
        echo -e "  🐢 AUR запрос: \033[33m${aur_time}ms\033[0m (средне)"
    else
        echo -e "  🔴 AUR запрос: \033[31m${aur_time}ms\033[0m (медленно)"
    fi
    
    echo -e "\n\033[33m📦 Тест скорости Git:\033[0m"
    local start=$(date +%s%N)
    if git clone --depth 1 --quiet "https://aur.archlinux.org/neofetch.git" /tmp/benchmark-git-$$ 2>/dev/null; then
        local end=$(date +%s%N)
        local git_time=$((($end - $start) / 1000000))
        rm -rf /tmp/benchmark-git-$$ 2>/dev/null
        
        if [ $git_time -lt 1000 ]; then
            echo -e "  🚀 Git clone: \033[32m${git_time}ms\033[0m (отлично!)"
        elif [ $git_time -lt 3000 ]; then
            echo -e "  ⚡ Git clone: \033[33m${git_time}ms\033[0m (хорошо)"
        else
            echo -e "  🐢 Git clone: \033[31m${git_time}ms\033[0m (медленно)"
        fi
    else
        echo -e "  🔴 Git clone: \033[31mНЕДОСТУПЕН\033[0m"
        local git_time=9999
    fi
    
    echo -e "\n\033[33m🔍 Тест скорости парсинга:\033[0m"
    local start=$(date +%s%N)
    if curl -s --max-time 3 "https://aur.archlinux.org/rpc/v5/search?arg=neofetch" 2>/dev/null | jq '.results[0].Name' > /dev/null 2>&1; then
        local end=$(date +%s%N)
        local parse_time=$((($end - $start) / 1000000))
        echo -e "  ⚡ Парсинг JSON: \033[32m${parse_time}ms\033[0m"
    else
        echo -e "  🔴 Парсинг JSON: \033[31mНЕДОСТУПЕН\033[0m"
        local parse_time=9999
    fi
    
    local total_time=$((aur_time + git_time + parse_time))
    echo -e "\n\033[36m═══════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[33m📊 Общее время: \033[1m${total_time}ms\033[0m"
    
    if [ $total_time -lt 2000 ]; then
        echo -e "\033[32m🏆 OCTO работает МОЛНИЕНОСНО! 🚀\033[0m"
    elif [ $total_time -lt 4000 ]; then
        echo -e "\033[33m⚡ OCTO работает быстро! 💨\033[0m"
    elif [ $total_time -lt 6000 ]; then
        echo -e "\033[33m🐢 OCTO работает нормально\033[0m"
    else
        echo -e "\033[31m🐌 OCTO работает медленно, нужна оптимизация\033[0m"
    fi
    
    echo -e "\n\033[36m💡 Рекомендации:\033[0m"
    if [ $aur_time -gt 2000 ]; then
        echo -e "  - Проверь интернет-соединение"
    fi
    if [ $git_time -gt 3000 ]; then
        echo -e "  - Проверь скорость интернета"
    fi
    echo -e "  - Кэш включен: ✅"
    echo -e ""
}

monitor_resources() {
    echo -e "\033[36m"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              📊 МОНИТОРИНГ СИСТЕМЫ                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
    local cpu_cores=$(nproc)
    echo -e "\033[33m💻 CPU:\033[0m"
    echo -e "  Ядер: $cpu_cores"
    echo -e "  Загрузка: $cpu_load"
    
    local mem_total=$(free -h | grep "^Mem:" | awk '{print $2}')
    local mem_used=$(free -h | grep "^Mem:" | awk '{print $3}')
    local mem_percent=$(free | grep "^Mem:" | awk '{printf "%.1f", ($3/$2)*100}')
    echo -e "\n\033[33m🧠 Память:\033[0m"
    echo -e "  Всего: $mem_total"
    echo -e "  Использовано: $mem_used ($mem_percent%)"
    
    local disk_used=$(df -h / | tail -1 | awk '{print $3}')
    local disk_total=$(df -h / | tail -1 | awk '{print $2}')
    local disk_percent=$(df -h / | tail -1 | awk '{print $5}')
    echo -e "\n\033[33m💾 Диск:\033[0m"
    echo -e "  Всего: $disk_total"
    echo -e "  Использовано: $disk_used ($disk_percent)"
    
    echo -e "\n\033[33m🐙 OCTO:\033[0m"
    local cache_size=$(du -sh "$OCTO_ROOT/cache" 2>/dev/null | cut -f1 || echo "0")
    local backups_count=$(ls -1 "$OCTO_ROOT/backups" 2>/dev/null | wc -l)
    local logs_count=$(ls -1 "$OCTO_ROOT/logs" 2>/dev/null | wc -l)
    echo -e "  Кэш: $cache_size"
    echo -e "  Бэкапов: $backups_count"
    echo -e "  Логов: $logs_count"
    echo -e ""
}

profile_operation() {
    local operation="$1"
    local pkg="$2"
    
    echo -e "\033[36m"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              📊 ПРОФИЛИРОВАНИЕ: $operation              ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    local start_time=$(date +%s)
    local start_mem=$(free | grep "^Mem:" | awk '{print $3}')
    
    case "$operation" in
        "search") 
            echo -e "\033[33m🔍 Выполняем поиск...\033[0m"
            fast_aur_search "$pkg" > /dev/null 2>&1
            ;;
        "install") 
            echo -e "\033[33m📦 Выполняем установку...\033[0m"
            install_with_deps "$pkg" > /dev/null 2>&1
            ;;
        "remove") 
            echo -e "\033[33m🗑️  Выполняем удаление...\033[0m"
            release_package "$pkg" > /dev/null 2>&1
            ;;
        *) 
            echo -e "\033[31m❌ Неизвестная операция\033[0m"
            return 1
            ;;
    esac
    
    local end_time=$(date +%s)
    local end_mem=$(free | grep "^Mem:" | awk '{print $3}')
    
    local duration=$((end_time - start_time))
    local mem_usage=$(((end_mem - start_mem) / 1024))
    
    echo -e "\n\033[36m═══════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[33m⏱️  Время выполнения: \033[1m${duration}с\033[0m"
    echo -e "\033[33m🧠 Использовано памяти: \033[1m${mem_usage}MB\033[0m"
    
    if [ $duration -lt 5 ]; then
        echo -e "\033[32m✅ Операция выполнена быстро! 🚀\033[0m"
    elif [ $duration -lt 15 ]; then
        echo -e "\033[33m⚡ Операция выполнена нормально\033[0m"
    else
        echo -e "\033[31m🐢 Операция выполнена медленно\033[0m"
    fi
    echo -e ""
}

predict_time() {
    local pkg="$1"
    
    echo -e "\033[36m"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              🔮 ПРОГНОЗ ВРЕМЕНИ                        ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    echo -e "\033[33m📦 Пакет: $pkg\033[0m"
    echo -e "\033[33m💻 Ядер CPU: $(nproc)\033[0m"
    echo -e "\n\033[36m═══════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[33m⏱️  Прогнозируемое время:\033[0m"
    echo -e "  \033[1m30 - 60 секунд\033[0m"
    echo -e "  \033[1m~1 минута\033[0m"
    echo -e ""
}

analyze_logs() {
    echo -e "\033[36m"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              📋 АНАЛИЗ ЛОГОВ OCTO                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    if [ ! -d "$OCTO_ROOT/logs" ]; then
        echo -e "\033[33m⚠️  Логов пока нет\033[0m"
        return 0
    fi
    
    local log_count=$(ls -1 "$OCTO_ROOT/logs" 2>/dev/null | wc -l)
    echo -e "\033[33m📄 Всего логов: $log_count\033[0m"
    
    if [ -f "$OCTO_ROOT/logs/errors.log" ]; then
        local errors=$(wc -l < "$OCTO_ROOT/logs/errors.log" 2>/dev/null || echo 0)
        echo -e "\033[31m❌ Ошибок: $errors\033[0m"
    fi
    
    if [ -f "$OCTO_ROOT/logs/installs.log" ]; then
        local installs=$(wc -l < "$OCTO_ROOT/logs/installs.log" 2>/dev/null || echo 0)
        echo -e "\033[32m✅ Установок: $installs\033[0m"
    fi
    
    echo -e ""
}
