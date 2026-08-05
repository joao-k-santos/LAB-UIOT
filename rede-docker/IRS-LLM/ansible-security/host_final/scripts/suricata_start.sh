#!/bin/bash

# --- YAML 1.1 Header ---
# Suricata Setup Script
# - Verifica se a configuração do Suricata existe e baixa as regras se necessário.
# - Adiciona regras locais e garante que o DNP3 seja desabilitado.
# --- YAML 1.1 Header ---

set -e

# Caminhos
RULES_DIR="/etc/suricata/rules"
CONFIG_PATH="/etc/suricata/suricata.yaml"
LOG_FILE="/var/log/suricata_start.log"

# Interface de rede (você pode mudar aqui ou usar auto-detecção)
INTERFACE="eth0"

# Rede interna
HOME_NET="172.28.0.0/16"
EXTERNAL_NET="!$HOME_NET"

echo "[INFO] Iniciando configuração do Suricata..." | tee -a "$LOG_FILE"

# Verifica se o arquivo de configuração existe, se não, cria com o cabeçalho básico
if [ ! -f "$CONFIG_PATH" ]; then
    echo "[INFO] Arquivo de configuração não encontrado. Criando o suricata.yaml básico..." | tee -a "$LOG_FILE"
    cat <<EOL > "$CONFIG_PATH"
%YAML 1.1
---
# Configuração do Suricata

# Definindo saída do log
outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /var/log/suricata/eve.json
      types:
        - alert
        - flow
        - dns
        - http

# Caminho para as regras
default-rule-path: /etc/suricata/rules

# Arquivos de regras
rule-files:
  - suricata.rules

# Configuração de protocolos da camada de aplicação
app-layer:
  protocols:
    modbus:
      enabled: yes
      detection-enabled: yes
    dnp3:
      enabled: yes
      detection-enabled: yes

# Configuração de af-packet
af-packet:
  - interface: eth0
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

# Variáveis de rede
vars:
  address-groups:
    HOME_NET: "$HOME_NET"
    EXTERNAL_NET: "$EXTERNAL_NET"
  port-groups:
    HTTP_PORTS: "{ 80 443 }"
EOL
    echo "[INFO] Arquivo suricata.yaml criado com sucesso!" | tee -a "$LOG_FILE"
fi

# Verifica se o Suricata já foi configurado anteriormente
if [ ! -f "$RULES_DIR/suricata.rules" ]; then
    echo "[INFO] Regras não encontradas. Baixando as regras do suricata-update..." | tee -a "$LOG_FILE"

    # Atualiza o Suricata e suas fontes de regras com suricata-update
    suricata-update

    # Verifica se o diretório de regras foi criado
    if [ ! -d "$RULES_DIR" ]; then
        echo "[INFO] Diretório de regras não encontrado. Criando..." | tee -a "$LOG_FILE"
        mkdir -p "$RULES_DIR"
    fi

    # Baixa as regras padrão do suricata-update
    echo "[INFO] Baixando as regras padrão..." | tee -a "$LOG_FILE"
    suricata-update --silent

    # Adiciona regras locais ao arquivo de configuração
    echo "[INFO] Adicionando regras locais ao arquivo de configuração..." | tee -a "$LOG_FILE"
    echo 'alert icmp any any -> any any (msg:"Ping detectado"; sid:1000001; rev:1;)' > "$RULES_DIR/local.rules"
    sed -i "/^rule-files:/a \  - local.rules" "$CONFIG_PATH"
else
    echo "[INFO] O Suricata já está configurado, pulando o download das regras..." | tee -a "$LOG_FILE"
fi

# Comenta as regras do DNP3 no arquivo de regras
echo "[INFO] Comentando regras DNP3 no arquivo de regras..." | tee -a "$LOG_FILE"
sed -i '/alert .*dnp3.*(.*)/s/^/#/' "$RULES_DIR/suricata.rules"

# Valida a configuração do Suricata
echo "[INFO] Validando a configuração do Suricata..." | tee -a "$LOG_FILE"
if suricata -T -c "$CONFIG_PATH" -v | tee -a "$LOG_FILE"; then
    echo "[SUCESSO] Validação OK." | tee -a "$LOG_FILE"
else
    echo "[ERRO] Validação falhou." | tee -a "$LOG_FILE"
    exit 1
fi

# Inicia o Suricata
echo "[INFO] Iniciando Suricata como IDS na interface $INTERFACE..." | tee -a "$LOG_FILE"
suricata -c "$CONFIG_PATH" -i "$INTERFACE" -D

echo "[OK] Suricata IDS iniciado!" | tee -a "$LOG_FILE"
