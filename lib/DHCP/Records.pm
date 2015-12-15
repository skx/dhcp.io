
=head1 NAME

DHCP::Records - DNS-Record Related code.

=head1 DESCRIPTION

This module is used to interface with Amazon and get/set DNS records.

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

use Singleton::Redis;
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

Return all records beneath our main zone.

The return value is a nested hash:

=for example begin

   $result{'a'}{'foo'} = "1.2.3.3";
   $result{'a'}{'bar'} = "1.2.3.5";
   $result{'aaaa'}{'foo'} = "::1";
   $result{'aaaa'}{'bar'} = "::1";

=for example end

=end doc

=cut

sub getRecords
{
    my ($self) = (@_);

    my $result;

    #
    #  Lookup in cache first
    #
    my $redis  = Singleton::Redis->instance();
    my $cached = $redis->get("DHCP:CACHED:ZONE");
    if ($cached)
    {
        $result = from_json($cached);
        return ($result);
    }

    #
    #  These are here to provide an offset in the iteration case.
    #
    #  The "fetch records" call will return no more than 100 records
    # at a time.
    #
    my $cont     = 1;
    my $tmp_name = undef;
    my $tmp_type = undef;

    while ($cont)
    {
        my ( $record_sets, $next ) =
          $self->{ 'r53' }->list_resource_record_sets(
                                              zone_id => $DHCP::Config::ZONE_ID,
                                              name    => $tmp_name,
                                              type    => $tmp_type
          );

        #
        #  Should we continue looping for more records?
        #
        if ( $next->{ 'name' } )
        {
            $tmp_name = $next->{ 'name' };
            $tmp_type = $next->{ 'type' };
        }
        else
        {
            $cont = 0;
        }


        #
        #  OK is the record we're looking for in the current batch?
        #
        foreach my $existing (@$record_sets)
        {
            my $type = $existing->{ 'type' };
            my $name = $existing->{ 'name' };
            $name = $1 if ( $name =~ /^([^.]+).(.*)/ );

            my $data = $existing->{ 'records' }[0];

            $result->{ $type }{ $name } = $data;
        }
    }

    #
    #  Store in the cache
    #
    $redis->set( "DHCP:CACHED:ZONE", to_json($result) );

    return ($result);
}


=begin doc

Remove an existing record.

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

    #
    #  Remove the cached values - which are now invalid.
    #
    Singleton::Redis->instance()->del("DHCP:CACHED:ZONE");

}



=begin doc

Create a new record.

=end doc

=cut

sub createRecord
{
    my ( $self, $record, $type, $ip ) = (@_);

    my $res = $self->{ 'r53' }->change_resource_record_sets(
        zone_id => $DHCP::Config::ZONE_ID,
        changes => [

            # Create the record
            {  action => 'create',
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

    #
    #  Remove the cached values - which are now invalid.
    #
    Singleton::Redis->instance()->del("DHCP:CACHED:ZONE");
}


=begin doc

Lookup the current values of the given record.

Return both the IPv4 and IPv6 records - if available.

=end doc

=cut

sub lookup
{
    my ( $self, $name ) = (@_);

    my $result;

    my $existing = $self->getRecords();
    $result->{ 'ipv4' } = $existing->{ "A" }{ $name }    || undef;
    $result->{ 'ipv6' } = $existing->{ "AAAA" }{ $name } || undef;

    return ($result);
}


1;
