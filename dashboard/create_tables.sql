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



CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL
)
