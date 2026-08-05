#!/bin/bash

SERVICE_DIR="/etc/systemd/system"
TARGET_DIR="/opt/spark_log_ingest"
SCRIPT_DIR="/opt/scripts"
CRON_JOB="*/1 * * * * /usr/bin/python3 $SCRIPT_DIR/process_suricata_logs.py >> /var/log/suricata_ingest.log 2>&1"

echo "[INFO] Verificando se systemd está disponível..."
if pidof systemd > /dev/null; then
    echo "[INFO] Systemd encontrado. Registrando serviço e timer..."
    
    cp "$TARGET_DIR/log_ingest.service" "$SERVICE_DIR/"
    cp "$TARGET_DIR/log_ingest.timer" "$SERVICE_DIR/"
    
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable --now log_ingest.timer
    echo "[OK] Timer systemd habilitado."
else
    echo "[WARN] Systemd não disponível. Caindo para fallback com cron."
    
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_DIR/process_suricata_logs.py"; echo "$CRON_JOB") | crontab -
    echo "[OK] Cron configurado com sucesso."
fi
