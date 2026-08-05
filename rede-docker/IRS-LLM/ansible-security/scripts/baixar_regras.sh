#!/bin/bash

API_URL="http://api.llm.local/regras"
TOKEN_FILE="/opt/regras/token.txt"
REGRAS_FILE="/opt/regras/regras.json"

# Gera novo token (ajuste conforme seu endpoint de autenticação)
NOVO_TOKEN=$(curl -s -X POST http://api.llm.local/auth -d '{"usuario":"admin","senha":"123"}' | jq -r .token)

if [[ "$NOVO_TOKEN" != "null" && -n "$NOVO_TOKEN" ]]; then
    echo "$NOVO_TOKEN" > "$TOKEN_FILE"
fi

TOKEN=$(cat "$TOKEN_FILE")

curl -s -H "Authorization: Bearer $TOKEN" "$API_URL" -o "$REGRAS_FILE"
