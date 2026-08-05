#!/bin/bash
API_ORQUESTRADOR="http://orquestrador:5000/regras"
REGRAS=$(curl -s $API_ORQUESTRADOR)

if [[ -z "$REGRAS" ]]; then
    echo "Nenhuma regra nova encontrada."
    exit 0
fi

echo "Aplicando regras recebidas..."

echo "$REGRAS" | jq -c '.[]' | while read regra; do
    COMANDO=$(echo $regra | jq -r '.comando')

    if [[ -n "$COMANDO" ]]; then
        echo "Executando comando: $COMANDO"
        
        # Segurança: restringe a execução a comandos aprovados
        if [[ "$COMANDO" =~ ^(iptables|pkill|usermod|chmod|kill|firewall-cmd) ]]; then
            eval "$COMANDO"
        else
            echo "Comando não permitido: $COMANDO"
        fi
    fi
done

echo "Regras aplicadas com sucesso."
