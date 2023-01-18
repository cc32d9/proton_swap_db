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
            my $take = 0;
            my %row;
            
            if( $aname eq 'swaplog' )
            {
                $take = 1;
            }
            elsif( $aname eq 'addliqlog' )
            {
                $take = 1;

                if( defined($data->{'lt_added'}) )
                {
                    split_asset(\%row, $data->{'lt_added'}, 'lt_amount', 'lt_symbol');
                }
                elsif( defined($data->{'lt'}) )
                {
                    split_asset(\%row, $data->{'lt'}, 'lt_amount', 'lt_symbol');
                }
                else
                {
                    $take = 0;
                }

                if( $take )
                {
                    split_asset(\%row, $data->{'add_token1'}, 'add_token1_amount', 'add_token1_symbol');
                    split_asset(\%row, $data->{'add_token2'}, 'add_token2_amount', 'add_token2_symbol');
                    
                    split_asset(\%row, $data->{'add_token1_min'}, 'add_token1_min_amount', 'add_token1_min_symbol');
                    split_asset(\%row, $data->{'add_token2_min'}, 'add_token2_min_amount', 'add_token2_min_symbol');
                    
                    $row{'memo'} = $data->{'memo'};
                }
            }
            elsif( $aname eq 'liqrmvlog' )
            {
                $take = 1;

                if( defined($data->{'lt_removed'}) )
                {
                    split_asset(\%row, $data->{'lt_removed'}, 'lt_amount', 'lt_symbol');
                }
                elsif( defined($data->{'lt'}) )
                {
                    split_asset(\%row, $data->{'lt'}, 'lt_amount', 'lt_symbol');
                }
                else
                {
                    $take = 0;
                }
                    
                if( $take )
                {
                    $row{'lt_amount'} *= -1;
                }
            }

            if( $take )
            {
                split_asset(\%row, $data->{'token1'}, 'token1_amount', 'token1_symbol');
                split_asset(\%row, $data->{'token2'}, 'token2_amount', 'token2_symbol');

                if( defined($data->{'pool1'}) and defined($data->{'pool2'}) )
                {
                    split_asset(\%row, $data->{'pool1'}, 'pool1_amount', 'pool1_symbol');
                    split_asset(\%row, $data->{'pool2'}, 'pool2_amount', 'pool2_symbol');

                    $row{'pool_price'} = $row{'pool2_amount'} / $row{'pool1_amount'};
                    $row{'inverted_pool_price'} = $row{'pool1_amount'} / $row{'pool2_amount'};
                    
                    $row{'pool1_contract'} = $data->{'pool1_contract'};
                    $row{'pool2_contract'} = $data->{'pool2_contract'};
                }

                $row{'pool1_swap_amount'} = 0;
                $row{'pool2_swap_amount'} = 0;
                $row{'pool1_liq_amount'} = 0;
                $row{'pool2_liq_amount'} = 0;

                if( $aname eq 'swaplog' )
                {
                    if( $row{'token1_symbol'} eq $row{'pool1_symbol'} )
                    {
                        $row{'pool1_swap_amount'} = $row{'token1_amount'};
                        $row{'pool2_swap_amount'} = $row{'token2_amount'};
                    }
                    else
                    {
                        $row{'pool1_swap_amount'} = $row{'token2_amount'};
                        $row{'pool2_swap_amount'} = $row{'token1_amount'};
                    }
                }
                elsif( $aname eq 'addliqlog' )
                {                    
                    $row{'pool1_liq_amount'} = $row{'token1_amount'};
                    $row{'pool2_liq_amount'} = $row{'token2_amount'};
                }
                elsif( $aname eq 'liqrmvlog' )
                {
                    $row{'pool1_liq_amount'} = $row{'token1_amount'} * -1;
                    $row{'pool2_liq_amount'} = $row{'token2_amount'} * -1;
                }

                $row{'block_num'} = $block_num;
                $row{'time'} = $block_time;
                $row{'tx_id'} = $trace->{'id'};
                $row{'act_type'} = $aname;
                $row{'owner'} = $data->{'owner'};
                    
                my @columns = sort keys %row;                
                my $sth = $main::db->{'dbh'}->prepare
                    ('INSERT INTO swap_ticks (' . join(',', @columns) .
                     ') VALUES (' . join(',', map('?', @columns)) . ')');
                $sth->execute(map($row{$_}, @columns));
            }
        }
    }
}


sub split_asset
{
    my $row = shift;
    my $asset = shift;
    my $name_amount = shift;
    my $name_symbol = shift;

    if( ref($asset) eq 'HASH' )
    {
        $asset = $asset->{'quantity'};
    }

    ($row->{$name_amount}, $row->{$name_symbol}) = split(/\s+/, $asset);
}



sub swaphistory_fork
{
    my $block_num = shift;

    my $dbh = $main::db->{'dbh'};

    my $sth = $dbh->prepare('DELETE FROM swap_ticks where block_num >= ?');
    $sth->execute($block_num);

    print STDERR "fork: $block_num\n";
}




push(@main::prepare_hooks, \&swaphistory_prepare);
push(@main::trace_hooks, \&swaphistory_trace);
push(@main::fork_hooks, \&swaphistory_fork);

1;
