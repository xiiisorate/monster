#!/bin/bash

# Проверяем наличие команды x-ui
if command -v x-ui &> /dev/null; then
    echo "Обнаружена установленная панель x-ui."

    # Запрос у пользователя на переустановку
    read -p "Вы хотите переустановить x-ui? [y/N]: " confirm
    confirm=${confirm,,}  # перевод в нижний регистр

    if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
        echo "Отмена. Скрипт завершает работу."
        exit 1
    fi

    echo "Удаление x-ui..."
    # Тихое удаление x-ui (если установлен через официальный скрипт)
    /usr/local/x-ui/x-ui uninstall -y &>/dev/null || true
    rm -rf /usr/local/x-ui /etc/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service
    systemctl daemon-reexec
    systemctl daemon-reload
    rm /root/3x-ui.txt
    echo "x-ui успешно удалена. Продолжаем выполнение скрипта..."
fi

# Вывод всех команд кроме диалога — в лог
exec 3>&1  # Сохраняем stdout для сообщений пользователю
LOG_FILE="/var/log/3x-ui_install_log.txt"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Функция генерации случайных строк
gen_random_string() {
    local length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

# === Запрос параметров панели ===
# Используем /dev/tty для прямого доступа к терминалу при read
echo -e "${yellow}Настройка параметров панели управления:${plain}" >&3

# Запрос логина
printf '\033[0;33mВведите логин для панели (Enter для случайного): \033[0m' > /dev/tty
read -r USER_LOGIN < /dev/tty
echo -e "" >&3  # Переход на новую строку
if [[ -z "$USER_LOGIN" ]]; then
    USER_LOGIN=$(gen_random_string 10)
    echo -e "${green}Используется случайный логин: ${USER_LOGIN}${plain}" >&3
else
    echo -e "${green}Логин установлен: ${USER_LOGIN}${plain}" >&3
fi

# Запрос пароля
printf '\033[0;33mВведите пароль для панели (Enter для случайного): \033[0m' > /dev/tty
read -rs USER_PASS < /dev/tty
echo -e "" >&3  # Новая строка после скрытого ввода
if [[ -z "$USER_PASS" ]]; then
    USER_PASS=$(gen_random_string 10)
    echo -e "${green}Используется случайный пароль: ${USER_PASS}${plain}" >&3
else
    echo -e "${green}Пароль установлен${plain}" >&3
fi

# Запрос адреса для панели (IP или домен)
printf '\033[0;33mВведите IP адрес или домен для панели (Enter для автоматического определения): \033[0m' > /dev/tty
read -r PANEL_ADDRESS < /dev/tty
echo -e "" >&3  # Переход на новую строку
if [[ -z "$PANEL_ADDRESS" ]]; then
    PANEL_ADDRESS=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://4.ident.me || echo "127.0.0.1")
    echo -e "${green}Используется автоматически определенный адрес: ${PANEL_ADDRESS}${plain}" >&3
else
    echo -e "${green}Адрес панели установлен: ${PANEL_ADDRESS}${plain}" >&3
fi

# Запрос пути панели (WEBPATH)
printf '\033[0;33mВведите путь для панели (например, XyZ123 или Enter для случайного): \033[0m' > /dev/tty
read -r USER_WEBPATH < /dev/tty
echo -e "" >&3  # Переход на новую строку
if [[ -z "$USER_WEBPATH" ]]; then
    USER_WEBPATH=$(gen_random_string 18)
    echo -e "${green}Используется случайный путь: ${USER_WEBPATH}${plain}" >&3
else
    # Очищаем путь от недопустимых символов (только буквы, цифры и подчеркивания)
    USER_WEBPATH=$(echo "$USER_WEBPATH" | tr -cd 'a-zA-Z0-9_' | head -c 50)
    if [[ -z "$USER_WEBPATH" ]]; then
        USER_WEBPATH=$(gen_random_string 18)
        echo -e "${yellow}Введенный путь был очищен от недопустимых символов. Используется случайный путь: ${USER_WEBPATH}${plain}" >&3
    else
        echo -e "${green}Путь панели установлен: ${USER_WEBPATH}${plain}" >&3
    fi
fi

# === Порт панели: по умолчанию 8080, а при аргументе extend — ручной выбор ===
if [[ "$1" == "--extend" ]]; then
    printf '\033[0;33mВведите порт для панели (Enter для 8080): \033[0m' > /dev/tty
    read -r USER_PORT < /dev/tty
    echo -e "" >&3  # Переход на новую строку
    PORT=${USER_PORT:-8080}

    # === Вопрос о SelfSNI ===
    echo -e "\n${yellow}Хотите установить SelfSNI (поддельный сайт для маскировки)?${plain}" >&3
    printf '\033[0;36mВведите y для установки или нажмите Enter для пропуска: \033[0m' > /dev/tty
    read -r INSTALL_SELFSNI < /dev/tty
    echo -e "" >&3  # Переход на новую строку
    if [[ "$INSTALL_SELFSNI" == "y" || "$INSTALL_SELFSNI" == "Y" ]]; then
        echo -e "${green}Устанавливается SelfSNI...${plain}" >&3
        bash <(curl -Ls https://raw.githubusercontent.com/YukiKras/vless-scripts/refs/heads/main/fakesite.sh)
    else
        echo -e "${yellow}Установка SelfSNI пропущена.${plain}" >&3
    fi
else
    PORT=8080
    echo -e "${yellow}Порт панели: ${PORT}${plain}" >&3
fi

echo -e "\nВесь процесс установки будет сохранён в файле: \033[0;36m${LOG_FILE}\033[0m" >&3
echo -e "\n\033[1;34mИдёт установка... Пожалуйста, не закрывайте терминал.\033[0m"

# Установка переменных
USERNAME="$USER_LOGIN"
PASSWORD="$USER_PASS"
WEBPATH="$USER_WEBPATH"

# Проверка root
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}Ошибка:${plain} скрипт нужно запускать от root" >&3
    exit 1
fi

# Определение ОС
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
else
    echo "Не удалось определить ОС" >&3
    exit 1
fi

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | arm64 | aarch64) echo 'arm64' ;;
        armv7* | arm) echo 'armv7' ;;
        armv6*) echo 'armv6' ;;
        armv5*) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo "unknown" ;;
    esac
}
ARCH=$(arch)

# Установка зависимостей
case "${release}" in
    ubuntu | debian | armbian)
        apt-get update > /dev/null 2>&1
        apt-get install -y -q wget curl tar tzdata jq xxd qrencode > /dev/null 2>&1
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update > /dev/null 2>&1
        yum install -y -q wget curl tar tzdata jq xxd qrencode > /dev/null 2>&1
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update > /dev/null 2>&1
        dnf install -y -q wget curl tar tzdata jq xxd qrencode > /dev/null 2>&1
        ;;
    arch | manjaro | parch)
        pacman -Syu --noconfirm > /dev/null 2>&1
        pacman -S --noconfirm wget curl tar tzdata jq xxd qrencode > /dev/null 2>&1
        ;;
    opensuse-tumbleweed)
        zypper refresh > /dev/null 2>&1
        zypper install -y wget curl tar timezone jq xxd qrencode > /dev/null 2>&1
        ;;
    *)
        apt-get update > /dev/null 2>&1
        apt-get install -y wget curl tar tzdata jq xxd qrencode > /dev/null 2>&1
        ;;
esac

# Установка x-ui
cd /usr/local/ || exit 1
#tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
wget -q -O x-ui-linux-${ARCH}.tar.gz https://github.com/MHSanaei/3x-ui/releases/download/v2.6.7/x-ui-linux-amd64.tar.gz

systemctl stop x-ui 2>/dev/null
rm -rf /usr/local/x-ui/
tar -xzf x-ui-linux-${ARCH}.tar.gz
rm -f x-ui-linux-${ARCH}.tar.gz

cd x-ui || exit 1
chmod +x x-ui
[[ "$ARCH" == armv* ]] && mv bin/xray-linux-${ARCH} bin/xray-linux-arm && chmod +x bin/xray-linux-arm
chmod +x x-ui bin/xray-linux-${ARCH}
cp -f x-ui.service /etc/systemd/system/
wget -q -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
chmod +x /usr/local/x-ui/x-ui.sh /usr/bin/x-ui

# Настройка
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" -webBasePath "$WEBPATH" >>"$LOG_FILE" 2>&1
/usr/local/x-ui/x-ui migrate >>"$LOG_FILE" 2>&1

systemctl daemon-reload >>"$LOG_FILE" 2>&1
systemctl enable x-ui >>"$LOG_FILE" 2>&1
systemctl start x-ui >>"$LOG_FILE" 2>&1

# Генерация Reality ключей
KEYS=$(/usr/local/x-ui/bin/xray-linux-${ARCH} x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep -i "Private" | sed -E 's/.*Key:\s*//')
PUBLIC_KEY=$(echo "$KEYS" | grep -i "Password" | sed -E 's/.*Password:\s*//')
SHORT_ID=$(head -c 8 /dev/urandom | xxd -p)
UUID=$(cat /proc/sys/kernel/random/uuid)
EMAIL=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)

# === Скачивание списка доменов из whitelist ===
WHITELIST_URL="https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/refs/heads/main/whitelist.txt"
WHITELIST_TEMP=$(mktemp)

echo -e "${green}Скачивание списка доменов из whitelist...${plain}" >&3

if curl -s -f "$WHITELIST_URL" -o "$WHITELIST_TEMP"; then
    echo -e "${green}Список доменов успешно скачан.${plain}" >&3
    
    # Парсим домены из файла (разделены пробелами и переносами строк)
    DOMAINS=($(cat "$WHITELIST_TEMP" | tr ' ' '\n' | grep -v '^$' | grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'))
    
    DOMAIN_COUNT=${#DOMAINS[@]}
    echo -e "${green}Найдено доменов: ${DOMAIN_COUNT}${plain}" >&3
    
    if [[ $DOMAIN_COUNT -eq 0 ]]; then
        echo -e "${red}Не удалось распарсить домены. Используем web.max.ru по умолчанию.${plain}" >&3
        DOMAINS=("web.max.ru")
    fi
else
    echo -e "${yellow}Не удалось скачать список доменов. Используем web.max.ru по умолчанию.${plain}" >&3
    DOMAINS=("web.max.ru")
fi

rm -f "$WHITELIST_TEMP"

# === Аутентификация в x-ui API ===
COOKIE_JAR=$(mktemp)

# === Авторизация через cookie ===
LOGIN_RESPONSE=$(curl -s -c "$COOKIE_JAR" -X POST "http://127.0.0.1:${PORT}/${WEBPATH}/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\"}")

if ! echo "$LOGIN_RESPONSE" | grep -q '"success":true'; then
    echo -e "${red}Ошибка авторизации через cookie.${plain}" >&3
    echo "$LOGIN_RESPONSE" >&3
    exit 1
fi

# === Создание одного инбаунда со всеми доменами ===
SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://4.ident.me)

# Генерируем короткий ID для инбаунда
SHORT_ID=$(head -c 8 /dev/urandom | xxd -p)

# Используем первый домен как dest (можно использовать любой)
FIRST_DOMAIN="${DOMAINS[0]}"

echo -e "${green}Создание одного инбаунда со всеми доменами (всего: ${#DOMAINS[@]})...${plain}" >&3
echo -e "${green}Генерация клиентов для каждого домена...${plain}" >&3

# Создаем массив клиентов - по одному на каждый домен
CLIENTS_TEMP=$(mktemp)
DOMAIN_COUNT=0
VLESS_LINKS=()

echo "[]" > "$CLIENTS_TEMP"

for domain in "${DOMAINS[@]}"; do
    # Генерируем уникальные значения для каждого клиента
    CURRENT_UUID=$(cat /proc/sys/kernel/random/uuid)
    CURRENT_EMAIL=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)
    
    # Добавляем клиента в массив через jq
    jq --arg uuid "$CURRENT_UUID" --arg email "${domain}-${CURRENT_EMAIL}" '. += [{
      id: $uuid,
      flow: "xtls-rprx-vision",
      email: $email,
      enable: true
    }]' "$CLIENTS_TEMP" > "${CLIENTS_TEMP}.tmp" && mv "${CLIENTS_TEMP}.tmp" "$CLIENTS_TEMP"
    
    # Формируем VLESS ссылку для этого клиента
    VLESS_LINK="vless://${CURRENT_UUID}@${SERVER_IP}:443?type=tcp&security=reality&encryption=none&flow=xtls-rprx-vision&sni=${domain}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F#${domain}"
    VLESS_LINKS+=("$VLESS_LINK")
    
    DOMAIN_COUNT=$((DOMAIN_COUNT + 1))
    
    if [[ $((DOMAIN_COUNT % 100)) -eq 0 ]] || [[ $DOMAIN_COUNT -eq 1 ]]; then
        echo -e "  ${green}✓${plain} Создан клиент для ${domain} (${DOMAIN_COUNT}/${#DOMAINS[@]})" >&3
    fi
done

CLIENTS_JSON=$(cat "$CLIENTS_TEMP")
rm -f "$CLIENTS_TEMP"

# Формируем массив всех доменов для serverNames через jq
SERVER_NAMES_JSON=$(printf '%s\n' "${DOMAINS[@]}" | jq -R . | jq -s .)

# Формирование JSON для settings со всеми клиентами
SETTINGS_JSON=$(jq -nc --argjson clients "$CLIENTS_JSON" '{
  clients: $clients,
  decryption: "none"
}')

# Формирование JSON для stream settings со всеми serverNames
STREAM_SETTINGS_JSON=$(jq -nc --arg pbk "$PUBLIC_KEY" --arg prk "$PRIVATE_KEY" --arg sid "$SHORT_ID" --arg dest "${FIRST_DOMAIN}:443" --argjson serverNames "$SERVER_NAMES_JSON" '{
  network: "tcp",
  security: "reality",
  realitySettings: {
    show: false,
    dest: $dest,
    xver: 0,
    serverNames: $serverNames,
    privateKey: $prk,
    settings: {publicKey: $pbk},
    shortIds: [$sid]
  }
}')

# Формирование JSON для sniffing
SNIFFING_JSON=$(jq -nc '{
  enabled: true,
  destOverride: ["http", "tls"]
}')

# Отправка инбаунда через API
REMARK="reality443-all-domains-${#DOMAINS[@]}"
echo -e "${green}Отправка инбаунда с ${#DOMAINS[@]} доменами и ${DOMAIN_COUNT} клиентами...${plain}" >&3

ADD_RESULT=$(curl -s -b "$COOKIE_JAR" -X POST "http://127.0.0.1:${PORT}/${WEBPATH}/panel/api/inbounds/add" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc \
    --argjson settings "$SETTINGS_JSON" \
    --argjson stream "$STREAM_SETTINGS_JSON" \
    --argjson sniffing "$SNIFFING_JSON" \
    --arg remark "$REMARK" \
    '{
      enable: true,
      remark: $remark,
      listen: "",
      port: 443,
      protocol: "vless",
      settings: ($settings | tostring),
      streamSettings: ($stream | tostring),
      sniffing: ($sniffing | tostring)
    }')"
)

# Очистка временных cookie
rm -f "$COOKIE_JAR"

# Проверка результата
if echo "$ADD_RESULT" | grep -q '"success":true'; then
    echo -e "${green}✓ Инбаунд успешно создан!${plain}" >&3
    SUCCESS_COUNT=1
    FAILED_COUNT=0
    
    # Сохраняем данные первого домена для примера ссылки
    FIRST_SUCCESS_DOMAIN="${DOMAINS[0]}"
    FIRST_SUCCESS_UUID=$(echo "$CLIENTS_JSON" | jq -r '.[0].id')
    FIRST_SUCCESS_EMAIL=$(echo "$CLIENTS_JSON" | jq -r '.[0].email')
    FIRST_SUCCESS_SHORT_ID="$SHORT_ID"
else
    echo -e "${red}✗ Ошибка при создании инбаунда${plain}" >&3
    ERROR_MSG=$(echo "$ADD_RESULT" | jq -r '.msg // .message // .error // "Неизвестная ошибка"' 2>/dev/null || echo "$ADD_RESULT")
    echo -e "${yellow}Детали ошибки: ${ERROR_MSG}${plain}" >&3
    SUCCESS_COUNT=0
    FAILED_COUNT=1
fi

# Перезапуск x-ui
if [[ $SUCCESS_COUNT -gt 0 ]]; then
    echo -e "${green}Перезапуск x-ui...${plain}" >&3
    systemctl restart x-ui >>"$LOG_FILE" 2>&1
    
    # Выводим информацию о созданном инбаунде
    if [[ -n "$FIRST_SUCCESS_DOMAIN" && ${#VLESS_LINKS[@]} -gt 0 ]]; then
        VLESS_LINK="${VLESS_LINKS[0]}"
        
        echo -e "\n\033[0;32mИнбаунд успешно создан!\033[0m" >&3
        echo -e "\033[1;36mСоздан один инбаунд на порту 443 с ${#DOMAINS[@]} доменами и ${DOMAIN_COUNT} клиентами.${plain}" >&3
        echo -e "\033[1;36mКаждый клиент настроен для работы с конкретным доменом через SNI.${plain}" >&3
        echo -e ""
        echo -e "\033[1;36mПример VLESS ссылки для домена ${FIRST_SUCCESS_DOMAIN}:\033[0m" >&3
        echo -e ""
        echo -e "${VLESS_LINK}" >&3
        echo -e ""
        echo -e "QR код с примером Vless ключа:"
        echo -e ""
        qrencode -t ANSIUTF8 "$VLESS_LINK"
        echo -e ""
        
        # Сохраняем все ссылки в файл
        if [[ ${#VLESS_LINKS[@]} -gt 0 ]]; then
            {
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "ВСЕ VLESS ССЫЛКИ (${#VLESS_LINKS[@]} шт.)"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            } >> /root/3x-ui.txt
            
            for i in "${!VLESS_LINKS[@]}"; do
                echo "${VLESS_LINKS[$i]}" >> /root/3x-ui.txt
            done
            
            echo "" >> /root/3x-ui.txt
            echo "═══════════════════════════════════════════════════════════" >> /root/3x-ui.txt
            echo "" >> /root/3x-ui.txt
            
            echo -e "${green}Все ${#VLESS_LINKS[@]} VLESS ссылок сохранены в /root/3x-ui.txt${plain}" >&3
        fi
        
        echo -e "${yellow}Примечание: Все ссылки для каждого домена доступны в панели управления x-ui.${plain}" >&3
        echo -e ""
        echo -e "С инструкцией по созданию дополнительных Vless ключей вы можете ознакомиться тут: https://wiki.yukikras.net/ru/razvertyvanie-proksi-protokola-vless-s-pomoshyu-3x-ui#как-добавлять-новых-клиентов"
        echo -e ""

        {
        echo "Инбаунд успешно создан!"
        echo "Создан один инбаунд на порту 443 с ${#DOMAINS[@]} доменами и ${DOMAIN_COUNT} клиентами."
        echo "Каждый клиент настроен для работы с конкретным доменом через SNI."
        echo ""
        echo "Пример VLESS ссылки для домена ${FIRST_SUCCESS_DOMAIN}:"
        echo ""
        echo "$VLESS_LINK"
        echo ""
        echo "QR код с примером Vless ключа:"
        echo ""
        qrencode -t ANSIUTF8 "$VLESS_LINK"
        echo ""
        echo "Примечание: Все ссылки для каждого домена доступны в панели управления x-ui."
        echo ""
        echo "С инструкцией по созданию дополнительных Vless ключей вы можете ознакомиться тут: https://wiki.yukikras.net/ru/razvertyvanie-proksi-protokola-vless-s-pomoshyu-3x-ui#как-добавлять-новых-клиентов"
        echo ""
        } >> /root/3x-ui.txt
    else
        echo -e "\n\033[0;32mИнбаунд успешно создан!\033[0m" >&3
        echo -e "\033[1;36mВсе инбаунды используют порт 443 с разными SNI.${plain}" >&3
        echo -e "${yellow}Для получения ссылок используйте панель управления x-ui.${plain}" >&3
    fi
else
    echo -e "${red}Не удалось создать ни одного инбаунда.${plain}" >&3
fi

# === Общая финальная информация (всегда выводится) ===
# SERVER_IP используется для VLESS ссылок (определяется автоматически)
SERVER_IP=${SERVER_IP:-$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://4.ident.me)}

echo -e "\n\033[1;32mПанель управления 3X-UI (https://github.com/MHSanaei/3x-ui) доступна по следующим данным:\033[0m" >&3
echo -e "Адрес панели: \033[1;36mhttp://${PANEL_ADDRESS}:${PORT}/${WEBPATH}\033[0m" >&3
echo -e "Логин:        \033[1;33m${USERNAME}\033[0m" >&3
echo -e "Пароль:       \033[1;33m${PASSWORD}\033[0m" >&3

echo -e "\nИнструкции по настройке VPN приложений вы сможете найти здесь:" >&3
echo -e "\033[1;34mhttps://wiki.yukikras.net/ru/nastroikavpn\033[0m" >&3

echo -e "\nВсе данные сохранены в файл: \033[1;36m/root/3x-ui.txt\033[0m" >&3
echo -e "Для повторного просмотра информации используйте команду:" >&3
echo -e "" >&3
echo -e "\033[0;36mcat /root/3x-ui.txt\033[0m" >&3
echo -e "" >&3

{
  echo "Панель управления 3X-UI (https://github.com/MHSanaei/3x-ui) доступна по следующим данным:"
  echo "Адрес панели - http://${PANEL_ADDRESS}:${PORT}/${WEBPATH}"
  echo "Логин:         ${USERNAME}"
  echo "Пароль:        ${PASSWORD}"
  echo ""
  echo "Инструкции по настройке VPN приложений:"
  echo "https://wiki.yukikras.net/ru/nastroikavpn"
} >> /root/3x-ui.txt
