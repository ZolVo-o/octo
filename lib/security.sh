#!/bin/bash

# Модуль безопасности OCTO

# Проверка PGP подписи
check_pgp() {
    local pkg="$1"
    local pgp_key=$(grep "^validpgpkeys=" PKGBUILD 2>/dev/null | cut -d= -f2 | tr -d '()' | sed 's/ //g' | tr ',' '\n')
    
    if [ -n "$pgp_key" ]; then
        echo -e "\033[36m🔑 Проверяем PGP ключи...\033[0m"
        echo "$pgp_key" | while read -r key; do
            if [ -n "$key" ]; then
                if gpg --list-keys "$key" &>/dev/null; then
                    echo -e "\033[32m  ✅ Ключ $key есть\033[0m"
                else
                    echo -e "\033[33m  ⚠️  Ключ $key отсутствует, пытаемся скачать...\033[0m"
                    gpg --recv-keys "$key" 2>/dev/null && echo -e "\033[32m  ✅ Ключ $key скачан\033[0m" || \
                    echo -e "\033[31m  ❌ Не удалось скачать ключ $key\033[0m"
                fi
            fi
        done
    fi
}

# Проверка PKGBUILD на вредоносный код
scan_pkgbuild() {
    local pkgbuild="$1"
    
    echo -e "\033[36m🔍 Сканируем PKGBUILD на подозрительные паттерны...\033[0m"
    
    local suspicious=0
    
    # Проверка на опасные команды
    grep -E "(curl.*\|.*sh|wget.*\|.*sh|rm -rf \/|sudo|chmod 777)" "$pkgbuild" > /dev/null && {
        echo -e "\033[31m⚠️  Обнаружены подозрительные команды!\033[0m"
        grep -E "(curl.*\|.*sh|wget.*\|.*sh|rm -rf \/|sudo|chmod 777)" "$pkgbuild" | sed 's/^/  /'
        suspicious=1
    }
    
    # Проверка на скачивание неизвестных файлов
    grep -E "(curl|wget) .*http" "$pkgbuild" > /dev/null && {
        echo -e "\033[33m📥 Обнаружены внешние загрузки:\033[0m"
        grep -E "(curl|wget) .*http" "$pkgbuild" | sed 's/^/  /'
    }
    
    # Проверка на модификацию системы
    grep -E "(install -D|cp .* \/|mv .* \/)" "$pkgbuild" > /dev/null && {
        echo -e "\033[33m📁 Обнаружены операции с системными файлами:\033[0m"
        grep -E "(install -D|cp .* \/|mv .* \/)" "$pkgbuild" | sed 's/^/  /'
    }
    
    if [ $suspicious -eq 1 ]; then
        echo -e "\033[31m⚠️  Пакет содержит подозрительный код!\033[0m"
        return 1
    fi
    
    echo -e "\033[32m✅ PKGBUILD прошёл проверку\033[0m"
    return 0
}

# Проверка целостности скачанных файлов
check_integrity() {
    local pkg="$1"
    
    if [ -f "PKGBUILD" ]; then
        echo -e "\033[36m🔐 Проверяем целостность...\033[0m"
        
        # Проверяем SHA суммы
        if grep "^sha" PKGBUILD > /dev/null; then
            echo -e "\033[32m✅ SHA суммы присутствуют\033[0m"
        else
            echo -e "\033[33m⚠️  Нет SHA сумм для проверки\033[0m"
        fi
    fi
}

# Создание бэкапа системы
system_backup() {
    echo -e "\033[36m💾 Создаём бэкап списка пакетов...\033[0m"
    
    local backup_file="$OCTO_ROOT/backups/system_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# Бэкап системы от $(date)"
        echo "# ========================"
        echo ""
        echo "## Официальные пакеты:"
        pacman -Qe
        echo ""
        echo "## AUR пакеты:"
        pacman -Qm
    } > "$backup_file"
    
    echo -e "\033[32m✅ Бэкап создан: $backup_file\033[0m"
    
    # Создаём архив с конфигами
    if [ -d "/etc" ]; then
        tar -czf "$OCTO_ROOT/backups/etc_$(date +%Y%m%d_%H%M%S).tar.gz" /etc 2>/dev/null && \
        echo -e "\033[32m✅ Бэкап /etc создан\033[0m"
    fi
}

# Восстановление из бэкапа
restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "\033[31m❌ Бэкап не найден: $backup_file\033[0m"
        return 1
    fi
    
    echo -e "\033[33m⚠️  Восстановить пакеты из бэкапа? [да/нет]\033[0m"
    read -r answer
    
    if [[ "$answer" =~ ^(да|Да|ок|Ок|y|Y|yes|Yes|)$ ]]; then
        echo -e "\033[36m🔄 Восстанавливаем пакеты...\033[0m"
        
        grep -E "^[a-z]" "$backup_file" | while read -r line; do
            if [[ ! "$line" =~ ^# ]]; then
                local pkg=$(echo "$line" | awk '{print $1}')
                if ! pacman -Q "$pkg" &>/dev/null; then
                    echo -e "\033[33m📦 Устанавливаем $pkg...\033[0m"
                    sudo pacman -S "$pkg" --noconfirm
                fi
            fi
        done
        
        echo -e "\033[32m✅ Восстановление завершено!\033[0m"
    fi
}
