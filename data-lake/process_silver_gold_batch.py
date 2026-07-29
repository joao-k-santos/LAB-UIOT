import os
import sys
from dotenv import load_dotenv
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as _sum, countDistinct, round, when

# 1. Carrega credenciais ocultas
load_dotenv()
access_key = os.getenv('minha_chave')
secret_key = os.getenv('secret_key')

if not access_key or not secret_key:
    print("❌ ERRO: Credenciais não encontradas no .env")
    sys.exit(1)

# 2. Inicializa a Sessão Spark para Processamento em Lote (Batch ETL)
spark = SparkSession.builder \
    .appName("Medallion-Silver-Gold-Pipeline") \
    .config("spark.jars.packages", "org.apache.hadoop:hadoop-aws:3.3.4") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")

# 3. Configurações S3A / Garage HQ
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

# Tuning de escrita no S3
hadoop_conf.set("mapreduce.fileoutputcommitter.algorithm.version", "2")
hadoop_conf.set("fs.s3a.directory.marker.retention", "keep")

print("🔄 Iniciando Ciclo de Refinamento Medalhão (Bronze -> Silver -> Gold)...\n")

try:
    # -------------------------------------------------------------
    # 🥈 PROCESSAMENTO SILVER: LIMPEZA E PADRONIZAÇÃO
    # -------------------------------------------------------------
    print("⏳ Lendo Camada Bronze...")
    df_bronze = spark.read.parquet("s3a://meu-data-lake/live_network_logs/")

    df_silver = df_bronze.filter((col("packets") > 0) & (col("bytes") > 0)) \
        .filter(col("dst_ip") != "255.255.255.255") \
        .dropDuplicates()

    print("💾 Gravando Camada Silver...")
    df_silver.write \
        .format("parquet") \
        .mode("overwrite") \
        .partitionBy("vlan") \
        .save("s3a://meu-data-lake/silver_network_logs/")

    print("🥈 Camada Silver atualizada com sucesso!\n")

    # -------------------------------------------------------------
    # 🥇 PROCESSAMENTO GOLD: DATA MINING & FEATURE ENGINEERING
    # -------------------------------------------------------------
    print("⏳ Lendo Camada Silver...")
    df_clean = spark.read.parquet("s3a://meu-data-lake/silver_network_logs/")

    df_gold = df_clean.groupBy("src_ip", "vlan").agg(
        _sum("packets").alias("total_packets"),
        _sum("bytes").alias("total_bytes"),
        countDistinct("dst_ip").alias("unique_targets"),
        countDistinct("dst_port").alias("unique_ports")
    ).withColumn(
        "bytes_per_packet", round(col("total_bytes") / col("total_packets"), 2)
    )

    # Regra Heurística de Detecção
    df_gold_analise = df_gold.withColumn(
        "comportamento",
        when((col("unique_ports") > 10) & (col("bytes_per_packet") < 100), "ANOMALIA_BOTNET")
        .otherwise("NORMAL")
    )

    print("💾 Gravando Camada Gold...")
    df_gold_analise.write \
        .format("parquet") \
        .mode("overwrite") \
        .save("s3a://meu-data-lake/gold_ml_features/")

    print("🥇 Camada Gold atualizada com sucesso!")
    print("\n--- 📌 Amostra da Camada Gold ---")
    df_gold_analise.show(10, truncate=False)

except Exception as e:
    print(f"❌ Erro durante o processamento Medalhão: {e}")

finally:
    spark.stop()