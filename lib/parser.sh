#!/bin/bash

# Модуль парсера OCTO - умные команды

# Обновить армию (все пакеты)
octo_army() {
    echo -e "\033[36m🐙 Собираем армию OCTO...\033[0m"
    
    local installed=($(db_get_installed | awk '{print $1}'))
    
    if [ ${#installed[@]} -eq 0 ]; then
        echo -e "\033[33m⚠️  Армия пуста. Никто не пойман!\033[0m"
        return 0
    fi
    
    echo -e "\033[35m🦑 Найдено осьминогов: ${#installed[@]}\033[0m"
    
    for pkg in "${installed[@]}"; do
        echo -e "\n\033[34m▶️  Ловим новую версию $pkg...\033[0m"
        catch_package "$pkg"
    done
    
    echo -e "\033[32m✅ Армия OCTO обновлена!\033[0m"
}

# Список пойманных
octo_shell() {
    echo -e "\033[36m🐚 Пойманные осьминоги:\033[0m"
    
    if command -v jq &> /dev/null; then
        jq -r '.installed[] | 
            "  \u001b[32m" + .name + "\u001b[0m" + 
            " \u001b[33mv" + .version + "\u001b[0m" +
            " \u001b[36m(пойман: " + .installed_at + ")\u001b[0m"' \
            "$PKGS_DB"
    else
        db_get_installed
    fi
}

# Создать бэкап
octo_backup() {
    local backup_name="octo_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    echo -e "\033[36m📦 Создаём бэкап: $backup_name\033[0m"
    
    tar -czf "$OCTO_ROOT/$backup_name" -C "$OCTO_ROOT" db/ backups/
    
    echo -e "\033[32m✅ Бэкап создан: $OCTO_ROOT/$backup_name\033[0m"
}

# Откат
octo_rollback() {
    local version="$1"
    echo -e "\033[33m⏪ Откат к версии $version...\033[0m"
    echo -e "\033[31m⚠️  Функция в разработке (как настоящий осьминог)\033[0m"
}

# Помощь
octo_help() {
    echo -e "\033[36m"
    cat << "HELP"
🐙 OCTO - Осьминожий пакетный менеджер
======================================
Уникальные команды:

  octo catch <пакет>     - Поймать пакет из AUR
  octo release <пакет>   - Отпустить пакет (удалить)
  octo tentacle <запрос> - Поиск щупальцами по AUR
  octo ink <пакет>       - Информация (чернила)
  octo army              - Обновить всю армию
  octo shell             - Показать пойманных
  octo backup            - Создать бэкап всей базы
  octo rollback <ид>     - Откатиться к версии

Примеры:
  octo catch google-chrome
  octo tentacle python
  octo ink neovim
  octo army

Осьминог всегда с тобой! 🐙
HELP
    echo -e "\033[0m"
}
