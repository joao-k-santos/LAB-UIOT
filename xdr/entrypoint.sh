#!/bin/bash

# Define a interface de rede padrão como eth0 caso nenhuma seja passada por variável de ambiente
INTERFACE=${INTERFACE_BORDA:-eth0}

echo "========================================================"
echo "🚀 Iniciando Sonda softflowd na interface: ${INTERFACE}"
echo "========================================================"

# Inicializa o softflowd enviando o fluxo IPFIX (v10) para o Vector local
# O softflowd por padrão já se desprende e roda em background (daemon)
softflowd -i "${INTERFACE}" -n 127.0.0.1:2055 -v 10

echo "========================================================"
echo "🔥 Iniciando Transportador Vector no primeiro plano..."
echo "========================================================"

# O comando 'exec' faz com que o Vector assuma o PID 1 do contêiner.
# Se o Vector parar, o contêiner fecha de forma limpa.
exec vector --config /etc/vector/vector.yaml