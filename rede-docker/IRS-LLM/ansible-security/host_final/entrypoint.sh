#!/bin/bash
set -e

mkdir -p /var/run/sshd
ssh-keygen -A 2>/dev/null || true

echo "Registrando timer do cron para ingestão de logs de rede..."
bash /opt/spark_log_ingest/setup_ingest_timer.sh || true

echo "Iniciando o cron em segundo plano..."
service cron start || true

echo "Iniciando a captura do suricata..."
bash /opt/scripts/suricata_start.sh &

echo "Iniciando o SSH daemon em primeiro plano..."
exec /usr/sbin/sshd -D
