
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

Lookup the user from the token.

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
    #  The type of the record.
    #
    my $type = 'A';

    $type = 'AAAA' if ( $ip =~ /:/ );

    #
    #  Look for the old value of the zone being updated.
    #
    #  Amazon won't let you apply a "set foo.example.com = 1.2.3.4",
    # if the `foo` record exists you must delete it, and recreate it.
    #
    #  Annoyingly deleting without the correct/current value will fail,
    # so you need to search the existing zone to find the old IP.
    #
    my $old_ip = undef;

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


        if ( $next->{ 'name' } )
        {
            $tmp_name = $next->{ 'name' };
            $tmp_type = $next->{ 'type' };
        }
        else
        {
            $cont = 0;
        }


        foreach my $existing (@$record_sets)
        {
            next
              unless ( $existing->{ 'name' } eq "$record.$DHCP::Config::ZONE" );
            $old_ip = $existing->{ 'records' }[0];
        }
    }

    if ($old_ip)
    {
        my $res = $r53->change_resource_record_sets(
            zone_id => $DHCP::Config::ZONE_ID,
            changes => [

                # Delete the current A record
                {  action => 'delete',
                   name   => "$record.$DHCP::Config::ZONE",
                   type   => $type,
                   ttl    => 60,
                   value  => $old_ip,
                },
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

    return ( $redis->get("DHCP:USER:$pass") );

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

    return 1 if ( !defined($user) || !length($user) );

    $user = lc($user);

    foreach my $denied (qw! www admin secure !)
    {
        return 1 if ( $denied eq $user
                    );
    }

    return 0;
}
1;
