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
