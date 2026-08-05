#!/bin/bash
set -e

echo "Aguardando o host_final_1 (172.28.0.10:22) estar pronto..."
until timeout 2 bash -c "</dev/tcp/172.28.0.10/22" 2>/dev/null; do
  echo "Aguardando SSH do host_final_1..."
  sleep 3
done
echo "host_final_1 disponível! Executando Ansible playbook..."

ansible-playbook -i /home/ansible_user/orquestrador/inventory/hosts.yml /home/ansible_user/orquestrador/playbooks/setup_orquestrador.yml || echo "Aviso: Falha no playbook inicial do Ansible, mantendo container ativo."

echo "Aplicando regras de firewall nft..."
nft -f /home/ansible_user/orquestrador/scripts/firewall_config.nft || true

echo "Iniciando cron em primeiro plano..."
exec cron -f