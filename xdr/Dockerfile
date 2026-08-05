FROM timberio/vector:0.56.0-debian

# Instala o softflowd e limpa os arquivos temporários do apt para reduzir o tamanho da imagem
RUN apt-get update && apt-get install -y softflowd && \
    apt-get clean && rm -rf /var/lib/apt/lists/*


COPY vector.yaml /etc/vector/vector.yaml    

# Copia o script que gerenciará a inicialização dos dois serviços
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
