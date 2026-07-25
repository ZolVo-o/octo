#!/bin/bash

# Модуль сборки OCTO - с прогресс-баром

BUILD_DIR="/tmp/octo-build"

catch_package() {
    local pkg="$1"
    
    if [ -z "$pkg" ]; then
        echo -e "\033[31m🐙 OCTO: Укажи имя пакета для ловли!\033[0m"
        return 1
    fi
    
    show_header "Ловим пакет" "$pkg"
    
    if db_is_installed "$pkg"; then
        local current_version=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
        echo -e "\033[33m⚠️  Пакет $pkg уже установлен (v$current_version)\033[0m"
        echo -e "\n\033[33m⚠️  Переустановить? [да/нет]\033[0m"
        read -r answer
        if [[ ! "$answer" =~ ^(да|Да|ок|Ок|y|Y|yes|Yes|)$ ]]; then
            echo -e "\033[33m❌ Отменено\033[0m"
            return 0
        fi
    fi
    
    local build_id=$(date +%s)_$RANDOM
    local pkg_dir="$BUILD_DIR/$build_id"
    mkdir -p "$pkg_dir"
    
    cd "$pkg_dir"
    
    echo -e "\033[33m⬇️  Тянем щупальца к AUR...\033[0m"
    git clone "https://aur.archlinux.org/$pkg.git" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "\033[31m❌ Пакет не найден в океане AUR\033[0m"
        rm -rf "$pkg_dir"
        return 1
    fi
    
    cd "$pkg"
    
    echo -e "\033[33m📸 Создаём снапшот PKGBUILD...\033[0m"
    cp PKGBUILD "$OCTO_ROOT/backups/${pkg}_$(date +%Y%m%d_%H%M%S).pkgbuild"
    
    echo -e "\033[36m📦 Информация о пакете:\033[0m"
    grep -E "^(pkgname|pkgver|pkgrel|pkgdesc|url)=" PKGBUILD | sed 's/^/  /'
    
    echo -e "\n\033[33m⚠️  Продолжить ловлю? [да/нет]\033[0m"
    echo -e "\033[36m🐙 Ответь: да, ок, y или просто Enter\033[0m"
    read -r answer
    
    if [[ ! "$answer" =~ ^(да|Да|ок|Ок|ok|OK|y|Y|yes|Yes|)$ ]]; then
        echo -e "\033[31m❌ Отпускаем пакет обратно в море\033[0m"
        cd && rm -rf "$pkg_dir"
        return 1
    fi
    
    echo -e "\033[32m🔨 Собираем осьминога...\033[0m"
    
    # Прогресс-бар для сборки
    echo -e "\033[36m📊 Прогресс сборки:\033[0m"
    for i in {1..20}; do
        show_progress_bar $i 20 50 "Сборка"
        sleep 0.1
    done
    echo ""
    
    makepkg -si --noconfirm 2>&1 | tee "$OCTO_ROOT/logs/${pkg}_build.log"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        local version=$(grep "^pkgver=" PKGBUILD | cut -d= -f2)
        
        init_db
        db_add_package "$pkg" "$version"
        
        echo -e "\033[32m✅ $pkg успешно пойман!\033[0m"
        echo -e "\033[36m🐙 Версия: $version, установлен в $(date)\033[0m"
        show_footer "Пакет пойман!"
    else
        echo -e "\033[31m❌ Не удалось собрать $pkg. Смотри лог: $OCTO_ROOT/logs/${pkg}_build.log\033[0m"
    fi
    
    cd && rm -rf "$pkg_dir"
}

release_package() {
    local pkg="$1"
    
    if [ -z "$pkg" ]; then
        echo -e "\033[31m🐙 OCTO: Укажи пакет для освобождения!\033[0m"
        return 1
    fi
    
    show_header "Освобождаем" "$pkg"
    
    if ! db_is_installed "$pkg"; then
        echo -e "\033[31m❌ Пакет $pkg не найден в нашей базе\033[0m"
        return 1
    fi
    
    local backup_file="$OCTO_ROOT/backups/${pkg}_release_$(date +%Y%m%d_%H%M%S).txt"
    pacman -Q "$pkg" > "$backup_file" 2>/dev/null
    
    # Прогресс-бар для удаления
    echo -e "\033[36m📊 Удаление:\033[0m"
    for i in {1..10}; do
        show_progress_bar $i 10 30 "Удаление"
        sleep 0.05
    done
    echo ""
    
    sudo pacman -R "$pkg"
    
    if [ $? -eq 0 ]; then
        db_remove_package "$pkg"
        echo -e "\033[32m✅ $pkg освобождён\033[0m"
        echo -e "\033[36m📋 Бэкап: $backup_file\033[0m"
        show_footer "Пакет освобождён!"
    else
        echo -e "\033[31m❌ Ошибка при освобождении $pkg\033[0m"
    fi
}
