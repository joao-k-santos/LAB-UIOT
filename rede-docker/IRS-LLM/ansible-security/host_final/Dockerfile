# Dockerfile para host final com Suricata, Spark e PySpark
FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV SPARK_VERSION=3.5.1
ENV HADOOP_VERSION=3

# Instala dependências
RUN apt-get update && apt-get install -y \
    software-properties-common \
    openssh-server \
    sudo \
    curl \
    jq \
    wget \
    rsyslog \
    iptables \
    net-tools \
    cron \
    iputils-ping \
    nano \
    tcpdump \
    openjdk-11-jdk \
    python3 \
    python3-pip && \
    add-apt-repository ppa:oisf/suricata-stable && \
    apt-get update && \
    apt-get install -y suricata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Instala yq (versão moderna em Go)
RUN wget https://github.com/mikefarah/yq/releases/download/v4.43.1/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

# Instala PySpark (fixado na versão 3.5.1 com timeout estendido para evitar timeout no download)
RUN pip3 install --no-cache-dir --default-timeout=1000 pyspark==3.5.1

# Baixa o driver JDBC do PostgreSQL
RUN mkdir -p /opt/spark/jars
RUN wget -O /opt/spark/jars/postgresql.jar https://jdbc.postgresql.org/download/postgresql-42.7.3.jar

# Cria o usuário ansible com sudo sem senha
RUN useradd -m -s /bin/bash ansible && echo "ansible:ansible" | chpasswd && echo "ansible ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configura SSH
RUN mkdir /var/run/sshd && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

# Cria diretório para logs do cron
RUN touch /var/log/cron.log

# Copia scripts
COPY scripts/* /opt/scripts/
COPY spark_log_ingest/ /opt/spark_log_ingest/
COPY entrypoint.sh /entrypoint.sh

# Permissões e conversão de quebras de linha (CRLF para LF via sed)
RUN sed -i 's/\r$//' /entrypoint.sh /opt/scripts/* /opt/spark_log_ingest/*
RUN chmod +x /opt/spark_log_ingest/setup_ingest_timer.sh
RUN chmod +x /opt/scripts/*
RUN chmod +x /entrypoint.sh

# Variáveis de ambiente do Spark
ENV SPARK_HOME=/opt/spark
ENV PATH="$SPARK_HOME/bin:$PATH"
ENV SPARK_MASTER=local[*]
ENV PYSPARK_SUBMIT_ARGS="--master local[*] pyspark-shell"
ENV PYSPARK_PYTHON=python3
ENV PYSPARK_DRIVER_PYTHON=python3

EXPOSE 22
USER root
# Usa o entrypoint corrigido
ENTRYPOINT ["/entrypoint.sh"]
