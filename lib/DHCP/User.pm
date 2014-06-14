# -*- cperl -*- #

=head1 NAME

DHCP::User - User/Record-Related code.

=head1 DESCRIPTION

This module allows the creation/login-testing of users.

Since usernames are record names this module also contains code
for setting the value of a name.

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

package DHCP::User;


# This must be renamed - it isn't in the repository.
use DHCP::Config;

# Standard modules.
use Data::UUID::LibUUID;
use WebService::Amazon::Route53;


=begin doc

Constructor.

Save away the redis handle we're given.

=end doc

=cut

sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{ 'redis' } = $supplied{ 'redis' } || die "Missing Redis handle";

    bless( $self, $class );
    return $self;

}


=begin doc

Create a new user on the system.

=end doc

=cut

sub createUser
{
    my ( $self, $user, $pass ) = (@_);

    $user = lc($user);

    my $redis = $self->{ 'redis' } || die "Missing handle";

    # set their login details.
    $redis->set( "DHCP:USER:$user", $pass );

    # set their token
    my $uid = new_uuid_string();
    $redis->set( "DHCP:USER:$user:TOKEN", $uid );
    $redis->set( "DHCP:TOKEN:$uid",       $user );
}


=begin doc

Discover which username (read DNS record) the given token represents.

=end doc

=cut

sub getUserFromToken
{
    my ( $self, $token ) = (@_);

    my $redis = $self->{ 'redis' } || die "Missing handle";
    return ( $redis->get("DHCP:TOKEN:$token") );
}



=begin doc

Set the value of a record to the given IP.

This invokes the Amazon Route53 API to do the necessary.  It is an uglier
method than I'd like.

=end doc

=cut

sub setRecord
{
    my ( $self, $record, $ip ) = (@_);

    #
    #  Create the helper.
    #
    my $r53 =
      WebService::Amazon::Route53->new( id  => $DHCP::Config::ROUTE_53_ID,
                                        key => $DHCP::Config::ROUTE_53_KEY );


    #
    #  The type of the record we're dealing with.
    #
    my $type = 'A';
    $type = 'AAAA' if ( $ip =~ /:/ );

    #
    #  Look for the old value of the zone being updated.
    #
    #  Amazon won't let you say "set foo.example.com = 1.2.3.4",
    # if the `foo` record exists you must delete it, and then recreate it.
    #
    #  Annoyingly deleting without the correct/current value will fail,
    # so you need to search the existing zone to find the old IP.
    #
    my $old_ip = undef;


    #
    #  These are here to provide an offset in the iteration case.
    #
    #  The "fetch records" call will return no more than 100 records
    # at a time.  Currently the dhcp.io zone has 5 records, but we
    # should be prepared...
    #
    my $cont     = 1;
    my $tmp_name = undef;
    my $tmp_type = undef;

    while ($cont)
    {
        my ( $record_sets, $next ) =
          $r53->list_resource_record_sets( zone_id => $DHCP::Config::ZONE_ID,
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

            #
            #  Skip unless the record is a match.
            #
            next
              unless ( $existing->{ 'name' } eq "$record.$DHCP::Config::ZONE" );

            #
            #  Get the old/current IP.
            #
            $old_ip = $existing->{ 'records' }[0];
        }
    }


    #
    #  If we got the old IP then we have to apply a "delete" + "create"
    # pair of events.
    #
    if ($old_ip)
    {
        my $res = $r53->change_resource_record_sets(
            zone_id => $DHCP::Config::ZONE_ID,
            changes => [

                # Delete the current record
                {  action => 'delete',
                   name   => "$record.$DHCP::Config::ZONE",
                   type   => $type,
                   ttl    => 60,
                   value  => $old_ip,
                },

                # Add the new record.
                {  action => 'create',
                   name   => "$record.$DHCP::Config::ZONE",
                   type   => $type,
                   ttl    => 60,
                   value  => $ip,
                },
            ] );
    }
    else
    {

        #
        #  The record isn't present.  Create it.
        #
        my $res =
          $r53->change_resource_record_sets(
                           zone_id => $DHCP::Config::ZONE_ID,
                           changes => [{ action => 'create',
                                         name  => "$record.$DHCP::Config::ZONE",
                                         type  => $type,
                                         ttl   => 60,
                                         value => $ip,
                                       },
                                      ] );
    }

}


=begin doc

Get the token belonging to the given user.

=end doc

=cut

sub getToken
{
    my ( $self, $user ) = (@_);

    my $redis = $self->{ 'redis' } || die "Missing handle";
    return ( $redis->get("DHCP:USER:$user:TOKEN") );
}


=begin doc

Test a login.

=end doc

=cut

sub testLogin
{
    my ( $self, $user, $pass ) = (@_);

    my $redis = $self->{ 'redis' } || die "Missing handle";

    #
    #  Does the user exist?
    #
    return undef unless ( $self->present($user) );

    #
    #  Get the password - TODO: Hashing.
    #
    my $epass = $redis->get("DHCP:USER:$user");
    return $user if ( $epass eq $pass );

    return undef;

}


=begin doc

Is the given username already present?

=end doc

=cut

sub present
{
    my ( $self, $user ) = (@_);

    my $redis = $self->{ 'redis' };
    return 1 if ( defined( $redis->get("DHCP:USER:$user") ) );
    return 0;

}

=begin doc

Is the given username forbidden?

=end doc

=cut

sub forbidden
{
    my ( $self, $user ) = (@_);

    # Missing username?  Invalid.
    return 1 if ( !defined($user) || !length($user) );

    # Containing invalid characters?  Invalid.
    return 1 unless ( $user =~ /^([a-z0-9]+)$/i );

    $user = lc($user);

    foreach
      my $denied (qw! www admin secure official steve kemp notice secret !)
    {
        return 1 if ( $denied eq $user );
    }

    return 0;
}
1;
