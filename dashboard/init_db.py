import psycopg2
import os
import requests
import time

DB_DIR = "/flower/databases"  # Caminho do diretório onde o banco será salvo
DB_FILE = os.path.join(DB_DIR, "nids.db")  # Caminho completo do banco
DB_FILE = os.path.join(DB_DIR, "nids.db")  # Caminho completo do banco
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "nids_db")
DB_USER = os.getenv("DB_USER", "user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
# Garante que o diretório do banco exista
os.makedirs(DB_DIR, exist_ok=True)

def conectar(db_host=DB_HOST, db_port=DB_PORT, db_name=DB_NAME, db_user=DB_USER, db_password=DB_PASSWORD):
    """Conecta ao banco de dados PostgreSQL"""
    retries = 10
    while retries > 0:
        try:
            conn = psycopg2.connect(
            host=db_host,
            port=db_port,
            database=db_name,
            user=db_user,
            password=db_password
        )
            return conn
        except Exception as e:
            print(f"Aguardando o banco subir... ({10 - retries + 1}/10)")
            time.sleep(3)
            retries -= 1
        else:
            raise Exception("Não foi possível conectar ao banco após várias tentativas")


def inicializar_banco():
    """Cria o banco de dados e as tabelas se ainda não existirem"""
    conn = conectar()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS trafego (
            id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            hash_id TEXT NOT NULL,
            flow_id TEXT NOT NULL,
            src_ip TEXT NOT NULL,
            dest_ip TEXT NOT NULL,
            src_port INTEGER NOT NULL,
            dest_port INTEGER NOT NULL,
            proto TEXT NOT NULL,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL,
            seconds INTEGER NOT NULL,
            severity INTEGER NOT NULL,
            pkts_toserver INTEGER NOT NULL,
            pkts_toclient INTEGER NOT NULL,
            bytes_toserver INTEGER NOT NULL,
            bytes_toclient INTEGER NOT NULL,
            UNIQUE (hash_id)
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS classificados (
            id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            hash_id TEXT NOT NULL,
            flow_id TEXT NOT NULL,
            src_ip TEXT NOT NULL,
            dest_ip TEXT NOT NULL,
            src_port INTEGER NOT NULL,
            dest_port INTEGER NOT NULL,
            proto TEXT NOT NULL,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL,
            seconds INTEGER NOT NULL,
            severity INTEGER NOT NULL,
            pkts_toserver INTEGER NOT NULL,
            pkts_toclient INTEGER NOT NULL,
            bytes_toserver INTEGER NOT NULL,
            bytes_toclient INTEGER NOT NULL,
            class TEXT NOT NULL,
            processado INTEGER DEFAULT 0,
            UNIQUE (hash_id)
        )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS usuarios (
        id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL
    )
    """)

    conn.commit()
    conn.close()
    print("Banco de dados inicializado!")

def criar_views():
    conn = conectar()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            CREATE OR REPLACE VIEW v_trafego_dash AS 
            SELECT
                t.hour,
                t.minute,
            
                -- 1. Visão Geral (Soma de tudo, pois a tabela 'trafego' tem 100% dos dados)
                SUM(t.bytes_toserver + t.bytes_toclient) AS volume_bytes_total,
                SUM(t.pkts_toserver + t.pkts_toclient) AS volume_pkts_total,
            
                -- 2. Visão Segmentada por Bytes
                -- Se c.hash_id for NULO, não está na tabela de classificados (é Normal)
                SUM(CASE WHEN c.hash_id IS NULL THEN (t.bytes_toserver + t.bytes_toclient) ELSE 0 END) AS bytes_normais,
                -- Se c.hash_id NÃO FOR NULO, é porque foi classificado como Anômalo
                SUM(CASE WHEN c.hash_id IS NOT NULL THEN (t.bytes_toserver + t.bytes_toclient) ELSE 0 END) AS bytes_anomalos,
            
                -- 3. Visão Segmentada por Pacotes
                SUM(CASE WHEN c.hash_id IS NULL THEN (t.pkts_toserver + t.pkts_toclient) ELSE 0 END) AS pkts_normais,
                SUM(CASE WHEN c.hash_id IS NOT NULL THEN (t.pkts_toserver + t.pkts_toclient) ELSE 0 END) AS pkts_anomalos
            
            FROM trafego t
            LEFT JOIN classificados c ON t.hash_id = c.hash_id
            GROUP BY
                t.hour,
                t.minute;
        """)
        conn.commit()
        conn.close()
        print("View criada")
    except Exception as e:
        print(f"Houve um erro: {e}")


if __name__ == "__main__":
    inicializar_banco()
    criar_views()