# Dockerfile para host final
FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /home/bot

COPY . /home/bot

# Instala dependências mínimas para receber instruções via Ansible
RUN apt-get update && apt-get install -y \
    ansible \
    openssh-server \
    sudo \
    curl \
    jq \
    sshpass \
    python3 \
    python3-pip \
    python3-apt \
    python3-setuptools \
    iputils-ping \
    rsyslog \
    iptables \
    net-tools \
    systemd \
    cron \
    nmap \
    hydra \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cria o usuário bot com sudo sem senha
RUN useradd -m -s /bin/bash bot && echo "bot:bot" | chpasswd && echo "bot ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Corrigir permissões do diretório temporário (p/ Ansible funcionar)
RUN chmod 1777 /tmp && \
    mkdir -p /home/bot/.ssh && \
    chown -R bot:bot /home/bot && \
    chmod 700 /home/bot

# Configura SSH
RUN mkdir /var/run/sshd
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
