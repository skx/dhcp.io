#!/usr/bin/perl -Ilib/ -I../lib/

use strict;
use warnings;


use Test::More qw! no_plan !;

BEGIN {use_ok("DHCP::User")}
require_ok("DHCP::User");
BEGIN {use_ok("Singleton::DBI")}
require_ok("Singleton::DBI");


#
#  Generate a temporary username
#
my $username;
my @chars = ( "A" .. "Z", "a" .. "z" );
$username .= $chars[rand @chars] for 1 .. 8;



#
#  Should we skip?
#
my $skip = 0;


#
#  Ensure that we have Redis installed.
#
## no critic (Eval)
eval "use Redis";
## use critic
$skip = 1 if ($@);


#
# Connect to redis
#
my $redis;
eval {$redis = new Redis();};
$skip = 1 if ($@);
$skip = 1 unless ($redis);
$skip = 1 unless ( $redis && $redis->ping() );


SKIP:
{

    skip "Redis must be running on localhost" unless ( !$skip );


    #
    # Test the username
    #
    is( length($username), 8, "Generated 8 character long username " );


    #
    # Create the helper
    #
    my $u = DHCP::User->new( redis => $redis,
                             db    => Singleton::DBI->instance() );
    isa_ok( $u, "DHCP::User", "Our object has the right type" );

    #
    # Try to find the user.
    #
    is( $u->present($username), 0, "The user doesn't exist: $username." );


    #
    #  A login will fail if the user doesn't exist.
    #
    is( $u->testLogin( $username, $username ),
        undef, "Login fails with missing user." );
    is( $u->testLogin( lc($username), $username ),
        undef, "Login fails with missing user." );

    #
    #  Create the user
    #
    my $email = $username . '@' . $username . '.com';

    $u->createUser( $username, $username, $email );
    is( $u->present($username), 1, "The user does exist now." );

    #
    #  Ensure the login works
    #
    is( $u->testLogin( $username, $username ), lc($username), "Login works" );
    is( $u->testLogin( lc($username), $username ),
        lc($username), "Login works" );


    #
    #  Find the user by email
    #
    my $found = $u->find($username);
    is( lc $username, $found, "Finding user by username succeeds" );
    $found = $u->find($email);
    is( lc $username, $found, "Finding user by email succeeds" );


    #
    #  Change the user's email address
    #
    $u->set_email( user => $username,
                   mail => 'steve@steve.org.uk' );

    #
    #  Ensure the previous find fails, and the new one succeeds.
    #
    $found = $u->find($email);
    is( undef, $found, "Finding user by mail fails when it is changed" );
    $found = $u->find('steve@steve.org.uk');
    is( lc $username, $found, "Finding user by (new) email succeeds" );


    #
    #  Change the users password and re-test login.
    #
    $u->set_pass( user => $username,
                  pass => '1234luggage' );

    is( $u->testLogin( $username, $username ),
        undef, "Login fails when password changed" );
    is( $u->testLogin( lc($username), '1234luggage' ),
        lc($username), "Login works with new password" );

    #
    #  Delete the user
    #
    $u->deleteUser($username);
    is( $u->present($username), 0, "The user does exist now." );

}

#
#  Test that expected usernames are forbidden.
#
my $u = DHCP::User->new( redis => $redis,
                         db    => Singleton::DBI->instance() );

foreach my $name (qw! www admin ipv4 ipv6 !)
{
    is( $u->forbidden($name), 1, "Expected username is forbidden: $name" );
}
