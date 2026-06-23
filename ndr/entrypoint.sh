#!/bin/bash

# Captura as variáveis do docker-compose ou assume os padrões
INTERFACE=${INTERFACE_BORDA:-eth0}
KAFKA_SERVER=${KAFKA_BROKER:-172.16.9.72:9092}
TRANSPORTE=${MODO_TRANSPORTE:-stdout}

echo "========================================================"
echo "🚀 [AER] Iniciando Sonda softflowd na interface: ${INTERFACE}"
echo "========================================================"

# AJUSTE AQUI: Adicionado '-c /var/run/softflowd.ctl' para fixar o arquivo de controle
softflowd -i "${INTERFACE}" -n 127.0.0.1:2055 -v 10 -c /var/run/softflowd.ctl -t general=5 -t maxlife=10 -t tcp.close=1

# Verifica qual modo de transporte foi escolhido
if [ "$TRANSPORTE" = "stdout" ]; then
  echo "========================================================"
  echo "🖥️  [AER] Modo DEBUG: Exibindo fluxos nativamente no TERMINAL..."
  echo "========================================================"
  exec goflow2 -listen="netflow://127.0.0.1:2055"
else
  echo "========================================================"
  echo "🏎️  [AER] Modo PRODUÇÃO: Enviando fluxos para o KAFKA..."
  echo "========================================================"
  exec goflow2 \
    -listen="netflow://127.0.0.1:2055" \
    -transport="kafka" \
    -transport.kafka.brokers="${KAFKA_SERVER}" \
    -transport.kafka.topic="ipfix-network-flow"
fi