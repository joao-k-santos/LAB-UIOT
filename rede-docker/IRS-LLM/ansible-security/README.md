# 🛡️ Sistema de Prevenção de Intrusão Baseado em Host (SPIH)

## ✍️ Autor

**João Kleber Magalhães dos Santos**  
*Projeto de Graduação do Curso de Engenharia de Redes de Comunicação*  
**Universidade de Brasília (UnB)**

---

## 📌 Sobre o Projeto

Este projeto implementa um **Sistema de Prevenção de Intrusão Baseado em Host (SPIH)** orquestrado via **Ansible** e ambiente conteinerizado com **Docker Compose**. 

O ecossistema simula um cenário real de segurança cibernética com:
- **Detecção de Ameaças**: **Suricata IDS** capturando tráfego e gerando logs estruturados (`eve.json`).
- **Engenharia de Dados & Logs**: Coletor autônomo baseado em **PySpark** para parsing, enriquecimento e ingestão contínua em banco de dados **PostgreSQL**.
- **Simulação de Ataques (Red Team / Botnet)**: Nó de Comando e Controle (**CNC**) orquestrando uma botnet conteinerizada para realizar ataques de varredura de portas (**Nmap**) e força bruta em SSH (**Hydra**).
- **Orquestrador de Segurança**: Agente centralizador responsável por baixar novas regras geradas por LLM e aplicar políticas dinâmicas de firewall (`nftables`).

---

## 🏗️ Arquitetura da Rede e Containers

O ambiente roda sob uma rede privada em ponte no Docker (`seguranca_net` na sub-rede `172.28.0.0/16`):

| Container | Endereço IP | Função Principal |
| :--- | :--- | :--- |
| **`host_final_1`** | `172.28.0.10` | Servidor-alvo (vítima) com **Suricata IDS**, geração de `eve.json` e ingestão de logs PySpark. |
| **`cnc`** | `172.28.0.100` | Servidor de Comando e Controle (C&C) que executa playbooks Ansible na botnet. |
| **`bot_1` a `bot_5`** | `172.28.0.20` - `172.28.0.60` | Nós da botnet que disparam ataques simultâneos contra a vítima. |
| **`orquestrador`** | `172.28.0.5` | Agente centralizador de regras Ansible, sincronização via API e atualização de firewall. |

---

## 📁 Estrutura do Diretório do Projeto

```
/ansible-security/
│
├── cnc/                                 # Ambiente de Comando e Controle (C&C)
│   ├── dockerfile                       # Imagem base reutilizada pelos bots
│   ├── inventory/bots.yml               # Inventário Ansible da botnet
│   ├── playbooks/                       # Playbooks de simulação de ataques (Nmap, Hydra)
│   └── wordlists/                       # Dicionários de senhas para brute force
│
├── host_final/                          # Servidor-alvo (vítima)
│   ├── dockerfile                       # Imagem com Suricata IDS, PySpark e Java
│   ├── entrypoint.sh                    # Script de inicialização dos sensores
│   ├── scripts/                         # Script de ingestão PySpark e startup Suricata
│   └── spark_log_ingest/                # Agendadores (systemd / cron fallback)
│
├── orquestrador/                        # Nó centralizador de segurança
│   ├── dockerfile                       # Imagem com Ansible, nftables e scripts
│   ├── entrypoint.sh                    # Polling de rede e inicialização
│   ├── playbooks/                       # Playbooks de sincronização e regras
│   └── scripts/                         # Scripts de download e aplicação de regras
│
├── suricata_config/                     # Arquivos de configuração do Suricata IDS
├── logs_suricata/                       # Volume persistente mapeado para os logs eve.json
├── docker-compose.yml                   # Orquestração do ambiente multi-container
├── MANUAL_DE_USO.md                     # Manual detalhado de execução
└── README.md                            # Documentação principal
```

---

## 🚀 Como Executar o Ambiente

### 1. Inicializar os Containers
Na raiz do repositório, execute o Docker Compose:

```bash
docker compose up -d --build
```

### 2. Verificar o Status da Rede
Certifique-se de que todos os containers estão ativos (`Up` / `running`):

```bash
docker compose ps
```

---

## ⚔️ Simulação de Ataques (Botnet)

Os ataques são disparados a partir do container **`cnc`** comandando a botnet via Ansible:

### 🎯 1. Ataque de Varredura de Portas (Port Scan via Nmap)
```bash
docker exec -it cnc ansible-playbook -i /home/bot/inventory/bots.yml /home/bot/playbooks/ataque_portscan.yml
```

### 🔑 2. Ataque de Força Bruta em SSH (Brute-Force via Hydra)
```bash
docker exec -it cnc ansible-playbook -i /home/bot/inventory/bots.yml /home/bot/playbooks/ataque_bruteforce.yml
```

---

## 📊 Coleta de Logs e Validação de Segurança

- **Acompanhar alertas em tempo real no Host Final**:
  ```bash
  docker exec -it host_final_1 tail -f /var/log/suricata/eve.json
  ```

- **Verificar os logs de ingestão do PySpark no PostgreSQL**:
  ```bash
  docker exec -it host_final_1 cat /var/log/suricata_ingest.log
  ```

---

## 🛠️ Solução de Problemas (Troubleshooting)

### 🚨 1. Erro de Quebra de Linha do Windows / CRLF (`exec /entrypoint.sh: no such file or directory`)
- **Causa**: Edição dos arquivos no Windows insere caracteres de retorno de carro `\r\n` (CRLF) nos scripts `.sh`. O Linux tenta executar `#!/bin/bash\r` e falha.
- **Solução**: Os Dockerfiles incluem sanitização nativa com `sed -i 's/\r$//'` em todos os scripts durante a compilação das imagens.

### 🌐 2. Erro de DNS / Timeout no Docker Hub (`i/o timeout` ou `127.0.0.53`)
- **Causa**: Em VMs Linux ou redes restritas/institucionais (`172.16.x.x`), o DNS de loopback ou DNS externo `8.8.8.8` pode ser bloqueado pelo firewall.
- **Solução**:
  ```bash
  sudo cp /run/systemd/resolve/resolv.conf /etc/resolv.conf
  sudo DOCKER_BUILDKIT=0 docker compose up -d --build
  ```

### ⏱️ 3. PySpark Timeout no Download (`ReadTimeoutError`)
- **Solução**: A instalação do PySpark está fixada na versão `pyspark==3.5.1` com `--default-timeout=1000` e `--no-cache-dir`, evitando downloads excessivos da versão 4.x.

### ⚡ 4. Otimização de Recursos da Botnet
- O `docker-compose.yml` compila a imagem do `cnc` **uma única vez** (`cnc_bot_image:latest`) e a compartilha com os 5 bots, economizando processamento e memória RAM na máquina host.

---

## 📌 Contato

**Universidade de Brasília - Engenharia de Redes de Comunicação**  
Caso tenha dúvidas ou sugestões, entre em contato!
