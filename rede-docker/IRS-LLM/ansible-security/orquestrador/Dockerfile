FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

# Instalar dependências e o Ansible
RUN apt-get update && apt-get install -y \
    ansible \
    systemd \
    sudo \
    curl \
    jq \
    cron \
    logrotate \
    bash \
    sshpass \
    python3-pip \
    python3-apt \
    python3-setuptools \
    python3 \
    rsyslog \
    nano \
    iptables \
    iputils-ping \
    iproute2 \
    net-tools \
    fail2ban \
    nftables \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cria um usuário padrão
RUN useradd -m -s /bin/bash ansible_user && echo "ansible_user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copia arquivos
COPY . /home/ansible_user/orquestrador
RUN sed -i 's/\r$//' /home/ansible_user/orquestrador/entrypoint.sh /home/ansible_user/orquestrador/scripts/*.sh
RUN chmod +x /home/ansible_user/orquestrador/scripts/*.sh
RUN chmod +x /home/ansible_user/orquestrador/entrypoint.sh
RUN mkdir -p /opt/playbooks
RUN cp -r /home/ansible_user/orquestrador/playbooks/* /opt/playbooks/
RUN mkdir -p /opt/inventory
RUN cp -r /home/ansible_user/orquestrador/inventory/* /opt/inventory/
RUN mkdir -p /opt/scripts
RUN cp -r /home/ansible_user/orquestrador/scripts/* /opt/scripts/
# Muda para root e define o comando padrão como cron
USER root
CMD ["./entrypoint.sh"]
