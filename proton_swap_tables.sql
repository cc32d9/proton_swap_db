CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

CREATE TABLE IF NOT EXISTS swap_ticks (
      block_num           BIGINT NOT NULL,
      time timestamptz NOT NULL,
      tx_id varchar(255) NOT NULL,
      act_type varchar(255) NOT NULL,
      owner varchar(30) NOT NULL,
      token1_symbol varchar(30) NOT NULL,
      token1_amount decimal NOT NULL,
      token2_symbol varchar(30) NOT NULL,
      token2_amount decimal NOT NULL,
      pool1_symbol varchar(30) NOT NULL,
      pool1_amount decimal NOT NULL,
      pool2_symbol varchar(30) NOT NULL,
      pool2_amount decimal NOT NULL,
      pool1_contract varchar(255) NOT NULL,
      pool2_contract varchar(255) NOT NULL,
      lt_symbol varchar(30),
      lt_amount decimal,
      add_token1_amount decimal,
      add_token1_symbol varchar(30),
      add_token2_symbol varchar(30),
      add_token2_amount decimal,
      add_token1_min_symbol varchar(30),
      add_token1_min_amount decimal,
      add_token2_min_symbol varchar(30),
      add_token2_min_amount decimal,
      memo varchar(255),
      pool_price decimal,
      inverted_pool_price decimal,
      pool1_swap_amount decimal,
      pool2_swap_amount decimal,
      pool1_liq_amount decimal,
      pool2_liq_amount decimal
);

SELECT create_hypertable('swap_ticks', 'time', if_not_exists => TRUE);

CREATE INDEX swap_ticks_i01 ON swap_ticks (block_num);



CREATE TABLE IF NOT EXISTS trade_executions (
      block_num           BIGINT NOT NULL,
      time timestamptz NOT NULL,
      tx_id varchar(255) NOT NULL,
      trade_id integer NOT NULL,
      bid_user VARCHAR(30) NOT NULL,
      bid_user_order_id integer NOT NULL,
      ask_user VARCHAR(30) NOT NULL,
      ask_user_order_id integer NOT NULL,
      bid_amount VARCHAR(250) NOT NULL,
      ask_amount VARCHAR(250) NOT NULL,
      price decimal NOT NULL
);

SELECT create_hypertable('trade_executions', 'time', if_not_exists => TRUE);

CREATE INDEX trade_executions_i01 ON trade_executions (block_num);

