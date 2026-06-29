# 📑 Guia Definitivo: Implantação e Operação do Data Lake Privado UIoT

Este documento consolida o passo a passo completo para implantar, tunelar e operar um ecossistema local standalone de engenharia de dados focado em segurança de rede (VLANs 30 e 40). A stack integra **Garage HQ (S3 Object Storage)**, **Apache Kafka (KRaft)**, **Apache Spark (Cluster Master/Worker)** e **Jupyter Lab (PySpark/ML)**.

---

## 🗺️ 1. Desenho de Arquitetura e Preparação do Servidor

A infraestrutura foi desenhada para rodar em um nó local único (standalone) hospedado sob o hipervisor Proxmox. Os volumes locais do host Linux são amarrados para garantir a persistência dos logs estruturados e dos metadados transacionais.

No terminal SSH do seu servidor (`uiot-dl`), prepare o ambiente limpando resíduos anteriores e forçando as permissões corretas para evitar travas de IO (Input/Output) do banco do Garage, permissões de ID do Kafka e o erro do Docker de criar arquivos de configuração como diretórios:

```bash
# Navegue até o diretório central do ecossistema
cd ~/data-lake

# Resete estruturas corrompidas de metadados transacionais anteriores
sudo docker compose down
sudo rm -rf garage_data kafka_data notebooks garage.toml

# Crie fisicamente os subdiretórios estruturais requisitados pelos contêineres
mkdir -p garage_data/meta garage_data/data notebooks

# Crie o arquivo em branco no host para impedir que o Docker o crie incorretamente como pasta
touch garage.toml

# Conceda privilégios de leitura/escrita para evitar travas no SQLite/LMDB do Garage
sudo chmod -R 777 garage_data

# Atribua a propriedade da pasta ao UID interno exigido pelo processo oficial do Kafka
sudo chown -R 1000:1000 kafka_data
```

---

## ⚙️ 2. Arquivos de Configuração do Ecossistema

Crie ou atualize os dois arquivos estruturais de infraestrutura exatamente dentro do diretório `~/data-lake`. Note que a sintaxe do Garage foi rigorosamente ajustada para satisfazer os requisitos nativos da versão `v0.9.x`.

### A. `garage.toml`

*Nota: Na versão v0.9.x, as propriedades de rede e o modo de replicação precisam obrigatoriamente ser declarados de forma global na raiz do arquivo, mantendo apenas a API S3 encapsulada em bloco.*

```toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"

# Define o funcionamento em nó único standalone local
replication_mode = "none"
compression_level = 2

# Parâmetros globais de rede e chave de pareamento de quórum
rpc_bind_addr = "[::]:3901"
rpc_secret = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
bootstrap_peers = []

# Bloco estruturado obrigatório da API de armazenamento
[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage"
```

### B. `docker-compose.yml`

*Nota: Todos os serviços foram unificados sob a rede comum `datalake_net` com o driver `bridge` para permitir a comunicação local nativa no Ubuntu Server. O broker do Kafka conta com ouvintes duplos isolando a ingestão de borda externa da leitura interna do cluster Spark.*

```yaml
services:
  # --- CAMADA DE ARMAZENAMENTO (STORAGE LAYER) ---
  garage:
    image: dxflrs/garage:v0.9.0
    container_name: garage-s3-storage
    ports:
      - "3900:3900" # API S3
      - "3901:3901" # RPC Interno
    volumes:
      - ./garage_data:/var/lib/garage
      - ./garage.toml:/etc/garage.toml:ro
    command: /garage -c /etc/garage.toml server
    networks:
      - datalake_net
    restart: unless-stopped

  # --- CAMADA DE MENSAGERIA (MENSAGENS/BUFFER) ---
  kafka:
    image: apache/kafka:3.7.0
    container_name: kafka-security-hub
    ports:
      - "9094:9094" # Porta exposta para ingestão dos agentes de borda externos (GoFlow2/Vector)
    environment:
      - KAFKA_NODE_ID=1
      - KAFKA_PROCESS_ROLES=broker,controller
      # INTERNAL para comunicação dentro do Docker, EXTERNAL para fora do servidor, CONTROLLER para o quórum KRaft
      - KAFKA_LISTENERS=INTERNAL://:9092,EXTERNAL://0.0.0.0:9094,CONTROLLER://:9093
      # Rotas de rede anunciadas: Spark consome via 'kafka:9092', Agentes externos enviam via IP do Ubuntu '172.16.9.72:9094'
      - KAFKA_ADVERTISED_LISTENERS=INTERNAL://kafka:9092,EXTERNAL://172.16.9.72:9094
      - KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT
      - KAFKA_INTER_BROKER_LISTENER_NAME=INTERNAL
      - KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093
      - KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER
      - KAFKA_LOG_DIRS=/var/lib/kafka/data
      - KAFKA_CLUSTER_ID=4L62xdw2Rxy2wAF4968gAg
    volumes:
      - kafka_data:/var/lib/kafka/data
    networks:
      - datalake_net
    healthcheck:
      test: ["CMD", "/opt/kafka/bin/kafka-broker-api-versions.sh", "--bootstrap-server", "localhost:9092"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s
    restart: unless-stopped

  # --- AUTOMAÇÃO: CRIAÇÃO DOS TÓPICOS ON-STARTUP ---
  kafka-init:
    image: apache/kafka:3.7.0
    depends_on:
      kafka:
        condition: service_healthy
    networks:
      - datalake_net
    entrypoint:
      - "bash"
      - "-c"
      - "/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic ipfix-network-flow --partitions 3 --replication-factor 1 --bootstrap-server kafka:9092 && echo '🚀 Tópicos provisionados com sucesso!'"

  # --- CAMADA DE PROCESSAMENTO (DISTRIBUÍDO) ---
  spark-master:
    image: apache/spark:3.5.1
    container_name: spark-master
    environment:
      - SPARK_MODE=master
    ports:
      - "8080:8080" # Web UI
      - "7077:7077" # Comunicação interna
    command: /opt/spark/bin/spark-class org.apache.spark.deploy.master.Master
    networks:
      - datalake_net
    restart: unless-stopped

  spark-worker:
    image: apache/spark:3.5.1
    container_name: spark-worker-1
    depends_on:
      - spark-master
    environment:
      - SPARK_MODE=worker
    command: /opt/spark/bin/spark-class org.apache.spark.deploy.worker.Worker spark://spark-master:7077
    networks:
      - datalake_net
    restart: unless-stopped

  # --- AMBIENTE DE DESENVOLVIMENTO (PYTHON/ML) ---
  pyspark-notebook:
    image: jupyter/pyspark-notebook:latest
    container_name: pyspark-lab
    ports:
      - "8888:8888"
    environment:
      - JUPYTER_ENABLE_LAB=yes
    volumes:
      - ./notebooks:/home/jovyan/work
    networks:
      - datalake_net
    restart: unless-stopped

networks:
  datalake_net:
    driver: bridge

volumes:
  kafka_data:
```

Suba os serviços executando o comando abaixo:

```bash
sudo docker compose up -d
```

---

## 🔒 3. Mapeamento de Rede e Contorno do Bloqueio da VPN

Como restrições e firewalls intermediários da VPN barram acessos TCP diretos às portas altas (`8888`, `8080`) no IP de destino `172.16.9.72`, utilizamos uma máquina ponte na rede local como salto automatizado (ProxyJump) acoplado a um redirecionamento de portas local (Port Forwarding).

1. No seu **computador pessoal (máquina física local)**, abra ou recrie o arquivo de configuração de SSH:
```bash
nano ~/.ssh/config
```

2. Cole a seguinte estrutura de salto transparente:
```text
Host ponte
    HostName IP_DA_SUA_MAQUINA_PONTE_AQUI
    User SEU_USUARIO_DA_PONTE

Host uiot-dl
    HostName 172.16.9.72
    User uiot
    ProxyJump ponte
```

3. Ajuste as permissões do arquivo para satisfazer a política estrita de segurança do OpenSSH:
```bash
chmod 600 ~/.ssh/config
```

4. Dispare o comando para trazer as interfaces web do Jupyter Lab e do Spark Master criptografadas para o seu navegador:
```bash
ssh -L 8888:localhost:8888 -L 8080:localhost:8080 uiot-dl
```

*Mantenha essa sessão ativa. Para encerrar o túnel e liberar as portas do seu computador físico mais tarde, basta fechar esse terminal ou digitar `exit`.*

---

## 🔑 4. Inicialização Lógica do Object Storage (Garage CLI)

Com os contêineres ativos, faça o provisionamento interno do espaço de disco. Como o binário do Garage não reside no `$PATH` tradicional do contêiner, invocamos o caminho absoluto (`/garage`):

```bash
# 1. Vincule o nó gerado (ID: 268d7de94a6e4690) alocando 15GB de cota na zona local
sudo docker compose exec garage /garage layout assign 268d7de94a6e4690 --capacity 15G --zone local

# 2. Confirme o mapeamento instanciando as 256 partições lógicas no cluster
sudo docker compose exec garage /garage layout apply --version 1

# 3. Gere as credenciais S3 (Copie o Key ID e o Secret Key impressos na tela!)
sudo docker compose exec garage /garage key create minha-chave

# 4. Instancie o bucket central que hospedará os logs colunares
sudo docker compose exec garage /garage bucket create meu-data-lake

# 5. Conceda permissão total de Leitura (Read) e Escrita (Write) da chave sobre o bucket
sudo docker compose exec garage /garage bucket allow meu-data-lake --read --write --key minha-chave
```

---

## 🛠️ 5. Administração Manual de Tópicos no Kafka (CLI)

Embora o contêiner `kafka-init` automatize a criação do pipeline principal, você pode gerenciar, auditar e criar tópicos adicionais manualmente de dentro do broker usando o caminho completo dos scripts.

### A. Listar todos os tópicos ativos do cluster
```bash
sudo docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

### B. Criar um novo tópico customizado
```bash
# Altere o '--topic' para o nome desejado. Recomendado usar 3 partições para paralelismo do Spark.
sudo docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --create --topic ipfix-network-flow --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092
```

### C. Descrever detalhes e partições de um tópico específico
```bash
sudo docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --describe --topic ipfix-network-flow --bootstrap-server localhost:9092
```

---

## 📓 6. Construção do Pipeline e Gerenciamento do `.env` no Jupyter

Abra o seu navegador web local no endereço `http://localhost:8888` e insira o token de segurança obtido através dos logs do contêiner (`sudo docker compose logs pyspark-notebook`).

Abra um notebook Python 3 em branco e execute as células organizadas sequencialmente a seguir:

### Célula 1: Instalação do Gerenciador de Ambiente
```python
!pip install python-dotenv
```

### Célula 2: Geração Automatizada e Oculta do Arquivo `.env`
```python
%%writefile .env
minha_chave=GKe752e73e675cc700c0eb72f3
secret_key=COLE_AQUI_O_SECRET_KEY_INTEIRO_EXIBIDO_PELO_GARAGE
```

### Célula 3: Boot da Sessão Spark e Tuning Hadoop S3A para o Garage
*Esta célula inclui parâmetros estritos de otimização de commits (`algorithm.version=2` e `directory.marker.retention=keep`) que eliminam os loops lentos de requisições de deleção, tornando as escritas locais no Garage instantâneas.*

```python
import os
from dotenv import load_dotenv
from pyspark.sql import SparkSession

# Carrega na memória as variáveis declaradas no arquivo oculto
load_dotenv()
access_key = os.getenv('minha_chave')
secret_key = os.getenv('secret_key')

# Instancia a sessão do Spark injetando dinamicamente os pacotes do Kafka e S3A AWS Hadoop
spark = SparkSession.builder \
    .appName("Security-DataLake-Pipeline") \
    .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1,org.apache.hadoop:hadoop-aws:3.3.4") \
    .getOrCreate()

# Configuração detalhada do driver de mapeamento de objetos para o endpoint do Garage
sc = spark.sparkContext
sc._jsc.hadoopConfiguration().set("fs.s3a.access.key", access_key)
sc._jsc.hadoopConfiguration().set("fs.s3a.secret.key", secret_key)
sc._jsc.hadoopConfiguration().set("fs.s3a.endpoint", "http://garage:3900")
sc._jsc.hadoopConfiguration().set("fs.s3a.path.style.access", "true")
sc._jsc.hadoopConfiguration().set("fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
sc._jsc.hadoopConfiguration().set("fs.s3a.connection.ssl.enabled", "false")

# Parâmetros de compatibilidade regional do Garage
sc._jsc.hadoopConfiguration().set("fs.s3a.endpoint.region", "garage")
sc._jsc.hadoopConfiguration().set("fs.s3a.region", "garage")
sc._jsc.hadoopConfiguration().set("fs.s3a.change.detection.mode", "none")
sc._jsc.hadoopConfiguration().set("fs.s3a.change.detection.source", "none")

# ⚡ TUNING DE PERFORMANCE: ACELERAÇÃO DE ESCRITA NO OBJECT STORAGE LOCAL
sc._jsc.hadoopConfiguration().set("mapreduce.fileoutputcommitter.algorithm.version", "2")
sc._jsc.hadoopConfiguration().set("fs.s3a.directory.marker.retention", "keep")
sc._jsc.hadoopConfiguration().set("fs.s3a.fast.upload", "true")
sc._jsc.hadoopConfiguration().set("fs.s3a.fast.upload.buffer", "disk")

print("🚀 Sessão Spark tunada e otimizada para o Garage HQ!")
```

### Célula 4: Teste de Escrita e Leitura Estática (Validação S3A)
```python
dados_teste = [
    ("VLAN_30", "192.168.30.99", "Mirai Port Scan Detectado", "ALTA"),
    ("VLAN_40", "192.168.40.12", "Tentativa Bruteforce SSH", "MEDIA")
]
colunas = ["origem_vlan", "ip_origem", "evento", "severidade"]
df_teste = spark.createDataFrame(dados_teste, schema=colunas)

try:
    df_teste.write.format("parquet").mode("overwrite").save("s3a://meu-data-lake/teste_alertas/")
    print("✨ Sucesso! O Spark conseguiu autenticar, gravar e fechar pacotes no Garage HQ.")
    spark.read.parquet("s3a://meu-data-lake/teste_alertas/").show()
except Exception as e:
    print(f"❌ Falha crítica de privilégio ou IO no Object Storage: {e}")
```

### Célula 5: Ativação do Pipeline de Streaming Estruturado (Background Job)
*Nota: Definido `"startingOffsets": "earliest"` para garantir que toda mensagem inserida no Kafka seja processada, mesmo que o pipeline tenha sido iniciado após o envio.*

```python
from pyspark.sql.functions import col, from_json, current_timestamp
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

# Mapeamento do Schema padronizado (Formato NetFlow/IPFIX estruturado)
log_schema = StructType([
    StructField("vlan", IntegerType(), True),
    StructField("src_ip", StringType(), True),
    StructField("dst_ip", StringType(), True),
    StructField("dst_port", IntegerType(), True),
    StructField("packets", IntegerType(), True),
    StructField("bytes", IntegerType(), True)
])

# Conexão de streaming contínuo ao cluster interno do Kafka na escuta interna
df_kafka = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka:9092") \
    .option("subscribe", "ipfix-network-flow") \
    .option("startingOffsets", "earliest") \
    .load()

# Conversão do binário de carga do Kafka em dados tipados estruturados
df_parsed = df_kafka.selectExpr("CAST(value AS STRING) as json_payload") \
    .select(from_json(col("json_payload"), log_schema).alias("data")) \
    .select("data.*") \
    .withColumn("ingestion_time", current_timestamp())

# Escrita incremental contínua salvando de forma otimizada e particionada por VLAN no Garage
query = df_parsed.writeStream \
    .format("parquet") \
    .outputMode("append") \
    .option("path", "s3a://meu-data-lake/live_network_logs/") \
    .option("checkpointLocation", "s3a://meu-data-lake/checkpoints/logs_pipeline/") \
    .partitionBy("vlan") \
    .start()

print("🔥 Pipeline de streaming em tempo real ativado em segundo plano!")
```

### Célula 6: Interrogação e Auditoria de Métricas do Stream
*Como o streaming roda de forma assíncrona, execute esta célula para auditar a saúde da thread e verificar em tempo real quantas linhas o Spark consumiu e descarregou por segundo.*

```python
import json

# 1. Valida se a thread de background continua em execução ativa
print(f"O streaming está ativo? {query.isActive}")

# 2. Exibe o relatório detalhado de telemetria do micro-batch
if query.lastProgress:
    print(json.dumps(query.lastProgress, indent=2))
else:
    print("Aguardando a entrada da primeira mensagem para gerar telemetria...")
```

---

## 🛰️ 7. Simulação de Ameaça e Verificação de Dados Streamados

Para validar o fluxo de dados em tempo real ponta a ponta:

1. Abra uma sessão SSH paralela no host do seu servidor Ubuntu e chame o produtor interativo:
```bash
sudo docker compose exec kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic ipfix-network-flow
```

2. Assim que o cursor interativo `>` abrir, insira linhas em formato JSON (pressionando Enter a cada inserção) simulando uma varredura de botnet na sua rede:
```json
{"vlan": 30, "src_ip": "192.168.30.77", "dst_ip": "192.168.30.1", "dst_port": 23, "packets": 600, "bytes": 36000}
{"vlan": 40, "src_ip": "192.168.40.10", "dst_ip": "192.168.9.50", "dst_port": 80, "packets": 150, "bytes": 12500}
```

3. **Verificando os arquivos gerados no Object Storage:**
Execute a célula 6 no Jupyter. Você verá o contador `"numInputRows"` subir indicando o consumo. Para ler os arquivos que foram streamados de forma incremental para dentro do Data Lake, crie uma nova célula no Jupyter e execute:

```python
# O Spark lerá os dados salvos e estruturados dinamicamente em partições colunares
spark.read.parquet("s3a://meu-data-lake/live_network_logs/").show()
```

Os logs estarão particionados por VLAN e indexados nativamente no disco do seu Data Lake Privado, prontos para a camada de analytics e Machine Learning!
```