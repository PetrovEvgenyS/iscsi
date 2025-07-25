#!/bin/bash

# --- Установка и настройка iSCSI Target без аутентификации ---

# --- Переменные ---
TARGET_IP="10.100.10.1"
INITIATOR_IP="10.100.10.2"
IQN_TARGET="iqn.2024-02.com.example:target"
IQN_INITIATOR="iqn.2024-02.com.example:initiator"

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
    magentaprint "Устанавливаем и настраиваем iSCSI Target на $TARGET_IP"
    dnf install -y targetcli

    targetcli <<EOF
/backstores/block create iscsi_disk /dev/sdb

/iscsi create $IQN_TARGET

/iscsi/$IQN_TARGET/tpg1/portals/ delete ip_address=0.0.0.0 ip_port=3260
/iscsi/$IQN_TARGET/tpg1/portals/ create ip_address=$TARGET_IP ip_port=3260

/iscsi/$IQN_TARGET/tpg1/luns create /backstores/block/iscsi_disk

/iscsi/$IQN_TARGET/tpg1 set attribute authentication=0
/iscsi/$IQN_TARGET/tpg1 set attribute generate_node_acls=1
/iscsi/$IQN_TARGET/tpg1 set attribute cache_dynamic_acls=1
/iscsi/$IQN_TARGET/tpg1 set attribute demo_mode_write_protect=0

saveconfig
exit
EOF

    magentaprint "Настройка firewall."
    firewall-cmd --permanent --add-port=3260/tcp
    firewall-cmd --reload

    systemctl enable --now target

    magentaprint "Настройки iSCSI Target:"
    targetcli ls
    magentaprint "iSCSI Target установлен и настроен успешно."
}


# --- Функция: настройка iSCSI Initiator ---
install_initiator() {
    magentaprint "Устанавливаем и настраиваем iSCSI Initiator на $INITIATOR_IP"
    dnf install -y iscsi-initiator-utils
    magentaprint "InitiatorName=$IQN_INITIATOR" | tee /etc/iscsi/initiatorname.iscsi

    iscsiadm -m discovery -t sendtargets -p $TARGET_IP
    iscsiadm -m node --targetname $IQN_TARGET --portal $TARGET_IP --login

    magentaprint "Просмотр текущих подключенных iSCSI Target:"
    iscsiadm -m session
    magentaprint "Просмотр текущих дисков и разделов:"
    lsblk

    magentaprint "iSCSI Initiator установлен и настроен успешно."
}


if [ "$1" == "target" ]; then
    install_target
elif [ "$1" == "initiator" ]; then
    install_initiator
else
    magentaprint "Использование: $0 {target|initiator}"
    exit 1
fi
