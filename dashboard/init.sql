-- Criação da tabela trafego
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
);

-- Criação da tabela classificados
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
);

-- Criação da tabela usuarios
CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL
);

-- Criação da View de volume
CREATE OR REPLACE VIEW v_trafego_dash AS
SELECT
    t.hour,
    t.minute,

    -- 1. Visão Geral
    SUM(t.bytes_toserver + t.bytes_toclient) AS volume_bytes_total,
    SUM(t.pkts_toserver + t.pkts_toclient) AS volume_pkts_total,

    -- 2. Visão Segmentada por Bytes
    SUM(CASE WHEN c.hash_id IS NULL THEN (t.bytes_toserver + t.bytes_toclient) ELSE 0 END) AS bytes_normais,
    SUM(CASE WHEN c.hash_id IS NOT NULL THEN (t.bytes_toserver + t.bytes_toclient) ELSE 0 END) AS bytes_anomalos,

    -- 3. Visão Segmentada por Pacotes
    SUM(CASE WHEN c.hash_id IS NULL THEN (t.pkts_toserver + t.pkts_toclient) ELSE 0 END) AS pkts_normais,
    SUM(CASE WHEN c.hash_id IS NOT NULL THEN (t.pkts_toserver + t.pkts_toclient) ELSE 0 END) AS pkts_anomalos

FROM trafego t
LEFT JOIN classificados c ON t.hash_id = c.hash_id
GROUP BY
    t.hour,
    t.minute;