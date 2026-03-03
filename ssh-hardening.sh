#!/bin/bash

set -e

SSH_MAIN="/etc/ssh/sshd_config"
SSH_DIR="/etc/ssh/sshd_config.d"
BACKUP_MAIN="${SSH_MAIN}.backup_$(date +%F_%T)"
AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"

PARAMS=("PasswordAuthentication" "PubkeyAuthentication" "ChallengeResponseAuthentication" "PermitRootLogin")

echo "== Проверка пользователя =="

if [ "$EUID" -eq 0 ]; then
    echo "❌ Не запускай скрипт от root."
    exit 1
fi

if [ -z "$SSH_CONNECTION" ]; then
    echo "❌ Скрипт должен запускаться из активной SSH-сессии."
    exit 1
fi

echo "== Проверка SSH-ключа =="

if [ ! -f "$AUTHORIZED_KEYS" ] || [ ! -s "$AUTHORIZED_KEYS" ]; then
    echo "❌ SSH ключ не найден или файл пуст."
    exit 1
fi

echo "✔ Ключ найден."

echo "== Создание бэкапа основного файла =="
sudo cp "$SSH_MAIN" "$BACKUP_MAIN"
echo "✔ Бэкап создан: $BACKUP_MAIN"

echo "== Правка $SSH_MAIN =="

sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_MAIN"
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_MAIN"
sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSH_MAIN"
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSH_MAIN"

echo "== Проверка конфликтов в $SSH_DIR =="

if [ -d "$SSH_DIR" ]; then
    for file in "$SSH_DIR"/*.conf; do
        [ -e "$file" ] || continue

        echo "Проверка $file"

        for param in "${PARAMS[@]}"; do
            if sudo grep -qE "^\s*${param}\s+" "$file"; then
                echo "  ⚠ Найдено переопределение $param — комментируем"
                sudo sed -i "s/^\s*\(${param}\s\+.*\)/# DISABLED_BY_HARDENING \1/" "$file"
            fi
        done
    done
fi

echo "== Проверка конфигурации sshd =="

if ! sudo sshd -t; then
    echo "❌ Ошибка конфигурации! Восстановление..."
    sudo cp "$BACKUP_MAIN" "$SSH_MAIN"
    exit 1
fi

echo "== Итоговые параметры =="
sudo sshd -T | grep -E "passwordauthentication|pubkeyauthentication|challengeresponseauthentication|permitrootlogin"

echo "== Перезапуск SSH =="
sudo systemctl restart ssh

echo "================================="
echo "✅ Готово."
echo "Парольный вход отключён."
echo "Root логин запрещён."
echo "Конфликтующие параметры в sshd_config.d закомментированы."
echo "================================="
