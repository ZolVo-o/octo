#!/bin/bash

# Модуль работы с официальными репозиториями Arch

# Список репозиториев
REPOS=("core" "extra" "community" "multilib")

# Поиск пакета в репозиториях
search_repo() {
    local query="$1"
    echo -e "\033[36m📦 Ищем в официальных репозиториях: $query\033[0m"
    
    for repo in "${REPOS[@]}"; do
        echo -e "\033[33m🔍 $repo:\033[0m"
        pacman -Ss "$query" | grep "^$repo" || echo "  (ничего не найдено)"
    done
}

# Полная информация о пакете из репозитория
repo_info() {
    local pkg="$1"
    echo -e "\033[36m📋 Информация о $pkg из репозиториев:\033[0m"
    pacman -Si "$pkg" 2>/dev/null || echo -e "\033[31m❌ Пакет не найден\033[0m"
}

# Установка из репозитория
install_from_repo() {
    local pkg="$1"
    echo -e "\033[36m📦 Устанавливаем $pkg из официальных репозиториев...\033[0m"
    
    # Проверяем существование пакета
    if ! pacman -Si "$pkg" &>/dev/null; then
        echo -e "\033[31m❌ Пакет $pkg не найден в репозиториях\033[0m"
        return 1
    fi
    
    # Получаем информацию о пакете
    local version=$(pacman -Si "$pkg" | grep "^Версия" | awk '{print $3}')
    local size=$(pacman -Si "$pkg" | grep "^Размер" | awk '{print $3, $4}')
    
    echo -e "\033[36m📦 Найден: $pkg v$version ($size)\033[0m"
    
    echo -e "\033[33m⚠️  Установить? [да/нет]\033[0m"
    read -r answer
    
    if [[ "$answer" =~ ^(да|Да|ок|Ок|y|Y|yes|Yes|)$ ]]; then
        sudo pacman -S "$pkg" --noconfirm
        
        if [ $? -eq 0 ]; then
            # Добавляем в БД OCTO
            init_db
            db_add_package "$pkg" "$version"
            echo -e "\033[32m✅ $pkg установлен!\033[0m"
        else
            echo -e "\033[31m❌ Ошибка установки\033[0m"
        fi
    else
        echo -e "\033[33m❌ Отменено\033[0m"
    fi
}

# Обновление официальных репозиториев
update_repos() {
    echo -e "\033[36m🔄 Обновляем базу официальных репозиториев...\033[0m"
    sudo pacman -Sy
}

# Полное обновление системы
full_system_update() {
    echo -e "\033[36m🔄 Полное обновление системы (pacman + AUR)...\033[0m"
    
    # Обновляем базу
    update_repos
    
    # Обновляем официальные пакеты
    echo -e "\033[33m📦 Обновляем официальные пакеты...\033[0m"
    sudo pacman -Su --noconfirm
    
    # Обновляем AUR пакеты через catch_package
    echo -e "\033[33m🐙 Обновляем AUR пакеты...\033[0m"
    octo_army
    
    echo -e "\033[32m✅ Система полностью обновлена!\033[0m"
}

# Показать отстающие пакеты
show_updates() {
    echo -e "\033[36m📊 Отстающие пакеты:\033[0m"
    
    echo -e "\033[33mОфициальные репозитории:\033[0m"
    pacman -Qu
    
    echo -e "\n\033[33mAUR пакеты:\033[0m"
    check_updates
}

# Сравнение версий пакетов
compare_versions() {
    local pkg="$1"
    
    echo -e "\033[36m🔍 Сравнение версий $pkg:\033[0m"
    
    # Версия из официальных репозиториев
    local repo_version=$(pacman -Si "$pkg" 2>/dev/null | grep "^Версия" | awk '{print $3}')
    
    # Версия из AUR
    local aur_version=$(curl -s "https://aur.archlinux.org/rpc/v5/info?arg=$pkg" | jq -r '.results[0].Version' 2>/dev/null)
    
    # Установленная версия
    local installed_version=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
    
    if [ -n "$repo_version" ]; then
        echo -e "\033[36m📦 Официальный репозиторий: $repo_version\033[0m"
    else
        echo -e "\033[33m📦 Официальный репозиторий: не найден\033[0m"
    fi
    
    if [ -n "$aur_version" ] && [ "$aur_version" != "null" ]; then
        echo -e "\033[35m🐙 AUR: $aur_version\033[0m"
    else
        echo -e "\033[33m🐙 AUR: не найден\033[0m"
    fi
    
    if [ -n "$installed_version" ]; then
        echo -e "\033[32m✅ Установлен: $installed_version\033[0m"
        
        # Сравнение
        if [ "$installed_version" == "$repo_version" ] || [ "$installed_version" == "$aur_version" ]; then
            echo -e "\033[32m✅ Версия актуальна!\033[0m"
        else
            echo -e "\033[33m⚠️  Доступна новая версия!\033[0m"
        fi
    else
        echo -e "\033[33m❌ Не установлен\033[0m"
    fi
}
