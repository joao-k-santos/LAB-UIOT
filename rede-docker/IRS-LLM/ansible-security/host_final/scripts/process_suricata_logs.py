from pyspark import SparkConf
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, hour, minute, second, to_timestamp
from pyspark.sql.types import StructType, StringType, IntegerType, StructField
import os

# Garante que não tenha variável externa influenciando
# Remove qualquer variável de ambiente que possa estar configurando o Spark em modo cluster
for var in ["SPARK_MASTER", "SPARK_HOME", "PYSPARK_SUBMIT_ARGS", "PYSPARK_DRIVER_PYTHON_OPTS"]:
    os.environ.pop(var, None)

spark = SparkSession.builder \
    .appName("SuricataLogProcessor") \
    .master("local[*]") \
    .config("spark.driver.bindAddress", "127.0.0.1") \
    .config("spark.driver.host", "127.0.0.1") \
    .config("spark.jars", "/opt/spark/jars/postgresql.jar") \
    .getOrCreate()


suricata_log_path = "/var/log/suricata/eve.json"

# Schema customizado
schema = StructType([
    StructField("timestamp", StringType(), True),
    StructField("event_type", StringType(), True),
    StructField("flow_id", StringType(), True),
    StructField("src_ip", StringType(), True),
    StructField("src_port", IntegerType(), True),
    StructField("dest_ip", StringType(), True),
    StructField("dest_port", IntegerType(), True),
    StructField("proto", StringType(), True),
    StructField("alert", StructType([
        StructField("severity", IntegerType(), True)
    ])),
    StructField("flow", StructType([
        StructField("pkts_toserver", IntegerType(), True),
        StructField("pkts_toclient", IntegerType(), True),
        StructField("bytes_toserver", IntegerType(), True),
        StructField("bytes_toclient", IntegerType(), True)
    ]))
])

# Lê todos os eventos, deixando o Spark inferir o schema
df_raw = spark.read.option("mode", "PERMISSIVE").json(suricata_log_path)

# Normaliza os campos para o schema desejado
df_final = df_raw.select(
    col("flow_id"),
    col("src_ip"),
    col("dest_ip"),
    col("src_port"),
    col("dest_port"),
    col("proto"),
    to_timestamp("timestamp").alias("ts"),
    col("alert.severity").alias("severity"),  # Pode ser null se não for um alerta
    col("flow.pkts_toserver").alias("pkts_toserver"),
    col("flow.pkts_toclient").alias("pkts_toclient"),
    col("flow.bytes_toserver").alias("bytes_toserver"),
    col("flow.bytes_toclient").alias("bytes_toclient")
).withColumn("hour", hour("ts")) \
 .withColumn("minute", minute("ts")) \
 .withColumn("seconds", second("ts")) \
 .drop("ts")

df_final = df_final.fillna(0) # Preenche valores nulos com 0
# Reorganiza
df_final = df_final.select(
    "flow_id", "src_ip", "dest_ip", "src_port", "dest_port", "proto",
    "hour", "minute", "seconds", "severity",
    "pkts_toserver", "pkts_toclient", "bytes_toserver", "bytes_toclient"
)

# Configuração JDBC
pg_url = "jdbc:postgresql://192.168.15.8:5432/nids_db"
pg_properties = {
    "user": "user",
    "password": "password",
    "driver": "org.postgresql.Driver"
}

# Escreve no PostgreSQL
df_final.write.jdbc(url=pg_url, table="trafego", mode="append", properties=pg_properties)

spark.stop()
