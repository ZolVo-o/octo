#!/bin/bash

# Модуль поиска OCTO - использует AUR API

AUR_API="https://aur.archlinux.org/rpc/v5"

# Поиск с рейтингом
tentacle_search() {
    local query="$1"
    echo -e "\033[36m🐙 Ищем '$query' щупальцами OCTO...\033[0m"
    
    local response=$(curl -s "$AUR_API/search?arg=$query")
    
    # Проверяем наличие jq
    if ! command -v jq &> /dev/null; then
        echo -e "\033[31m❌ Установи jq: sudo pacman -S jq\033[0m"
        return 1
    fi
    
    # Парсим и выводим с рейтингом
    echo "$response" | jq -r '.results[] | 
        "  \u001b[32m" + .Name + "\u001b[0m" + 
        " \u001b[33mv" + .Version + "\u001b[0m" +
        " \u001b[35m★ " + (.Votes | tostring) + "\u001b[0m" +
        "\n    " + .Description +
        "\n    📦 Популярность: " + (.Popularity | tostring) +
        "\n    👤 Мейнтейнер: " + (.Maintainer // "без мейнтейнера") +
        "\n    🔗 " + .URL +
        "\n"'
}

# Информация о пакете
ink_info() {
    local pkg="$1"
    echo -e "\033[34m🦑 Информация о $pkg (чернила OCTO)\033[0m"
    
    local response=$(curl -s "$AUR_API/info?arg=$pkg")
    
    echo "$response" | jq '.results[] | {
        "Имя": .Name,
        "Версия": .Version,
        "Голосов": .Votes,
        "Популярность": .Popularity,
        "Описание": .Description,
        "URL": .URL,
        "Мейнтейнер": .Maintainer,
        "Зависимости": .Depends,
        "Дата создания": .FirstSubmitted | tonumber | strftime("%Y-%m-%d %H:%M:%S"),
        "Последнее обновление": .LastModified | tonumber | strftime("%Y-%m-%d %H:%M:%S")
    }'
}
