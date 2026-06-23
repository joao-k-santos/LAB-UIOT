# Etapa 1: Puxa a imagem oficial do GoFlow2 para extrair o binário
FROM netsampler/goflow2:latest AS goflow2_source

# Etapa 2: Monta o ambiente de execução com o softflowd
FROM debian:bookworm-slim

# Instala o softflowd e limpa o cache do apt
RUN apt-get update && \
    apt-get install -y softflowd && \
    rm -rf /var/lib/apt/lists/*

# Copia o binário do GoFlow2 da Etapa 1 direto para a pasta de executáveis do sistema
COPY --from=goflow2_source /goflow2 /usr/bin/goflow2

# Copia e configura o script de inicialização
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]