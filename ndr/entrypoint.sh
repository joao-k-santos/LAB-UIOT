#!/bin/sh
echo "========================================================"
echo "🚀 [AER] Iniciando Sonda softflowd na interface: $INTERFACE_BORDA"
echo "========================================================"

# Inicia o softflowd forçando a versão NetFlow v9 (-v 9) - 100% compatível com GoFlow2 e Kafka
/usr/sbin/softflowd -d -i $INTERFACE_BORDA -n 127.0.0.1:2055 -v 9 -c /var/run/softflowd.ctl -t maxlife=5 -t expint=2 -t tcp=5 -t udp=5 -t icmp=5 -t general=5 &

echo "========================================================"
if [ "$MODO_TRANSPORTE" = "stdout" ]; then
    echo "🖥️  [AER] Modo DEBUG: Exibindo fluxos v9 apenas no TERMINAL..."
    echo "========================================================"
    exec /goflow2 -listen "netflow://:2055" -format "json" -loglevel "debug"
else
    echo "🌐 [AER] Modo PRODUÇÃO: Enviando fluxos v9 para o Kafka em $KAFKA_BROKER..."
    echo "========================================================"
    exec /goflow2 -listen "netflow://:2055" -format "json" -transport "kafka" -transport.kafka.brokers "$KAFKA_BROKER" -transport.kafka.topic "ipfix-network-flow" -loglevel "debug"
fi