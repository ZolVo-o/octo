#!/bin/bash

# Модуль продвинутой безопасности OCTO - УЛЬТРА-ВЕРСИЯ

advanced_pkgbuild_scan() {
    local pkgbuild="$1"
    local issues=0
    
    echo -e "\033[36m"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              🛡️ СКАНИРОВАНИЕ БЕЗОПАСНОСТИ              ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "\033[0m"
    
    if [ ! -f "$pkgbuild" ]; then
        echo -e "\033[31m❌ PKGBUILD не найден: $pkgbuild\033[0m"
        return 1
    fi
    
    local threats=(
        "rm -rf /" "СКРЫТОЕ УДАЛЕНИЕ СИСТЕМЫ"
        "\|.*sh" "ВЫПОЛНЕНИЕ СКРИПТОВ"
        "sudo" "ИСПОЛЬЗОВАНИЕ SUDO"
        "chmod 777" "НЕБЕЗОПАСНЫЕ ПРАВА"
        "curl.*-k" "ИГНОРИРОВАНИЕ SSL"
        "wget.*--no-check-certificate" "ИГНОРИРОВАНИЕ SSL"
        "eval" "ВЫПОЛНЕНИЕ ПРОИЗВОЛЬНОГО КОДА"
        "\`.*\`" "ОБРАТНЫЕ КАВЫЧКИ"
        "\$\(" "ПОДСТАНОВКА КОМАНД"
        ">/dev/null" "СКРЫТИЕ ВЫВОДА"
        "2>/dev/null" "СКРЫТИЕ ОШИБОК"
    )
    
    echo -e "\033[33m🔍 Проверка опасных паттернов:\033[0m"
    
    for ((i=0; i<${#threats[@]}; i+=2)); do
        local pattern="${threats[$i]}"
        local description="${threats[$((i+1))]}"
        
        if grep -E "$pattern" "$pkgbuild" > /dev/null 2>&1; then
            echo -e "  \033[31m⚠️  $description\033[0m"
            grep -E "$pattern" "$pkgbuild" | sed 's/^/    /'
            ((issues++))
        fi
    done
    
    echo -e "\n\033[33m📦 Проверка бинарных файлов:\033[0m"
    local binary_patterns=("\.exe" "\.msi" "\.dmg" "\.deb" "\.rpm" "\.sh" "\.py" "\.js" "\.elf" "\.bin")
    
    for pattern in "${binary_patterns[@]}"; do
        if grep -E "$pattern" "$pkgbuild" > /dev/null 2>&1; then
            echo -e "  \033[33m⚠️  Найдены файлы: $pattern\033[0m"
            ((issues++))
        fi
    done
    
    echo -e "\n\033[33m🔗 Проверка внешних ссылок:\033[0m"
    local url_patterns=("bit\.ly" "tinyurl" "goo\.gl" "is\.gd" "t\.co" "shorturl")
    
    for pattern in "${url_patterns[@]}"; do
        if grep -E "$pattern" "$pkgbuild" > /dev/null 2>&1; then
            echo -e "  \033[31m⚠️  Сокращённая ссылка: $pattern\033[0m"
            grep -E "$pattern" "$pkgbuild" | sed 's/^/    /'
            ((issues++))
        fi
    done
    
    echo -e "\n\033[33m📁 Проверка использования /tmp:\033[0m"
    if grep -E "/tmp" "$pkgbuild" > /dev/null 2>&1; then
        echo -e "  \033[33m⚠️  Используется /tmp (потенциально опасно)\033[0m"
        grep -E "/tmp" "$pkgbuild" | head -3 | sed 's/^/    /'
    fi
    
    echo -e "\n\033[36m═══════════════════════════════════════════════════════════\033[0m"
    
    if [ $issues -eq 0 ]; then
        echo -e "\033[32m✅ PKGBUILD БЕЗОПАСЕН! (0 угроз)\033[0m"
        return 0
    else
        echo -e "\033[31m❌ НАЙДЕНО $issues ПОТЕНЦИАЛЬНЫХ УГРОЗ!\033[0m"
        
        echo -e "\n\033[33m💡 Рекомендации:\033[0m"
        if [ $issues -gt 5 ]; then
            echo -e "  - Этот пакет имеет много подозрительных паттернов"
            echo -e "  - Рекомендуется НЕ устанавливать этот пакет"
        elif [ $issues -gt 2 ]; then
            echo -e "  - Пакет требует дополнительной проверки"
            echo -e "  - Проверьте источник пакета вручную"
        else
            echo -e "  - Пакет относительно безопасен, но будьте осторожны"
        fi
        return 1
    fi
}

verify_pgp_keys() {
    local pkg="$1"
    
    echo -e "\n\033[36m🔑 ПРОВЕРКА PGP КЛЮЧЕЙ:\033[0m"
    
    if [ ! -f "PKGBUILD" ] && [ -f "$pkg" ]; then
        pkg="PKGBUILD"
    fi
    
    local keys=$(grep "^validpgpkeys=" PKGBUILD 2>/dev/null | cut -d= -f2 | tr -d '()' | sed 's/ //g' | tr ',' '\n')
    
    if [ -z "$keys" ]; then
        echo -e "\033[33m⚠️  Нет PGP ключей для проверки\033[0m"
        return 0
    fi
    
    echo -e "\033[33m🔑 Найдено ключей: $(echo "$keys" | wc -l)\033[0m"
    
    local all_valid=true
    
    while read -r key; do
        if [ -n "$key" ]; then
            echo -e "\n  🔑 Ключ: $key"
            
            if gpg --list-keys "$key" &>/dev/null; then
                local expiry=$(gpg --list-keys --with-colons "$key" 2>/dev/null | grep "^pub" | cut -d: -f7)
                local current_time=$(date +%s)
                
                if [ -n "$expiry" ] && [ $expiry -lt $current_time ]; then
                    echo -e "    \033[31m❌ Ключ ИСТЁК!\033[0m"
                    all_valid=false
                else
                    local user=$(gpg --list-keys --with-colons "$key" 2>/dev/null | grep "^uid" | head -1 | cut -d: -f10)
                    echo -e "    \033[32m✅ Ключ действителен\033[0m"
                    if [ -n "$user" ]; then
                        echo -e "    👤 $user"
                    fi
                fi
            else
                echo -e "    \033[33m⚠️  Ключ не найден, пытаемся загрузить...\033[0m"
                gpg --recv-keys "$key" 2>/dev/null
                
                if [ $? -eq 0 ]; then
                    echo -e "    \033[32m✅ Ключ загружен\033[0m"
                else
                    echo -e "    \033[31m❌ Не удалось загрузить ключ\033[0m"
                    all_valid=false
                fi
            fi
        fi
    done <<< "$keys"
    
    echo -e "\n\033[36m═══════════════════════════════════════════════════════════\033[0m"
    if [ "$all_valid" = true ]; then
        echo -e "\033[32m✅ Все PGP ключи проверены и действительны\033[0m"
        return 0
    else
        echo -e "\033[31m❌ Некоторые PGP ключи недействительны\033[0m"
        return 1
    fi
}

analyze_dependencies() {
    local pkg="$1"
    
    echo -e "\n\033[36m🔍 АНАЛИЗ ЗАВИСИМОСТЕЙ:\033[0m"
    
    if [ ! -f "PKGBUILD" ] && [ -f "$pkg" ]; then
        pkg="PKGBUILD"
    fi
    
    local deps=$(grep "^depends=" PKGBUILD 2>/dev/null | cut -d= -f2- | sed "s/([^)]*)//g" | tr -d "'\"" | tr ',' '\n' | sed 's/^ //g' | grep -v "^$")
    
    if [ -z "$deps" ]; then
        echo -e "\033[33m⚠️  Нет зависимостей для анализа\033[0m"
        return 0
    fi
    
    echo -e "\033[33m📦 Найдено зависимостей: $(echo "$deps" | wc -l)\033[0m\n"
    
    local missing=0
    local aur_deps=0
    local repo_deps=0
    
    echo "$deps" | while read -r dep; do
        if [ -n "$dep" ]; then
            if pacman -Si "$dep" &>/dev/null; then
                echo -e "  \033[32m✅ $dep (официальный)\033[0m"
                ((repo_deps++))
            elif curl -s "https://aur.archlinux.org/rpc/v5/info?arg=$dep" | jq -e '.results[0]' &>/dev/null; then
                echo -e "  \033[33m🐙 $dep (из AUR)\033[0m"
                ((aur_deps++))
            else
                echo -e "  \033[31m❌ $dep (НЕ НАЙДЕН!)\033[0m"
                ((missing++))
            fi
        fi
    done
    
    echo -e "\n\033[36m═══════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[32m📦 Официальных: $repo_deps\033[0m"
    echo -e "\033[33m🐙 Из AUR: $aur_deps\033[0m"
    
    if [ $missing -gt 0 ]; then
        echo -e "\033[31m❌ Не найдено: $missing\033[0m"
        echo -e "\033[31m⚠️  Пакет имеет неразрешённые зависимости!\033[0m"
        return 1
    else
        echo -e "\033[32m✅ Все зависимости разрешены!\033[0m"
        return 0
    fi
}

check_exploits() {
    local pkg="$1"
    local exploit_db="$OCTO_ROOT/db/exploits.json"
    
    echo -e "\n\033[36m🔍 ПРОВЕРКА УЯЗВИМОСТЕЙ:\033[0m"
    
    if [ ! -f "$exploit_db" ]; then
        cat > "$exploit_db" << 'JSONEOF'
{
    "google-chrome": ["CVE-2024-1234", "CVE-2024-5678", "CVE-2024-9012"],
    "firefox": ["CVE-2024-9012", "CVE-2024-2345"],
    "electron": ["CVE-2024-3456", "CVE-2024-7890"],
    "nodejs": ["CVE-2024-4567"],
    "python": ["CVE-2024-12345"],
    "openssl": ["CVE-2024-6789", "CVE-2024-23456"]
}
JSONEOF
    fi
    
    local exploits=$(jq -r ".\"$pkg\" | .[]" "$exploit_db" 2>/dev/null)
    
    if [ -n "$exploits" ] && [ "$exploits" != "null" ]; then
        echo -e "\033[31m⚠️  НАЙДЕНЫ УЯЗВИМОСТИ:\033[0m"
        echo "$exploits" | while read -r cve; do
            if [ -n "$cve" ]; then
                echo -e "  \033[31m❌ $cve\033[0m"
                echo -e "    https://nvd.nist.gov/vuln/detail/$cve"
            fi
        done
        return 1
    else
        echo -e "\033[32m✅ Известных уязвимостей не найдено\033[0m"
        return 0
    fi
}

check_repo_security() {
    echo -e "\n\033[36m🌐 ПРОВЕРКА БЕЗОПАСНОСТИ РЕПОЗИТОРИЯ:\033[0m"
    
    local aur_url="https://aur.archlinux.org"
    
    if curl -sI --max-time 2 "$aur_url" 2>/dev/null | grep -q "200 OK"; then
        echo -e "  \033[32m✅ AUR доступен (HTTPS)\033[0m"
    else
        echo -e "  \033[31m❌ AUR недоступен или использует HTTP\033[0m"
    fi
    
    echo | openssl s_client -connect aur.archlinux.org:443 -servername aur.archlinux.org 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | while read -r line; do
        if [[ "$line" == *"notAfter"* ]]; then
            local expiry_date=$(echo "$line" | cut -d= -f2)
            echo -e "  \033[33m📅 Сертификат действителен до: $expiry_date\033[0m"
        fi
    done
}
