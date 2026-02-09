#!/bin/bash

# ==============================================================================
# NAME: docker_systemctl_supervisor_install.sh (v3.2 - "Management Edition")
# DESCRIPTION: Proxy Systemctl-Supervisor com suporte a listagem e ajuda.
# ==============================================================================

set -e

# --- CORES PARA FEEDBACK ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Marcadores para Edição de Arquivos
MARK_START="### [SYSTEMCTL-PROXY-START] ###"
MARK_END="### [SYSTEMCTL-PROXY-END] ###"

# --- FUNÇÃO DE AJUDA ( /? ) ---
show_help() {
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BLUE}       HELP - PROXY SYSTEMCTL PARA DOCKER           ${NC}"
    echo -e "${BLUE}====================================================${NC}"
    echo -e "Uso: ./docker_systemctl_supervisor_install.sh [comando]"
    echo ""
    echo -e "${YELLOW}Comandos disponíveis:${NC}"
    echo -e "  --list      Lista todos os serviços registrados e seus status."
    echo -e "  --delete    Remove o Proxy e restaura as configurações originais."
    echo -e "  /?          Mostra esta tela de ajuda."
    echo ""
    echo -e "Se nenhum comando for passado, o assistente de instalação será iniciado."
    echo "----------------------------------------------------"
    exit 0
}

# Verificação imediata de ajuda
if [[ "$1" == "/?" || "$1" == "--help" ]]; then show_help; fi

# --- FUNÇÃO DE COLETA INTERATIVA ---
ask_path() {
    local var_name=$1
    local default_path=$2
    local description=$3
    local status=""
    local prompt_val=""

    if [ -e "$default_path" ]; then
        status="${GREEN}(arquivo/diretório encontrado)${NC}"
        prompt_val="$default_path"
    else
        status="${RED}(NÃO encontrado)${NC}"
        prompt_val="" 
    fi

    echo -e "\n--- $description ---"
    read -p "$(echo -e "Caminho sugerido [$prompt_val] $status: ")" user_input

    if [ -z "$user_input" ]; then
        eval "$var_name=\"$default_path\""
    else
        eval "$var_name=\"$user_input\""
    fi
}

# --- COLETA INICIAL DE AMBIENTE ---
echo -e "${BLUE}Configurando ambiente do Proxy...${NC}"
ask_path "MAIN_CONF" "/etc/supervisor/supervisord.conf" "Arquivo MESTRE do Supervisor"
ask_path "SUPERVISOR_CONF_DIR" "/etc/supervisor/conf.d" "Diretório de novas configs (.conf)"
ask_path "REGISTRY_FILE" "/var/log/systemctl_proxy_registry.list" "Arquivo de REGISTRO e Status"
ask_path "SYNC_SCRIPT" "/usr/local/bin/supervisor-sync.sh" "Local do script Sincronizador"
ask_path "PROXY_SYSTEMCTL" "/usr/local/bin/systemctl" "Local do binário PROXY Systemctl"

# --- FUNÇÃO DE LISTAGEM (--list) ---
list_services() {
    if [ ! -f "$REGISTRY_FILE" ]; then
        echo -e "${RED}Erro: Arquivo de registro não encontrado em $REGISTRY_FILE.${NC}"
        echo "O Proxy já foi instalado?"
        exit 1
    fi

    echo -e "\n${BLUE}====================================================${NC}"
    echo -e "${BLUE}      SERVIÇOS GERENCIADOS PELO PROXY              ${NC}"
    echo -e "${BLUE}====================================================${NC}"
    printf "%-20s | %-40s | %-10s\n" "SERVIÇO" "CAMINHO DA UNIDADE" "STATUS"
    echo "--------------------------------------------------------------------------------"

    while IFS='|' read -r service_name unit_path status; do
        if [ "$status" == "active" ]; then
            color=$GREEN
        else
            color=$YELLOW
        fi
        printf "%-20s | %-40s | ${color}%-10s${NC}\n" "$service_name" "$unit_path" "$status"
    done < "$REGISTRY_FILE"
    echo "--------------------------------------------------------------------------------"
    exit 0
}

# --- FUNÇÃO DE DESINSTALAÇÃO (--delete) ---
uninstall() {
    echo -e "${RED}Removendo modificações baseadas nos caminhos informados...${NC}"
    if [ -f "$REGISTRY_FILE" ]; then
        while IFS='|' read -r name path st; do rm -f "$SUPERVISOR_CONF_DIR/$name.conf"; done < "$REGISTRY_FILE"
        rm -f "$REGISTRY_FILE"
    fi
    [ -f "$MAIN_CONF" ] && sed -i "/$MARK_START/,/$MARK_END/d" "$MAIN_CONF"
    rm -f "$SYNC_SCRIPT" "$PROXY_SYSTEMCTL" /bin/systemctl /usr/bin/systemctl
    echo -e "${GREEN}Sistema restaurado.${NC}"
    exit 0
}

# Processamento de flags após coleta de caminhos
if [ "$1" == "--list" ]; then list_services; fi
if [ "$1" == "--delete" ]; then uninstall; fi

# --- RESUMO E INSTALAÇÃO ---
echo -e "\n${YELLOW}CONFIRMAÇÃO DE INSTALAÇÃO:${NC}"
echo "----------------------------------------------------"
echo "Config Supervisor: $MAIN_CONF"
echo "Registro de Apps:  $REGISTRY_FILE"
echo "----------------------------------------------------"
read -p "Deseja proceder com a instalação? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then exit 0; fi

echo -e "${BLUE}Executando instalação...${NC}"

# Garantir Registro
mkdir -p "$(dirname "$REGISTRY_FILE")"
touch "$REGISTRY_FILE" && chmod 666 "$REGISTRY_FILE"

# Ajustar Supervisor Master
if [ -f "$MAIN_CONF" ]; then
    sed -i "s/nodaemon=false/nodaemon=true $MARK_START/" "$MAIN_CONF"
    if ! grep -q "$MARK_START" "$MAIN_CONF"; then
        cat << EOF >> "$MAIN_CONF"

$MARK_START
[include]
files = $SUPERVISOR_CONF_DIR/*.conf
$MARK_END
EOF
    fi
fi

# Criar Sincronizador
cat << EOF > "$SYNC_SCRIPT"
#!/bin/bash
# $MARK_START
# Sincronizador Proxy v3.2
# $MARK_END
REGISTRY_FILE="$REGISTRY_FILE"
SUPERVISOR_CONF_DIR="$SUPERVISOR_CONF_DIR"
M_START="$MARK_START"
M_END="$MARK_END"

get_val() { grep -Po "(?<=^\$1=).*" "\$2" | head -1 | tr -d '"'; }

while IFS='|' read -r service_name unit_path status; do
    if [ "\$status" == "pending" ] && [ -f "\$unit_path" ]; then
        EXEC=\$(get_val "ExecStart" "\$unit_path")
        USER=\$(get_val "User" "\$unit_path")
        {
            echo "\$M_START"
            echo "[program:\$service_name]"
            echo "command=\$EXEC"
            echo "autostart=true"
            echo "autorestart=true"
            [[ -n "\$USER" ]] && echo "user=\$USER"
            echo "\$M_END"
        } > "\$SUPERVISOR_CONF_DIR/\$service_name.conf"
        sed -i "s|\$service_name|\$unit_path|pending|\$service_name|\$unit_path|active|" "\$REGISTRY_FILE"
    fi
done < "\$REGISTRY_FILE"
supervisorctl update
EOF
chmod +x "$SYNC_SCRIPT"

# Criar Proxy Binário
cat << EOF > "$PROXY_SYSTEMCTL"
#!/bin/bash
# $MARK_START
# Proxy Systemctl Binário
# $MARK_END
REGISTRY_FILE="$REGISTRY_FILE"
SYNC_SCRIPT="$SYNC_SCRIPT"
COMMAND=\$1
SERVICE=\$2

case \$COMMAND in
    enable|start)
        [[ \$SERVICE == *".service" ]] && S_NAME=\$(basename \$SERVICE .service) || S_NAME=\$SERVICE
        U_PATH=\$(find /lib/systemd/system /etc/systemd/system -name "\$S_NAME.service" | head -1)
        if [ -n "\$U_PATH" ] && ! grep -q "\$S_NAME" "\$REGISTRY_FILE"; then
            echo "\$S_NAME|\$U_PATH|pending" >> "\$REGISTRY_FILE"
        fi
        bash "\$SYNC_SCRIPT"
        ;;
    stop|disable)
        S_NAME=\$(basename \$SERVICE .service)
        rm -f "$SUPERVISOR_CONF_DIR/\$S_NAME.conf"
        sed -i "/\$S_NAME/d" "\$REGISTRY_FILE"
        supervisorctl update
        ;;
esac
EOF
chmod +x "$PROXY_SYSTEMCTL"
ln -sf "$PROXY_SYSTEMCTL" /bin/systemctl
ln -sf "$PROXY_SYSTEMCTL" /usr/bin/systemctl

# Autodiscovery e Finalização
find /lib/systemd/system /etc/systemd/system -maxdepth 1 -name "*.service" | while read -r unit; do
    NAME=$(basename "$unit" .service)
    if [[ ! "$NAME" =~ (supervisor|systemd|dbus|udev|getty) ]] && ! grep -q "$NAME" "$REGISTRY_FILE"; then
        echo "$NAME|$unit|pending" >> "$REGISTRY_FILE"
    fi
done
bash "$SYNC_SCRIPT"
echo -e "${GREEN}Proxy Systemctl v3.2 instalado e operacional!${NC}"