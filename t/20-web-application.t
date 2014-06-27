#!/usr/bin/perl -Ilib/ -I../lib/
#
#  Test our web-application directly.
#
use strict;
use warnings;


use Test::More qw! no_plan !;

## no critic (Eval)
eval "use Test::WWW::Mechanize::CGIApp";
## use critic
plan skip_all => "Test::WWW::Mechanize::CGIApp required for testing." if $@;


#
#  We'll create a temporary user.
#
BEGIN {use_ok("DHCP::User")}
require_ok("DHCP::User");

#
#  We'll load our application.
#
BEGIN {use_ok("DHCP::Application")}
require_ok("DHCP::Application");



#
#  Load our application - disable redirections
#
my $mech = Test::WWW::Mechanize::CGIApp->new;
$mech->requests_redirectable( [] );


$mech->app("DHCP::Application");
isa_ok( $mech->app(), "DHCP::Application",
        "Loading our application succeeded" );


#
#  Test that some of our run-modes require login, as expected.
#
foreach my $mode (qw! home record edit delete !)
{
    $mech->get_ok("?mode=$mode");

    $mech->content_contains( "You must login",
                             "The mode $mode requires a login" );
}


#
#  Test a login succeeds.
#
my $username = "tmp.test";
my $password = "pass.me";

#
#  Create a helper
#
my $user = DHCP::User->new();

isa_ok( $user, "DHCP::User", "The user-helper has the correct type" );

#
#  Create a user.
#
$user->createUser( $username, $password );

#
#  Login.
#
$mech->get("?mode=login&lname=$username&lpass=$password");
is( $mech->response()->header('Location'), "/home", "Login succeeded" );

#
#  Login we expect to fail.
#
$mech->get("?mode=login&lname=$username&lpass=fail.name");
is( $mech->response()->header('Location'), "/", "Login succeeded" );

#$mech->content_contains( "Welcome Home",
#                         "Login succeeds with correct password." );


#
#  Delete the user.
#
$user->deleteUser($username);
is( $user->present($username), 0, "The user does exist now." );

