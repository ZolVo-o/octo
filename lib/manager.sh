#!/bin/bash

# Модуль управления пакетами OCTO

release_with_deps() {
    local pkg="$1"
    
    if [ -z "$pkg" ]; then
        echo -e "\033[31m🐙 OCTO: Укажи пакет для освобождения!\033[0m"
        return 1
    fi
    
    echo -e "\033[33m🔄 Отпускаем $pkg с зависимостями...\033[0m"
    
    if ! db_is_installed "$pkg"; then
        echo -e "\033[31m❌ Пакет $pkg не найден в нашей базе\033[0m"
        return 1
    fi
    
    local deps=$(pacman -Qi "$pkg" 2>/dev/null | grep "^依赖关系" | cut -d: -f2 | tr ',' '\n' | sed 's/^ //g' | grep -v "^$")
    
    if [ -n "$deps" ]; then
        echo -e "\033[36m📦 Найдены зависимости:\033[0m"
        echo "$deps" | sed 's/^/  /'
        
        echo -e "\n\033[33m⚠️  Удалить зависимости (которые не нужны другим)? [да/нет]\033[0m"
        read -r answer
    fi
    
    local backup_file="$OCTO_ROOT/backups/${pkg}_release_$(date +%Y%m%d_%H%M%S).txt"
    pacman -Q "$pkg" > "$backup_file" 2>/dev/null
    
    if [[ "$answer" =~ ^(да|Да|ок|Ок|y|Y|yes|Yes|)$ ]]; then
        echo -e "\033[33m🗑️  Удаляем пакет и зависимости...\033[0m"
        sudo pacman -Rsc "$pkg"
    else
        echo -e "\033[33m🗑️  Удаляем только пакет...\033[0m"
        sudo pacman -R "$pkg"
    fi
    
    if [ $? -eq 0 ]; then
        db_remove_package "$pkg"
        echo -e "\033[32m✅ $pkg освобождён\033[0m"
        echo -e "\033[36m📋 Бэкап: $backup_file\033[0m"
    else
        echo -e "\033[31m❌ Ошибка при освобождении $pkg\033[0m"
    fi
}

clean_cache() {
    echo -e "\033[36m🧹 Очищаем кэш OCTO...\033[0m"
    
    local cache_size=$(du -sh "$OCTO_ROOT/cache" 2>/dev/null | cut -f1 || echo "0")
    echo -e "\033[33m📦 Размер кэша: $cache_size\033[0m"
    
    echo -e "\n\033[33m⚠️  Удалить всё? [да/нет]\033[0m"
    read -r answer
    
    if [[ "$answer" =~ ^(да|Да|ок|Ок|y|Y|yes|Yes|)$ ]]; then
        rm -rf "$OCTO_ROOT/cache"/*
        echo -e "\033[32m✅ Кэш очищен\033[0m"
    else
        echo -e "\033[33m❌ Очистка отменена\033[0m"
    fi
}

clean_backups() {
    echo -e "\033[36m🧹 Очищаем старые бэкапы...\033[0m"
    
    local backup_count=$(ls -1 "$OCTO_ROOT/backups" 2>/dev/null | wc -l)
    echo -e "\033[33m📦 Найдено бэкапов: $backup_count\033[0m"
    
    if [ $backup_count -eq 0 ]; then
        echo -e "\033[33m⚠️  Бэкапов нет\033[0m"
        return 0
    fi
    
    echo -e "\033[33m⚠️  Удалить все бэкапы старше 30 дней? [да/нет]\033[0m"
    read -r answer
    
    if [[ "$answer" =~ ^(да|Да|ок|Ок|y|Y|yes|Yes|)$ ]]; then
        find "$OCTO_ROOT/backups" -type f -mtime +30 -delete
        echo -e "\033[32m✅ Старые бэкапы удалены\033[0m"
    else
        echo -e "\033[33m❌ Очистка отменена\033[0m"
    fi
}

octo_stats() {
    echo -e "\033[36m📊 Статистика OCTO:\033[0m"
    
    local total=$(jq -r '.total' "$PKGS_DB" 2>/dev/null || echo 0)
    local installed_count=$(jq -r '.installed | length' "$PKGS_DB" 2>/dev/null || echo 0)
    local history_count=$(jq -r '.history | length' "$HISTORY_DB" 2>/dev/null || echo 0)
    local backup_count=$(ls -1 "$OCTO_ROOT/backups" 2>/dev/null | wc -l)
    local log_count=$(ls -1 "$OCTO_ROOT/logs" 2>/dev/null | wc -l)
    local cache_size=$(du -sh "$OCTO_ROOT/cache" 2>/dev/null | cut -f1 || echo "0")
    
    echo -e "\033[32m🐙 Поймано пакетов: $total\033[0m"
    echo -e "\033[33m📦 Установлено: $installed_count\033[0m"
    echo -e "\033[36m📜 История операций: $history_count\033[0m"
    echo -e "\033[35m💾 Бэкапов: $backup_count\033[0m"
    echo -e "\033[34m📋 Логов: $log_count\033[0m"
    echo -e "\033[33m🗑️  Размер кэша: $cache_size\033[0m"
    
    echo -e "\n\033[36m📋 Последние операции:\033[0m"
    
    if [ -f "$HISTORY_DB" ] && command -v jq &>/dev/null; then
        local hist_len=$(jq '.history | length' "$HISTORY_DB" 2>/dev/null || echo 0)
        if [ "$hist_len" -gt 0 ] 2>/dev/null; then
            jq -r '.history | last(5)[] | "  \(.time) - \(.action) \(.name) v\(.version)"' "$HISTORY_DB" 2>/dev/null
        else
            echo "  История пуста"
        fi
    else
        echo "  История недоступна"
    fi
}

search_system() {
    local query="$1"
    echo -e "\033[36m🔍 Ищем в системе: $query\033[0m"
    
    pacman -Qs "$query"
}

system_info() {
    local pkg="$1"
    echo -e "\033[36m📋 Информация о $pkg в системе:\033[0m"
    
    if pacman -Qi "$pkg" &>/dev/null; then
        pacman -Qi "$pkg"
    else
        echo -e "\033[31m❌ Пакет не найден в системе\033[0m"
    fi
}

check_updates() {
    echo -e "\033[36m🔄 Проверяем обновления...\033[0m"
    
    local installed=($(db_get_installed | awk '{print $1}'))
    
    if [ ${#installed[@]} -eq 0 ]; then
        echo -e "\033[33m⚠️  Нет установленных AUR-пакетов\033[0m"
        return 0
    fi
    
    echo -e "\033[33m📦 Проверяем ${#installed[@]} пакетов...\033[0m"
    
    for pkg in "${installed[@]}"; do
        local current_version=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
        local latest_version=$(curl -s --max-time 3 "https://aur.archlinux.org/rpc/v5/info?arg=$pkg" 2>/dev/null | jq -r '.results[0].Version' 2>/dev/null)
        
        if [ -n "$current_version" ] && [ -n "$latest_version" ] && [ "$latest_version" != "null" ] && [ "$current_version" != "$latest_version" ]; then
            echo -e "\033[32m⬆️  $pkg: $current_version -> $latest_version\033[0m"
        else
            echo -e "\033[33m✅ $pkg: актуален ($current_version)\033[0m"
        fi
    done
}
