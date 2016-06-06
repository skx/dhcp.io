
=head1 NAME

DHCP::Lookup - Perform DNS lookups.

=head1 DESCRIPTION

This module is used to perform DNS lookups of given hostnames, it is
used in our code to show the B<existing> value(s) for a given name.

For example we'll lookup the value of C<skx.dhcp.io> to return:

=for example begin

     $result->{'a'}   = "127.0.0.1";
     $result->{'aaaa'} = "fe80::1";

=for example end

Our code used to query the current values by querying the Amazon
Route53 infrastructure directly, this is admittedly more reliable
but the overhead was too high given the size of our domain.

=cut

=head1 AUTHOR

Steve Kemp <steve@steve.org.uk>

=cut

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 Steve Kemp <steve@steve.org.uk>.

This library is free software. You can modify and or distribute it under
the same terms as Perl itself.

=cut


package DHCP::Lookup;

use strict;
use warnings;

use Net::DNS::Resolver;


=begin doc

Constructor

=end doc

=cut

sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};

    bless( $self, $class );
    return $self;
}


=begin doc

Lookup the values of the given name.  We use type C<any> when making
the query, such that we can discover both C<A> and C<AAAA> records.

=end doc

=cut

sub values
{
    my ( $self, $name ) = (@_);

    my $result;

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
