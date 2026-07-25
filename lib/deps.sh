#!/bin/bash

# Модуль умного разрешения зависимостей

# Получить все зависимости пакета
get_deps() {
    local pkg="$1"
    local deps_file="$2"
    
    if [ -f "$deps_file" ]; then
        grep "^depends=" "$deps_file" | cut -d= -f2 | tr "'" '"' | jq -r '.[]' 2>/dev/null || \
        grep "^depends=" "$deps_file" | cut -d= -f2 | tr '()' ' ' | sed 's/ //g' | tr ',' '\n'
    fi
}

# Проверить, установлена ли зависимость
is_dep_installed() {
    local dep="$1"
    pacman -Q "$dep" &>/dev/null || return 1
}

# Умная установка с зависимостями
install_with_deps() {
    local pkg="$1"
    
    echo -e "\033[36m🔍 Анализируем зависимости $pkg...\033[0m"
    
    # Создаём временную папку
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1
    
    # Клонируем пакет
    git clone "https://aur.archlinux.org/$pkg.git" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "\033[31m❌ Пакет не найден\033[0m"
        return 1
    fi
    
    cd "$pkg" || return 1
    
    # Получаем список зависимостей
    local deps=$(get_deps "$pkg" "PKGBUILD")
    
    if [ -n "$deps" ]; then
        echo -e "\033[36m📦 Найдены зависимости:\033[0m"
        echo "$deps" | while read -r dep; do
            if [ -n "$dep" ]; then
                if is_dep_installed "$dep"; then
                    echo -e "\033[32m  ✅ $dep (установлен)\033[0m"
                else
                    echo -e "\033[31m  ❌ $dep (не установлен)\033[0m"
                    
                    # Проверяем, есть ли в официальных репозиториях
                    if pacman -Si "$dep" &>/dev/null; then
                        echo -e "\033[33m    📦 Можно установить из репозиториев\033[0m"
                    elif curl -s "https://aur.archlinux.org/rpc/v5/info?arg=$dep" | jq -e '.results[0]' &>/dev/null; then
                        echo -e "\033[35m    🐙 Можно установить из AUR\033[0m"
                    else
                        echo -e "\033[31m    ❌ Зависимость не найдена!\033[0m"
                    fi
                fi
            fi
        done
    fi
    
    cd && rm -rf "$tmp_dir"
    
    echo -e "\n\033[33m⚠️  Установить все зависимости автоматически? [да/нет]\033[0m"
    read -r answer
    
    if [[ "$answer" =~ ^(да|Да|ок|Ок|y|Y|yes|Yes|)$ ]]; then
        echo -e "\033[36m🔧 Устанавливаем зависимости...\033[0m"
        # Используем makepkg для автоматической установки зависимостей
        catch_package "$pkg"
    else
        echo -e "\033[33m❌ Отменено\033[0m"
    fi
}

# Показать дерево зависимостей
show_dep_tree() {
    local pkg="$1"
    local level="$2"
    local prefix=""
    
    if [ -z "$level" ]; then
        level=0
    fi
    
    for ((i=0; i<level; i++)); do
        prefix="$prefix  "
    done
    
    echo "${prefix}📦 $pkg"
    
    # Получаем зависимости из системы
    local deps=$(pacman -Qi "$pkg" 2>/dev/null | grep "^依赖关系" | cut -d: -f2 | tr ',' '\n' | sed 's/^ //g' | grep -v "^$")
    
    if [ -n "$deps" ] && [ $level -lt 3 ]; then
        echo "$deps" | while read -r dep; do
            if [ -n "$dep" ]; then
                local dep_name=$(echo "$dep" | cut -d' ' -f1)
                show_dep_tree "$dep_name" $((level + 1))
            fi
        done
    fi
}
