import os
import sys
from dotenv import load_dotenv
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, current_timestamp, coalesce
from pyspark.sql.types import (
    StructType, StructField, StringType, IntegerType, LongType
)

# 1. Carrega credenciais ocultas
load_dotenv()
access_key = os.getenv('minha_chave')
secret_key = os.getenv('secret_key')

if not access_key or not secret_key:
    print("❌ ERRO: Credenciais 'minha_chave' e 'secret_key' não encontradas no .env")
    sys.exit(1)

# 2. Inicializa a Sessão PySpark com os pacotes necessários
spark = SparkSession.builder \
    .appName("Daemon-KafkaToGarage-Ingestion") \
    .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1,org.apache.hadoop:hadoop-aws:3.3.4") \
    .getOrCreate()

# Reduz logs verbosos do Spark no terminal
spark.sparkContext.setLogLevel("WARN")

# 3. Configurações de Conexão e Tuning do S3A para o Garage HQ
sc = spark.sparkContext
hadoop_conf = sc._jsc.hadoopConfiguration()
hadoop_conf.set("fs.s3a.access.key", access_key)
hadoop_conf.set("fs.s3a.secret.key", secret_key)
hadoop_conf.set("fs.s3a.endpoint", "http://garage:3900")
hadoop_conf.set("fs.s3a.path.style.access", "true")
hadoop_conf.set("fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
hadoop_conf.set("fs.s3a.connection.ssl.enabled", "false")
hadoop_conf.set("fs.s3a.endpoint.region", "garage")
hadoop_conf.set("fs.s3a.region", "garage")
hadoop_conf.set("fs.s3a.change.detection.mode", "none")
hadoop_conf.set("fs.s3a.change.detection.source", "none")

# Tuning para escrita direta de alta performance
hadoop_conf.set("mapreduce.fileoutputcommitter.algorithm.version", "2")
hadoop_conf.set("fs.s3a.directory.marker.retention", "keep")
hadoop_conf.set("fs.s3a.fast.upload", "true")
hadoop_conf.set("fs.s3a.fast.upload.buffer", "disk")

print("🚀 Daemon do Spark iniciado! Processando mensagens do Kafka -> Garage HQ...")

# 4. Schema resiliente (GoFlow2 + Testes Manuais)
goflow_schema = StructType([
    StructField("Type", StringType(), True),
    StructField("TimeReceived", LongType(), True),
    StructField("SequenceNum", LongType(), True),
    StructField("SamplingRate", IntegerType(), True),
    StructField("FlowDirection", IntegerType(), True),

    StructField("Bytes", LongType(), True),
    StructField("Packets", LongType(), True),
    StructField("bytes", LongType(), True),
    StructField("packets", LongType(), True),

    StructField("SrcAddr", StringType(), True),
    StructField("DstAddr", StringType(), True),
    StructField("src_ip", StringType(), True),
    StructField("dst_ip", StringType(), True),

    StructField("SrcPort", IntegerType(), True),
    StructField("DstPort", IntegerType(), True),
    StructField("src_port", IntegerType(), True),
    StructField("dst_port", IntegerType(), True),

    StructField("Proto", IntegerType(), True),
    StructField("TcpFlags", IntegerType(), True),

    StructField("SrcVlan", IntegerType(), True),
    StructField("DstVlan", IntegerType(), True),
    StructField("VlanId", IntegerType(), True),
    StructField("vlan", IntegerType(), True),

    StructField("SamplerAddress", StringType(), True)
])

# 5. Ingestão Streaming
df_kafka = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka:9092") \
    .option("subscribe", "ipfix-network-flow") \
    .option("startingOffsets", "earliest") \
    .load()

df_flows = (
    df_kafka
    .selectExpr("CAST(value AS STRING) AS json_payload", "timestamp AS kafka_timestamp")
    .select(from_json(col("json_payload"), goflow_schema).alias("flow"), col("kafka_timestamp"))
    .select(
        col("flow.Type").alias("flow_type"),
        col("flow.TimeReceived").alias("time_received"),
        coalesce(col("flow.SrcAddr"), col("flow.src_ip")).alias("src_ip"),
        coalesce(col("flow.DstAddr"), col("flow.dst_ip")).alias("dst_ip"),
        coalesce(col("flow.SrcPort"), col("flow.src_port")).alias("src_port"),
        coalesce(col("flow.DstPort"), col("flow.dst_port")).alias("dst_port"),
        col("flow.Proto").alias("protocol"),
        coalesce(col("flow.Bytes"), col("flow.bytes")).alias("bytes"),
        coalesce(col("flow.Packets"), col("flow.packets")).alias("packets"),
        coalesce(
            col("flow.vlan"),
            col("flow.VlanId"),
            col("flow.SrcVlan"),
            col("flow.DstVlan")
        ).alias("vlan"),
        current_timestamp().alias("ingestion_time")
    )
    .filter(col("src_ip").isNotNull())
)

# 6. Disparo da Gravação Contínua
query = df_flows.writeStream \
    .format("parquet") \
    .outputMode("append") \
    .option("path", "s3a://meu-data-lake/live_network_logs/") \
    .option("checkpointLocation", "s3a://meu-data-lake/checkpoints/goflow_pipeline/") \
    .partitionBy("vlan") \
    .start()

# Segura o processo em execução contínua
try:
    query.awaitTermination()
except KeyboardInterrupt:
    print("\n🛑 Encerrando graciosamente o processo de ingestão...")
    query.stop()
    spark.stop()