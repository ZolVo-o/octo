#!/bin/bash

# Модуль производительности OCTO

CACHE_DIR="$OCTO_ROOT/cache"
AUR_CACHE="$CACHE_DIR/aur_cache.json"
CACHE_TTL=300  # 5 минут

init_cache() {
    mkdir -p "$CACHE_DIR"
    if [ ! -f "$AUR_CACHE" ]; then
        echo '{"timestamp": 0, "data": {}}' > "$AUR_CACHE"
    fi
}

fast_aur_search() {
    local query="$1"
    
    if [ -z "$query" ]; then
        echo -e "\033[31m🐙 Укажи запрос для поиска\033[0m"
        return 1
    fi
    
    echo -e "\033[36m🔍 Ищем в AUR: $query\033[0m"
    
    # Проверяем кэш
    local cached=$(get_cached_result "search_$query")
    
    if [ $? -eq 0 ] && [ -n "$cached" ]; then
        echo -e "\033[33m⚡ Используем кэш (${CACHE_TTL}с)\033[0m"
        display_search_results "$cached"
        return 0
    fi
    
    echo -e "\033[33m🌐 Запрашиваем из AUR...\033[0m"
    
    # Используем более быстрый curl с таймаутом
    local start_time=$(date +%s%N)
    local response=$(curl -s --max-time 5 --connect-timeout 3 "https://aur.archlinux.org/rpc/v5/search?arg=$query" 2>/dev/null)
    local end_time=$(date +%s%N)
    
    if [ -z "$response" ] || [[ "$response" == *"error"* ]]; then
        echo -e "\033[31m❌ Ошибка AUR API, пробуем снова...\033[0m"
        response=$(curl -s --max-time 10 --connect-timeout 5 "https://aur.archlinux.org/rpc/v5/search?arg=$query" 2>/dev/null)
    fi
    
    if [ -z "$response" ]; then
        echo -e "\033[31m❌ Не удалось получить ответ от AUR\033[0m"
        echo -e "\033[33m💡 Проверь интернет или попробуй позже\033[0m"
        return 1
    fi
    
    local time_ms=$((($end_time - $start_time) / 1000000))
    echo -e "\033[32m✅ Запрос выполнен за ${time_ms}ms\033[0m"
    
    # Сохраняем в кэш
    save_to_cache "search_$query" "$response"
    
    display_search_results "$response"
}

display_search_results() {
    local response="$1"
    
    if ! command -v jq &> /dev/null; then
        echo -e "\033[31m❌ Установи jq: sudo pacman -S jq\033[0m"
        return 1
    fi
    
    local count=$(echo "$response" | jq -r '.results | length' 2>/dev/null)
    
    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
        echo -e "\033[33m⚠️  Ничего не найдено\033[0m"
        return 0
    fi
    
    echo -e "\033[32m✅ Найдено пакетов: $count\033[0m\n"
    
    # Быстрый вывод с цветами
    echo "$response" | jq -r '.results[] | 
        "  \u001b[32m" + .Name + "\u001b[0m" + 
        " \u001b[33mv" + .Version + "\u001b[0m" +
        " \u001b[35m★ " + (.Votes | tostring) + "\u001b[0m" +
        "\n    " + .Description +
        "\n    📦 Популярность: " + (.Popularity | tostring) +
        "\n"' 2>/dev/null
}

save_to_cache() {
    local key="$1"
    local value="$2"
    local current_time=$(date +%s)
    
    local temp_file=$(mktemp)
    jq --arg key "$key" \
       --arg value "$value" \
       --argjson time "$current_time" \
       '.timestamp = $time | .data[$key] = $value' \
       "$AUR_CACHE" > "$temp_file" 2>/dev/null
    mv "$temp_file" "$AUR_CACHE" 2>/dev/null
}

get_cached_result() {
    local key="$1"
    
    if [ ! -f "$AUR_CACHE" ]; then
        return 1
    fi
    
    local cache_data=$(cat "$AUR_CACHE" 2>/dev/null)
    local cache_time=$(echo "$cache_data" | jq -r '.timestamp' 2>/dev/null)
    local current_time=$(date +%s)
    
    if [ -z "$cache_time" ] || [ "$cache_time" = "null" ]; then
        return 1
    fi
    
    if [ $((current_time - cache_time)) -lt $CACHE_TTL ]; then
        local result=$(echo "$cache_data" | jq -r ".data[\"$key\"]" 2>/dev/null)
        if [ -n "$result" ] && [ "$result" != "null" ] && [ "$result" != "" ]; then
            echo "$result"
            return 0
        fi
    fi
    return 1
}

clean_cache() {
    echo -e "\033[36m🧹 Очищаем кэш OCTO...\033[0m"
    
    local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    local cache_files=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
    
    echo -e "\033[33m📦 Размер кэша: $cache_size ($cache_files файлов)\033[0m"
    
    echo -e "\n\033[33m⚠️  Удалить кэш? [да/нет]\033[0m"
    read -r answer
    
    if [[ "$answer" =~ ^(да|Да|ок|Ок|y|Y|yes|Yes|)$ ]]; then
        rm -rf "$CACHE_DIR"/*
        init_cache
        echo -e "\033[32m✅ Кэш очищен!\033[0m"
    else
        echo -e "\033[33m❌ Отменено\033[0m"
    fi
}

cache_stats() {
    echo -e "\033[36m📊 Статистика кэша:\033[0m"
    
    if [ ! -f "$AUR_CACHE" ]; then
        echo -e "\033[33m⚠️  Кэш не инициализирован\033[0m"
        return 0
    fi
    
    local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    local entries=$(jq '.data | length' "$AUR_CACHE" 2>/dev/null || echo 0)
    local cache_time=$(jq -r '.timestamp' "$AUR_CACHE" 2>/dev/null)
    local current_time=$(date +%s)
    local age=$((current_time - cache_time))
    
    echo -e "\033[33m📦 Размер: $cache_size\033[0m"
    echo -e "\033[33m📄 Записей: $entries\033[0m"
    echo -e "\033[33m⏱️  Возраст: ${age}с (TTL: ${CACHE_TTL}с)\033[0m"
    
    if [ $age -gt $CACHE_TTL ]; then
        echo -e "\033[33m⚠️  Кэш устарел\033[0m"
    else
        local time_left=$((CACHE_TTL - age))
        echo -e "\033[32m✅ Кэш актуален (осталось ${time_left}с)\033[0m"
    fi
}
