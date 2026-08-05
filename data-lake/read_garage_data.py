import os
import sys
from dotenv import load_dotenv
from pyspark.sql import SparkSession

# 1. Carrega credenciais
load_dotenv()
access_key = os.getenv('minha_chave')
secret_key = os.getenv('secret_key')

if not access_key or not secret_key:
    print("❌ ERRO: Credenciais 'minha_chave' e 'secret_key' não encontradas no .env")
    sys.exit(1)

# 2. Inicializa a Sessão PySpark
spark = SparkSession.builder \
    .appName("Reader-Garage-S3") \
    .config("spark.jars.packages", "org.apache.hadoop:hadoop-aws:3.3.4") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")

# 3. Configurações do S3A para o Garage
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

target_path = "s3a://meu-data-lake/live_network_logs/"

print(f"🔎 Lendo dados do Data Lake em: {target_path}\n")

try:
    df = spark.read.parquet(target_path)
    total_records = df.count()
    
    print(f"📊 Total de registros gravados: {total_records}\n")
    
    print("--- 📌 Últimos 20 registros inseridos ---")
    df.orderBy(df.ingestion_time.desc()).show(20, truncate=False)
    
    print("--- 🏷️ Volumetria de logs particionados por VLAN ---")
    df.groupBy("vlan").count().orderBy("vlan").show()

except Exception as e:
    print(f"❌ Erro ao consultar o Garage S3: {e}")

finally:
    spark.stop()