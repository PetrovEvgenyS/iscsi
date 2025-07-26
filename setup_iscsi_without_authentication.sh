#!/bin/bash

# --- Установка и настройка iSCSI Target без аутентификации ---

# --- Переменные ---
TARGET_IP="10.100.10.1"         # IP-адрес сервера iSCSI Target
INITIATOR_IP="10.100.10.2"      # IP-адрес iSCSI Initiator
IQN_TARGET="iqn.2025-07.com.example:target"         # IQN для iSCSI Target
IQN_INITIATOR="iqn.2025-07.com.example:initiator"   # IQN для iSCSI Initiator
BLOCK_DEVICE="/dev/sdb"         # Блочное устройство, используемое iSCSI Target


### ЦВЕТА ###
ESC=$(printf '\033') RESET="${ESC}[0m" MAGENTA="${ESC}[35m" RED="${ESC}[31m" GREEN="${ESC}[32m"

### Функции цветного вывода ###
magentaprint() { echo; printf "${MAGENTA}%s${RESET}\n" "$1"; }
errorprint() { echo; printf "${RED}%s${RESET}\n" "$1"; }
greenprint() { echo; printf "${GREEN}%s${RESET}\n" "$1"; }


# ---------------------------------------------------------------------------------------


# --- Проверка запуска через sudo ---
if [ -z "$SUDO_USER" ]; then
    errorprint "Пожалуйста, запустите скрипт через sudo."
    exit 1
fi

# --- Функция: установка и настройка iSCSI Target ---
install_target() {
    magentaprint "Устанавливаем и настраиваем iSCSI Target на $TARGET_IP:"
    dnf install -y targetcli

    magentaprint "Создание блочного устройства для iSCSI (используется $BLOCK_DEVICE):"
    targetcli /backstores/block create iscsi_disk $BLOCK_DEVICE

    magentaprint "Создание нового iSCSI Target с указанным IQN:"
    targetcli /iscsi create $IQN_TARGET

    magentaprint "Удаление портала по умолчанию (0.0.0.0:3260):"
    targetcli /iscsi/$IQN_TARGET/tpg1/portals/ delete ip_address=0.0.0.0 ip_port=3260

    magentaprint "Создание портала с нужным IP-адресом и портом 3260:"
    targetcli /iscsi/$IQN_TARGET/tpg1/portals/ create ip_address=$TARGET_IP ip_port=3260

    magentaprint "Назначение ранее созданного блочного устройства как LUN для Target:"
    targetcli /iscsi/$IQN_TARGET/tpg1/luns create /backstores/block/iscsi_disk

    magentaprint "Отключение аутентификации для Target (demo mode):"
    targetcli /iscsi/$IQN_TARGET/tpg1 set attribute authentication=0

    magentaprint "Включение автоматической генерации ACL для новых инициаторов:"
    targetcli /iscsi/$IQN_TARGET/tpg1 set attribute generate_node_acls=1

    magentaprint "Включение динамического кэширования ACL:"
    targetcli /iscsi/$IQN_TARGET/tpg1 set attribute cache_dynamic_acls=1

    magentaprint "Разрешение записи в demo mode (без защиты от записи):"
    targetcli /iscsi/$IQN_TARGET/tpg1 set attribute demo_mode_write_protect=0

    magentaprint "Сохранение конфигурации targetcli:"
    targetcli saveconfig

    magentaprint "Настройка firewall:"
    firewall-cmd --permanent --add-port=3260/tcp
    firewall-cmd --reload

    systemctl enable --now target
    systemctl restart target

    magentaprint "Настройки iSCSI Target:"
    targetcli ls
    
    greenprint "iSCSI Target установлен и настроен успешно."
}


# --- Функция: настройка iSCSI Initiator ---
install_initiator() {
    magentaprint "Устанавливаем и настраиваем iSCSI Initiator на $INITIATOR_IP:"
    dnf install -y iscsi-initiator-utils
    systemctl enable --now iscsid

    magentaprint "Настройка IQN Initiator:"
    sed -i "s/^InitiatorName=.*/InitiatorName=$IQN_INITIATOR/" /etc/iscsi/initiatorname.iscsi
    systemctl restart iscsid

    magentaprint "Проверяем доступность к iSCSI Target $IQN_TARGET на $TARGET_IP:"
    iscsiadm -m discovery -t sendtargets -p $TARGET_IP
    
    magentaprint "Подключаемся к iSCSI Target $IQN_TARGET на $TARGET_IP:"
    iscsiadm -m node --targetname $IQN_TARGET --portal $TARGET_IP:3260 --login

    magentaprint "Настройка автоматического подключения к iSCSI Target при загрузке:"
    iscsiadm -m node --targetname $IQN_TARGET --portal $TARGET_IP:3260 --op update -n node.startup -v automatic

    magentaprint "Просмотр текущих подключенных iSCSI Target:"
    iscsiadm -m session

    magentaprint "Проверяем подключенные устройства:"
    lsblk

    greenprint "iSCSI Initiator установлен и настроен успешно."
}



if [ "$1" == "target" ]; then
    install_target
elif [ "$1" == "initiator" ]; then
    install_initiator
else
    magentaprint "Использование: $0 {target|initiator}"
    exit 1
fi
