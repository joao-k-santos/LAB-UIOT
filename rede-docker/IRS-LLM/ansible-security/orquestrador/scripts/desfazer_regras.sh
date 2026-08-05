#!/bin/bash

REGRAS_FILE="/opt/seguranca/regras/regras.json"

if [[ ! -f "$REGRAS_FILE" ]]; then
    echo "Arquivo de regras não encontrado: $REGRAS_FILE"
    exit 1
fi

REGRAS=$(cat "$REGRAS_FILE")

echo "Desfazendo regras recebidas..."

echo "$REGRAS" | jq -c '.[]' | while read regra; do
    COMANDO=$(echo $regra | jq -r '.desfazer')

    if [[ -n "$COMANDO" ]]; then
        echo "Executando comando de reversão: $COMANDO"

        # Lista segura de comandos permitidos
        if [[ "$COMANDO" =~ ^(iptables|pkill|usermod|chmod|kill|firewall-cmd) ]]; then
            eval "$COMANDO"
        else
            echo "Comando não permitido: $COMANDO"
        fi
    fi
done

echo "Regras desfeitas com sucesso."
