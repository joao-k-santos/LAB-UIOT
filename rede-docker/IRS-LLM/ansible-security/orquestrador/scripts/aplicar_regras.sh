#!/bin/bash
set -euo pipefail

REGRAS_FILE="/opt/regras/regras.json"
LOG_FILE="/var/log/aplicar_regras.log"

log_info() {
    echo "[INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERRO] $1" | tee -a "$LOG_FILE" >&2
}

# Verifica se o jq está instalado
if ! command -v jq &>/dev/null; then
    log_error "jq não está instalado. Instale com: apt install jq"
    exit 1
fi

# Verifica se o arquivo existe
if [[ ! -f "$REGRAS_FILE" ]]; then
    log_error "Arquivo de regras não encontrado: $REGRAS_FILE"
    exit 1
fi

# Verifica se o JSON é válido
if ! jq empty "$REGRAS_FILE" 2>/dev/null; then
    log_error "Arquivo JSON inválido: $REGRAS_FILE"
    exit 1
fi

REGRAS=$(cat "$REGRAS_FILE")

log_info "Aplicando regras recebidas..."

echo "$REGRAS" | jq -c '.[]' | while read -r regra; do
    COMANDO=$(echo "$regra" | jq -r '.comando')

    if [[ -n "$COMANDO" ]]; then
        log_info "Executando comando: $COMANDO"

        # Lista de comandos permitidos (início da string)
        if [[ "$COMANDO" =~ ^(nft|iptables|pkill|usermod|chmod|kill|firewall-cmd)[[:space:]] ]]; then
            eval "$COMANDO"
        else
            log_error "Comando não permitido: $COMANDO"
            exit 1
        fi
    fi
done

log_info "Regras aplicadas com sucesso."
