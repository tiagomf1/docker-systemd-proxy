#!/bin/bash

set -e

# --- CORES PARA FEEDBACK ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color


# --- VERIFICAÇÃO UAP (O Programa checa a fundação técnica) ---
if ! command -v supervisorctl &> /dev/null; then
    echo -e "${RED}❌ ERRO: O Supervisor não foi detectado no sistema.${NC}"
    echo -e "${YELLOW}O Administrador deve decidir se deseja instalar o Supervisor para prosseguir.${NC}"
    
    # Verifica se o terminal é interativo (permite perguntas)
    if [ -t 0 ]; then
        read -p "ADMINISTRADOR: Deseja executar [apt-get update && apt-get install -y supervisor]? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo -e "${GREEN}Iniciando instalação técnica...${NC}"
            apt-get update && apt-get install -y supervisor
        else
            echo -e "${RED}Instalação cancelada pelo Administrador.${NC}"
            exit 1
        fi
    else
        # Se for um Dockerfile/Script não interativo, apenas informa o erro e o comando
        echo -e "${BLUE}Necessário Supervisor para prosseguir. Sugestão: apt-get update && apt-get install -y supervisor${NC}"
        exit 1
    fi
fi

# --- CONFIGURAÇÕES E MARCADORES ---
MARK_START="### [SYSTEMCTL-PROXY-START] ###"
MARK_END="### [SYSTEMCTL-PROXY-END] ###"
REGISTRY_FILE="/etc/supervisor/services_registry.txt"
SYNC_SCRIPT="/usr/local/bin/supervisor-sync.sh"
PROXY_SYSTEMCTL="/usr/local/bin/systemctl-proxy"
SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"

# --- FUNÇÃO DE AJUDA ( /? ) ---
show_help() {
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BLUE}       HELP - PROXY SYSTEMCTL PARA DOCKER           ${NC}"
    echo -e "${BLUE}====================================================${NC}"
    echo -e "Uso: ./docker_systemctl_supervisor_install.sh [opção]"
    echo ""
    echo -e "${YELLOW}Opções disponíveis:${NC}"
    echo -e "  --list      Lista todos os serviços registrados e seus status."
    echo -e "  --delete    Remove o Proxy e restaura as configurações originais."
    echo -e "  /?          Mostra esta tela de ajuda."
    echo ""
    echo -e "Sem opções: Inicia a instalação/atualização do Proxy."
    echo -e "${BLUE}====================================================${NC}"
}

# --- LÓGICA DE ARGUMENTOS ---
case "$1" in
    --list)
        if [ -f "$REGISTRY_FILE" ]; then
            echo -e "${GREEN}Serviços Registrados no Proxy:${NC}"
            cat "$REGISTRY_FILE"
        else
            echo "Nenhum serviço registado ainda."
        fi
        exit 0
        ;;
    --delete)
        echo -e "${YELLOW}Removendo Proxy e restaurando systemctl original...${NC}"
        rm -f "$PROXY_SYSTEMCTL" "$SYNC_SCRIPT" "$REGISTRY_FILE"
        ln -sf /bin/systemctl.dist /bin/systemctl || echo "Systemctl original já restaurado."
        echo -e "${GREEN}Proxy removido com sucesso.${NC}"
        exit 0
        ;;
    /\?|--help)
        show_help
        exit 0
        ;;
esac

echo -e "${BLUE}Iniciando Instalação UAP Level...${NC}"

# Criar ficheiro de registo se não existir
touch "$REGISTRY_FILE"

# --- CRIAR MOTOR DE SINCRONIZAÇÃO (supervisor-sync.sh) ---
cat << EOF > "$SYNC_SCRIPT"
#!/bin/bash
# $MARK_START
# Motor de Sincronização UAP
# $MARK_END
REGISTRY_FILE="$REGISTRY_FILE"
SUPERVISOR_CONF_DIR="$SUPERVISOR_CONF_DIR"

while IFS='|' read -r S_NAME U_PATH STATUS; do
    if [ "\$STATUS" == "pending" ]; then
        echo "Gerando config para: \$S_NAME"
        EXEC_CMD=\$(grep "ExecStart=" "\$U_PATH" | sed 's/ExecStart=//')
        
        cat << EOC > "\$SUPERVISOR_CONF_DIR/\$S_NAME.conf"
[program:\$S_NAME]
command=\$EXEC_CMD
autostart=true
autorestart=true
stderr_logfile=/var/log/\$S_NAME.err.log
stdout_logfile=/var/log/\$S_NAME.out.log
EOC
        sed -i "s|^\$S_NAME|\$U_PATH|pending|\$S_NAME|\$U_PATH|active|" "\$REGISTRY_FILE"
    fi
done < "\$REGISTRY_FILE"
supervisorctl update
EOF

chmod +x "$SYNC_SCRIPT"

# --- CRIAR BINÁRIO DO PROXY (systemctl-proxy) ---
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
    status)
        supervisorctl status
        ;;
esac
EOF

chmod +x "$PROXY_SYSTEMCTL"

# Backup do systemctl original e linkagem do proxy
if [ ! -f /bin/systemctl.dist ]; then
    mv /bin/systemctl /bin/systemctl.dist
fi
ln -sf "$PROXY_SYSTEMCTL" /bin/systemctl

echo -e "${GREEN}✅ Instalação Concluída! O Programa está pronto para o Usuário usar.${NC}"
echo -e "${YELLOW}Dica: Use 'systemctl enable seu-serviço' e o Proxy fará o resto.${NC}"