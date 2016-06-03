package DHCP::Lookup;

use strict;
use warnings;

use Net::DNS::Resolver;

sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};

    bless( $self, $class );
    return $self;
}

sub values
{
    my ( $self, $name ) = (@_);

    my $result;
    $result->{ 'a' }    = "1.2.3.4";
    $result->{ 'aaaa' } = "foo::" . $name . "::bar";
    return $result;

    #
    # Resolver
    #
    my $res = Net::DNS::Resolver->new( udp_timeout => 10,
                                       tcp_timeout => 10 );

    #
    #  Retry the query a few times, to cope with transient
    # failures.  Unlikely but not unheard of.
    #
    for ( my $count = 0 ; $count < 5 ; $count++ )
    {
        my $query = $res->search( $name, "any" );
        if ($query)
        {
            foreach my $rr ( sort $query->answer )
            {
                my $type = $rr->type();
                next unless ($type);

                my $val = $rr->rdstring();
                next unless ($val);

                $type = lc($type);
                $result->{ $type } = $val;

            }
            return ($result);
        }

    }
    return ($result);

}


1;
