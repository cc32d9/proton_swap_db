
CREATE TABLE IF NOT EXISTS swap_ticks (
      seq                 BIGINT NOT NULL,
      block_num           BIGINT NOT NULL,
      time  TIMESTAMP WITHOUT TIME ZONE NOT NULL,
      tx_id varchar(255) NOT NULL,
      act_type varchar(255) NOT NULL,
      owner varchar(30),
      token1_symbol varchar(30) NOT NULL,
      token1_amount decimal NOT NULL,
      token2_symbol varchar(30) NOT NULL,
      token2_amount decimal NOT NULL,
      pool1_symbol varchar(30),
      pool1_amount decimal,
      pool2_symbol varchar(30),
      pool2_amount decimal,
      pool1_contract varchar(255),
      pool2_contract varchar(255),
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

CREATE INDEX IF NOT EXISTS swap_ticks_i01 ON swap_ticks (block_num);
CREATE INDEX IF NOT EXISTS swap_ticks_i02 ON swap_ticks (token1_symbol, token2_symbol, time);
CREATE INDEX IF NOT EXISTS swap_ticks_i03 ON swap_ticks (token1_symbol, block_num, time);
CREATE INDEX IF NOT EXISTS swap_ticks_i04 ON swap_ticks (token2_symbol, block_num, time);




