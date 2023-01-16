use strict;
use warnings;
use DBD::Pg qw(:pg_types);


my $swap_contract = 'proton.swaps';

my @insert_journal;
my @insert_order_history;
my @insert_exec;
my @insert_trades;

sub swaphistory_prepare
{
    my $args = shift;
    if( defined($args->{'contract'}) )
    {
        $swap_contract = $args->{'contract'};
    }

    my $dbh = $main::db->{'dbh'};

    $main::db->{'ins_swap_ticks'} =
        $dbh->prepare('INSERT INTO swap_ticks (block_num, time, tx_id, act_type, owner, token1_symbol, token1_amount, ' .
                      ' token2_symbol, token2_amount, pool1_symbol, pool1_amount, pool2_symbol, pool2_amount, ' .
                      ' pool1_contract, pool2_contract, lt_symbol, lt_amount, add_token1_amount, add_token1_symbol, ' .
                      ' add_token2_symbol, add_token2_amount, add_token1_min_symbol, add_token1_min_amount decimal, ' .
                      ' add_token2_min_symbol, add_token2_min_amount, memo, pool_price, inverted_pool_price, ' .
                      ' pool1_swap_amount, pool2_swap_amount, pool1_liq_amount, pool2_liq_amount) ' .
                      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
    
    printf STDERR ("proton_swap_dbwriter.pl prepared, contract: %s\n", $swap_contract);
}


sub swaphistory_trace
{
    my $trx_seq = shift;
    my $block_num = shift;
    my $block_time = shift;
    my $trace = shift;
    my $jsptr = shift;

    foreach my $atrace (@{$trace->{'action_traces'}})
    {
        my $act = $atrace->{'act'};
        my $contract = $act->{'account'};
        my $aname = $act->{'name'};
        my $receipt = $atrace->{'receipt'};
        my $receiver = $receipt->{'receiver'};
        my $data = $act->{'data'};
        next unless ref($data) eq 'HASH';
        next unless $contract eq $swap_contract;

        if( $receiver eq $contract )
        {
            if( $aname eq 'logmarket' )
            {
                my $status = $data->{'status'};
                my $old_val = {};
                my $op;
                my $new_val = $data->{'market'};
                my $market_id = $new_val->{'market_id'};

                my $bid_token_s = $new_val->{'bid_token'}{'sym'}; # 4,XPR
                my $decimals = $bid_token_s;
                $decimals =~ s/,.*//;
                my $bid_token_m = 10 ** int($decimals);
                $bid_token_s =~ s/^\d,//; # cut off the precision

                my ($amount, $ask_token_s) = split(/\s+/, $new_val->{'ask_token'}{'quantity'}); # 0.002698 XUSDC
                $decimals = 0;
                my $pos = index($amount, '.');
                if( $pos > -1 )
                {
                    $decimals = length($amount) - $pos - 1;
                }
                my $ask_token_m = 10 ** $decimals;

                if( $status eq 'create' )
                {
                    $op = 1;
                    $main::db->{'ins_market'}->execute
                        ($market_id, $new_val->{'order_min'}, $new_val->{'status_code'}, $new_val->{'ask_oracle_index'},
                         $new_val->{'bid_token'}{'contract'}, $bid_token_s, $bid_token_m,
                         $new_val->{'ask_token'}{'contract'}, $ask_token_s, $ask_token_m,
                         $block_time, $block_time);
                }
                else
                {
                    my $sth = $main::db->{'get_market'};
                    $sth->execute($market_id);
                    my $r = $sth->fetchall_arrayref({});
                    if( scalar(@{$r}) == 0 )
                    {
                        die("Cannot find the previous state for market_id=$market_id");
                    }
                    $old_val = $r->[0];
                    if( $status eq 'delete' )
                    {
                        $op = 3;
                        $main::db->{'del_market'}->execute($market_id);
                    }
                    else
                    {
                        $op = 2;
                        $main::db->{'upd_market'}->execute
                            ($new_val->{'order_min'}, $new_val->{'status_code'}, $new_val->{'ask_oracle_index'},
                            $block_time, $market_id);
                    }
                }

                $main::db->{'ins_market_history'}->execute
                    ($receipt->{'global_sequence'}, $block_num, $block_time,
                     $market_id, $new_val->{'order_min'}, $new_val->{'status_code'}, $new_val->{'ask_oracle_index'},
                     $new_val->{'bid_token'}{'contract'}, $bid_token_s, $bid_token_m,
                     $new_val->{'ask_token'}{'contract'}, $ask_token_s, $ask_token_m,
                     $status, $trace->{'id'});

                push(@insert_journal, [$block_num, $op, '\'markets\'', '\'market_id\'', $market_id,
                                       $main::db->{'dbh'}->quote($main::json->encode($old_val), {pg_type => DBD::Pg->PG_BYTEA})]);
            }
            elsif( $aname eq 'logorder' )
            {
                my $status = $data->{'status'};
                my $old_val = {};
                my $op;
                my $new_val = $data->{'order'};
                my $order_id = $new_val->{'order_id'};
                my $quantity_init;

                if( $status eq 'create' )
                {
                    $op = 1;
                    $quantity_init = $new_val->{'quantity'};
                    $main::db->{'ins_order'}->execute
                        ($order_id, $new_val->{'market_id'}, $quantity_init, $quantity_init,
                         $new_val->{'price'}, $new_val->{'account_name'}, $new_val->{'order_side'},
                         $new_val->{'order_type'}, $new_val->{'trigger_price'}, $new_val->{'fill_type'},
                         $status, $block_time, $block_time);
                }
                else
                {
                    my $sth = $main::db->{'get_order'};
                    $sth->execute($order_id);
                    my $r = $sth->fetchall_arrayref({});
                    if( scalar(@{$r}) == 0 )
                    {
                        die("Cannot find the previous state for order_id=$order_id");
                    }
                    $old_val = $r->[0];
                    $quantity_init = $old_val->{'quantity_init'};

                    if( $status eq 'cancel' or $status eq 'delete' )
                    {
                        $op = 3;
                        $main::db->{'del_order'}->execute($order_id);
                    }
                    else
                    {
                        $op = 2;
                        $main::db->{'upd_order'}->execute
                            ($new_val->{'quantity'}, $new_val->{'order_type'},
                             $new_val->{'trigger_price'},
                             $status, $order_id);
                    }
                }

                my $dbh = $main::db->{'dbh'};

                push(@insert_order_history, [
                         $receipt->{'global_sequence'}, $block_num, $dbh->quote($block_time),
                         $order_id, $new_val->{'market_id'}, $quantity_init, $new_val->{'quantity'}, $new_val->{'price'},
                         $dbh->quote($new_val->{'account_name'}), $new_val->{'order_side'}, $new_val->{'order_type'},
                         $new_val->{'trigger_price'}, $new_val->{'fill_type'},
                         $dbh->quote($status), $data->{'quantity_change'}, $dbh->quote($trace->{'id'})]);

                push(@insert_journal, [$block_num, $op, '\'current_orders\'', '\'order_id\'', $order_id,
                                       $dbh->quote($main::json->encode($old_val), {pg_type => DBD::Pg->PG_BYTEA})]);

            }
            elsif( $aname eq 'logexec' )
            {
                my $trade_id = $data->{'trade_id'};
                my $trx_id = $trace->{'id'};

                my $dbh = $main::db->{'dbh'};

                push(@insert_exec, [
                         $trade_id, $block_num, $dbh->quote($block_time), $data->{'bid_user_order_id'},
                         $data->{'bid_total'}, $dbh->quote($trx_id)]);

                push(@insert_exec, [
                         $trade_id, $block_num, $dbh->quote($block_time), $data->{'ask_user_order_id'},
                         $data->{'ask_total'}, $dbh->quote($trx_id)]);

                push(@insert_trades, [
                         $block_num,
                         $dbh->quote($block_time),
                         $trade_id,
                         $data->{'market_id'},
                         $data->{'price'},
                         $dbh->quote($data->{'bid_user'}),
                         $data->{'bid_user_order_id'},
                         $data->{'bid_total'},
                         $data->{'bid_amount'},
                         $data->{'bid_fee'},
                         $dbh->quote($data->{'bid_referrer'}),
                         $data->{'bid_referrer_fee'},
                         $dbh->quote($data->{'ask_user'}),
                         $data->{'ask_user_order_id'},
                         $data->{'ask_total'},
                         $data->{'ask_amount'},
                         $data->{'ask_fee'},
                         $dbh->quote($data->{'ask_referrer'}),
                         $data->{'ask_referrer_fee'},
                         $data->{'order_side'},
                         $dbh->quote($trx_id)]);
            }
        }
    }
}



sub swaphistory_fork
{
    my $block_num = shift;

    my $dbh = $main::db->{'dbh'};

    my $sth = $dbh->prepare('DELETE FROM swap_ticks where block_num >= ?');
    $sth->execute($block_num);
    $sth = $dbh->prepare('DELETE FROM trade_executions where block_num >= ?');
    $sth->execute($block_num);

    print STDERR "fork: $block_num\n";
}




push(@main::prepare_hooks, \&swaphistory_prepare);
push(@main::trace_hooks, \&swaphistory_trace);
push(@main::fork_hooks, \&swaphistory_fork);

1;
