
=head1 NAME

DHCP::Records - DNS-Record Related code.

=head1 DESCRIPTION

This module is used to interface with Amazon and set/delete DNS records.

There is no facility to retrieve the current values of the records, as
we use DNS directly for that.  This is more efficient in our UI as
we only ever need to show a few records, and making DNS-lookups scales
better than having to fetch the whole zone-name, and parse it.

(Amazon lets you fetch a zone, but internally it requests N records,
and then allows you to continue fetching more in chunks.)

=cut

=head1 AUTHOR

Steve Kemp <steve@steve.org.uk>

=cut

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 Steve Kemp <steve@steve.org.uk>.

This library is free software. You can modify and or distribute it under
the same terms as Perl itself.

=cut


use strict;
use warnings;

package DHCP::Records;


# This must be renamed - it isn't in the repository.
use DHCP::Config;

use WebService::Amazon::Route53;
use JSON;

=begin doc

Constructor.

=end doc

=cut

sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};

    #
    #  Create the helper.
    #
    $self->{ 'r53' } =
      WebService::Amazon::Route53->new( id  => $DHCP::Config::ROUTE_53_ID,
                                        key => $DHCP::Config::ROUTE_53_KEY );


    bless( $self, $class );
    return $self;

}



=begin doc

Remove an existing record.  This is used either:

* When a user clicks `delete` on a name/record.
* When an account is removed.

=end doc

=cut

sub removeRecord
{
    my ( $self, $record, $type, $ip ) = (@_);

    my $res = $self->{ 'r53' }->change_resource_record_sets(
        zone_id => $DHCP::Config::ZONE_ID,
        changes => [

            # Delete the current record
            {  action => 'delete',
               name   => "$record.$DHCP::Config::ZONE",
               type   => $type,
               ttl    => $DHCP::Config::TTL,
               value  => $ip,
            },
        ] );

    if ( !$res )
    {
        use Data::Dumper;
        print STDERR Dumper( $self->{ 'r53' }->error() );
    }
}



=begin doc

Add/Change a record.

=end doc

=cut

sub createRecord
{
    my ( $self, $record, $type, $ip ) = (@_);

    #
    #  This is just here to remove the invalid record
    # it will probably fail - because active users won't
    # have this record in place.
    #
    #  Remove in a few days.
    #
    my $tmp = $self->{ 'r53' }->change_resource_record_sets(
        zone_id => $DHCP::Config::ZONE_ID,
        changes => [

            # Create the record
            {  action => 'DELETE',
               name   => "$record.$DHCP::Config::ZONE",
               type   => "CNAME",
               ttl    => 3600,
               value  => "invalid.dhcp.io",
            },
        ] );

    my $res = $self->{ 'r53' }->change_resource_record_sets(
        zone_id => $DHCP::Config::ZONE_ID,
        changes => [

            # Create the record
            {  action => 'upsert',
               name   => "$record.$DHCP::Config::ZONE",
               type   => $type,
               ttl    => $DHCP::Config::TTL,
               value  => $ip,
            },
        ] );

    if ( !$res )
    {
        use Data::Dumper;
        print STDERR Dumper( $self->{ 'r53' }->error() );
    }

}

1;
