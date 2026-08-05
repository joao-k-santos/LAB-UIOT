#!/bin/bash
# Baixa as regras da API e envia para os hosts finais

LOG="/var/log/seguranca/enviar_regras.log"
ERR="/var/log/seguranca/enviar_regras.err"
PLAYBOOK="/opt/playbooks/enviar_regras.yml"
INVENTORY="/opt/inventory/hosts.yml"

/usr/local/bin/baixar_regras.sh >> "$LOG" 2>> "$ERR"

if [ $? -eq 0 ]; then
    ansible-playbook -i "$INVENTORY" "$PLAYBOOK" >> "$LOG" 2>> "$ERR"
else
    echo "$(date) - Erro ao baixar regras. Playbook não executado." >> "$ERR"
fi
