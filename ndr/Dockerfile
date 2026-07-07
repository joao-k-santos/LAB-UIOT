# Etapa 1: Construir o goflow2 a partir do código fonte usando Golang no Debian
FROM golang:1.21-bookworm AS builder
RUN go install github.com/netsampler/goflow2/cmd/goflow2@v1.3.6

# Etapa 2: Preparar a imagem final Debian e instalar o softflowd
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y softflowd && rm -rf /var/lib/apt/lists/*

# Copiar o binário compilado do goflow2 da etapa anterior
COPY --from=builder /go/bin/goflow2 /goflow2

# Copiar o script de inicialização
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]