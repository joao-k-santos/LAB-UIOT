# 📑 Guia Definitivo: Implantação e Operação do Data Lake Privado UIoT

Este documento consolida o passo a passo completo para implantar, tunelar e operar um ecossistema local standalone de engenharia de dados focado em segurança de rede (VLANs 30 e 40). A stack integra **Garage HQ (S3 Object Storage)**, **Apache Kafka (KRaft)**, **Apache Spark (Cluster Master/Worker)** e **Jupyter Lab (PySpark/ML)**.

---

## 🗺️ 1. Desenho de Arquitetura e Preparação do Servidor

A infraestrutura foi desenhada para rodar em um nó local único (standalone) hospedado sob o hipervisor Proxmox. Os volumes locais do host Linux são amarrados para garantir a persistência dos logs estruturados e dos metadados transacionais.

No terminal SSH do seu servidor (`uiot-dl`), prepare o ambiente limpando resíduos anteriores e forçando as permissões corretas para evitar travas de IO (Input/Output) do banco do Garage e permissões de ID do Kafka:

```bash
# Navegue até o diretório central do ecossistema
cd ~/data-lake

# Resete estruturas corrompidas de metadados transacionais anteriores
sudo rm -rf garage_data kafka_data

# Crie fisicamente os subdiretórios estruturais requisitados pelos contêineres
mkdir -p garage_data/meta garage_data/data notebooks

# Conceda privilégios totais de leitura/escrita para evitar travas no SQLite/LMDB do Garage
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

*Nota: Removidas todas as marcações textuais de anotações que quebravam o interpretador YAML do Docker. Os comandos de boot chamam os binários absolutos e classes Java adequadas.*

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
    restart: unless-stopped

  # --- CAMADA DE MENSAGERIA (MENSAGENS/BUFFER) ---
  kafka:
    image: apache/kafka:3.7.0
    container_name: kafka-security-hub
    ports:
      - "9092:9092"
    environment:
      - KAFKA_NODE_ID=1
      - KAFKA_PROCESS_ROLES=broker,controller
      - KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093
      - KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092
      - KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093
      - KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER
      - KAFKA_LOG_DIRS=/var/lib/kafka/data
      - KAFKA_CLUSTER_ID=4L62xdw2Rxy2wAF4968gAg
    volumes:
      - ./kafka_data:/var/lib/kafka/data
    restart: unless-stopped

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
    restart: unless-stopped

  spark-worker:
    image: apache/spark:3.5.1
    container_name: spark-worker-1
    depends_on:
      - spark-master
    environment:
      - SPARK_MODE=worker
    command: /opt/spark/bin/spark-class org.apache.spark.deploy.worker.Worker spark://spark-master:7077
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
    restart: unless-stopped

networks:
  datalake_net:
    driver: overlay

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

## 📓 5. Construção do Pipeline e Gerenciamento do `.env` no Jupyter

Abra o seu navegador web local no endereço `http://localhost:8888` e insira o token de segurança obtido através dos logs do contêiner (`sudo docker compose logs pyspark-notebook`).

Abra um notebook Python 3 em branco e execute as células organizadas sequencialmente a seguir:

### Célula 1: Instalação do Gerenciador de Ambiente

```python
!pip install python-dotenv

```

### Célula 2: Geração Automatizada e Oculta do Arquivo `.env`

*Esta célula utiliza comandos mágicos para persistir as chaves de acesso no mesmo diretório de execução, mantendo as credenciais fora do código aberto.*

```python
%%writefile .env
minha_chave=GKe752e73e675cc700c0eb72f3
secret_key=COLE_AQUI_O_SECRET_KEY_INTEIRO_EXIBIDO_PELO_GARAGE

```

### Célula 3: Boot da Sessão Spark e Acoplamento Hadoop S3A

*Inclusão mandatória do pacote `import os` para ler as variáveis injetadas pelo `load_dotenv()`.*

```python
import os
from dotenv import load_dotenv
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, current_timestamp
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

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

print("🚀 Sessão Spark configurada com sucesso usando segurança via arquivo .env!")

```

### Célula 4: Teste de Escrita e Leitura Estática (Validação S3A)

```python
# Massa de dados de teste contendo metadados de incidentes
dados_teste = [
    ("VLAN_30", "192.168.30.99", "Mirai Port Scan Detectado", "ALTA"),
    ("VLAN_40", "192.168.40.12", "Tentativa Bruteforce SSH", "MEDIA")
]
colunas = ["origem_vlan", "ip_origem", "evento", "severidade"]
df_teste = spark.createDataFrame(dados_teste, schema=colunas)

try:
    # Persiste em formato binário otimizado colunar Parquet
    df_teste.write.format("parquet").mode("overwrite").save("s3a://meu-data-lake/teste_alertas/")
    print("✨ Sucesso! O Spark conseguiu autenticar, gravar e fechar pacotes no Garage HQ.")
    
    # Valida a leitura reversa do dado persistido
    spark.read.parquet("s3a://meu-data-lake/teste_alertas/").show()
except Exception as e:
    print(f"❌ Falha crítica de privilégio ou IO no Object Storage: {e}")

```

### Célula 5: Ativação do Pipeline de Streaming Estruturado em Tempo Real

```python
# Mapeamento do Schema padronizado (Formato NetFlow/Akvorado simplificado)
log_schema = StructType([
    StructField("vlan", IntegerType(), True),
    StructField("src_ip", StringType(), True),
    StructField("dst_ip", StringType(), True),
    StructField("dst_port", IntegerType(), True),
    StructField("packets", IntegerType(), True),
    StructField("bytes", IntegerType(), True)
])

# Conexão de streaming contínuo ao cluster interno do Kafka
df_kafka = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka:9092") \
    .option("subscribe", "security-network-flux") \
    .option("startingOffsets", "latest") \
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

print("🔥 Pipeline de streaming em tempo real ativado e escutando tópicos do Kafka.")

```

---

## 🛰️ 6. Simulação de Ingestão de Ameaça e Validação Finais

Para testar o fluxo de ponta a ponta (Ingestão ➡️ Buffer ➡️ Processamento Streaming ➡️ Armazenamento S3):

1. Abra uma sessão SSH paralela no host do servidor e chame o produtor interativo do Kafka:
```bash
sudo docker compose exec kafka-security-hub kafka-console-producer.sh --broker-list localhost:9092 --topic security-network-flux

```


2. Assim que o cursor interativo `>` abrir, insira a linha abaixo em formato JSON para simular um ataque de botnet infectando e escaneando a rede interna e pressione Enter:
```json
{"vlan": 30, "src_ip": "192.168.30.77", "dst_ip": "192.168.30.1", "dst_port": 23, "packets": 600, "bytes": 36000}

```



O Apache Spark consumirá o evento instantaneamente por streaming e ordenará ao Garage a criação estruturada da subpasta `live_network_logs/vlan=30/`. Seus dados estarão persistidos de forma limpa e indexada, prontos para alimentar seus modelos analíticos de detecção de anomalias por entropia de portas!

```