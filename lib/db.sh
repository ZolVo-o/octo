#!/bin/bash

# Модуль базы данных OCTO
# Используем JSON-файлы для хранения

DB_DIR="$OCTO_ROOT/db"
PKGS_DB="$DB_DIR/packages.json"
HISTORY_DB="$DB_DIR/history.json"

# Инициализация БД
init_db() {
    mkdir -p "$DB_DIR"
    
    if [[ ! -f "$PKGS_DB" ]]; then
        echo '{"installed": [], "total": 0}' > "$PKGS_DB"
    fi
    
    if [[ ! -f "$HISTORY_DB" ]]; then
        echo '{"history": []}' > "$HISTORY_DB"
    fi
}

# Добавить пакет в БД
db_add_package() {
    local name="$1"
    local version="$2"
    local installed_at=$(date -Iseconds)
    
    # Читаем текущую БД
    local temp_db=$(mktemp)
    jq --arg name "$name" \
       --arg version "$version" \
       --arg time "$installed_at" \
       '.installed += [{"name": $name, "version": $version, "installed_at": $time}] | .total += 1' \
       "$PKGS_DB" > "$temp_db"
    
    mv "$temp_db" "$PKGS_DB"
    
    # Добавляем в историю
    local temp_history=$(mktemp)
    jq --arg name "$name" \
       --arg version "$version" \
       --arg action "install" \
       --arg time "$installed_at" \
       '.history += [{"action": $action, "name": $name, "version": $version, "time": $time}]' \
       "$HISTORY_DB" > "$temp_history"
    
    mv "$temp_history" "$HISTORY_DB"
}

# Удалить пакет из БД
db_remove_package() {
    local name="$1"
    local temp_db=$(mktemp)
    
    jq --arg name "$name" \
       '.installed = [.installed[] | select(.name != $name)] | .total -= 1' \
       "$PKGS_DB" > "$temp_db"
    
    mv "$temp_db" "$PKGS_DB"
}

# Получить все установленные пакеты
db_get_installed() {
    jq -r '.installed[] | "\(.name) \(.version)"' "$PKGS_DB"
}

# Проверить, установлен ли пакет
db_is_installed() {
    local name="$1"
    jq --arg name "$name" '.installed[] | select(.name == $name) | .name' "$PKGS_DB" | grep -q .
}
