#!/bin/bash

# Carrega variáveis da API
if [ -f /opt/regras/.env ]; then
  export $(grep -v '^#' /opt/regras/.env | xargs)
fi

TOKEN_FILE="/opt/regras/token.txt"
REGRAS_FILE="/opt/regras/regras.json"

# Obter novo token (ajuste para FastAPI com form-urlencoded)
NOVO_TOKEN=$(curl -s -X POST "$API_URL/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$API_USER&password=$API_PASS" | jq -r .access_token)

if [[ "$NOVO_TOKEN" != "null" && -n "$NOVO_TOKEN" ]]; then
  echo "$NOVO_TOKEN" > "$TOKEN_FILE"
fi

TOKEN=$(cat "$TOKEN_FILE")

# Baixar regras
curl -s -H "Authorization: Bearer $TOKEN" "$API_URL/download_regras?formato=json" -o "$REGRAS_FILE"
if [[ $? -ne 0 ]]; then
  echo "Erro ao baixar regras."
  exit 1
fi
echo "Regras baixadas com sucesso."
