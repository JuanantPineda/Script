#!/usr/bin/env bash
#Autor: Alejandro Herrera Jiménez y Juan Antonio Pineda Amador
#Descripción: Aplicación que recibe como parámetros un dispositivos de bloques un formato de ficheros y un punto de montaje y lo configura para que esté disponible tras reiniciar
#Version: 1.4
#Fecha: 15-05-2024


# Zona de declaracion de variables
# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin color


# Zona de declaracion de variables
# Función de ayuda
mostrar_ayuda() {
    echo -e "${YELLOW}Uso: sudo $0 -d <dispositivo o archivo> -t <formato> -m <punto_de_montaje>${NC}"
    echo "  -d: Dispositivo de bloques, archivo, o dispositivo RAID"
    echo "  -t: Formato de archivos (ej. ext4, ntfs, etc.)"
    echo "  -m: Punto de montaje deseado"
}

# Verificar si el usuario es root
verificar_root() {
    if [ "$UID" -ne 0 ]; then
        echo -e "${RED}Este script debe ejecutarse como root. Ejecute con sudo.${NC}"
        exit 1
    fi
}
vd
# Parsear los argumentos de línea de comandos
parsear_argumentos() {
    while getopts ":d:t:m:" opt; do
        case $opt in
            d) dispositivo=$OPTARG ;;
            t) formato=$OPTARG ;;
            m) punto_de_montaje=$OPTARG ;;
            \?) echo -e "${RED}Opción inválida: -$OPTARG${NC}" >&2
                mostrar_ayuda
                exit 1 ;;
            :) echo -e "${RED}La opción -$OPTARG requiere un argumento.${NC}" >&2
                mostrar_ayuda
                exit 1 ;;
        esac
    done

    if [[ -z $dispositivo || -z $formato || -z $punto_de_montaje ]]; then
        echo -e "${RED}Faltan argumentos.${NC}"
        mostrar_ayuda
        exit 1
    fi
}

# Verificar que el punto de montaje exista
verificar_punto_de_montaje() {
    if [ ! -d "$punto_de_montaje" ]; then
        echo -e "${YELLOW}El punto de montaje $punto_de_montaje no existe. Creándolo...${NC}"
        mkdir -p $punto_de_montaje
    fi
}

# Formatear y montar el dispositivo
formatear_y_montar() {
    dispositivo=$(realpath -q $dispositivo)
    if [[ -z $dispositivo ]]; then
        echo -e "${RED}La ruta del dispositivo $OPTARG no es válida.${NC}"
        exit 1
    fi

    if [ -f "$dispositivo" ]; then
        manejar_dispositivo_bucle
    elif [[ $dispositivo == /dev/md* ]]; then
        manejar_dispositivo_raid
    else
        manejar_dispositivo_bloque
    fi

    mount -a
    echo -e "${GREEN}La configuración se ha completado correctamente.${NC}"
}

# Manejar dispositivo de bucle
manejar_dispositivo_bucle() {
    losetup -f -P $dispositivo
    dispositivo_de_bucle=$(losetup -j $dispositivo | cut -d ":" -f 1)
    if [ -z "$dispositivo_de_bucle" ]; then
        echo -e "${RED}Error al crear el dispositivo de bucle.${NC}"
        exit 1
    fi
    mkfs.$formato $dispositivo_de_bucle
    mount $dispositivo_de_bucle $punto_de_montaje
    configurar_fstab $dispositivo $formato "loop defaults"
}

# Manejar dispositivo RAID
manejar_dispositivo_raid() {
    mkfs.$formato $dispositivo
    mount $dispositivo $punto_de_montaje
    uuid=$(blkid -s UUID -o value $dispositivo)
    if [ -z "$uuid" ]; then
        echo -e "${RED}Error al obtener el UUID del dispositivo RAID.${NC}"
        exit 1
    fi
    configurar_fstab "UUID=$uuid" $formato "defaults"
    mdadm --detail --scan | tee -a /etc/mdadm/mdadm.conf
    update-initramfs -u
}

# Manejar dispositivo de bloques normales
manejar_dispositivo_bloque() {
    mkfs.$formato $dispositivo
    mount $dispositivo $punto_de_montaje
    uuid=$(blkid -s UUID -o value $dispositivo)
    if [ -z "$uuid" ]; then
        echo -e "${RED}Error al obtener el UUID del dispositivo.${NC}"
        exit 1
    fi
    configurar_fstab "UUID=$uuid" $formato "defaults"
}

# Configurar fstab
configurar_fstab() {
    local entrada=$1
    local formato=$2
    local opciones=$3
    if ! grep -q "$entrada" /etc/fstab; then
        echo "$entrada $punto_de_montaje $formato $opciones 0 0" >> /etc/fstab
    else
        echo -e "${YELLOW}El dispositivo ya está configurado en /etc/fstab.${NC}"
    fi
}

# Función principal
main() {
    verificar_root
    parsear_argumentos "$@"
    verificar_punto_de_montaje
    formatear_y_montar
}

# Zona del script
# Llamada a la función principal
main "$@"