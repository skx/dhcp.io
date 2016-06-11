
=head1 NAME

DHCP::User - User/Record-Related code.

=head1 MIGRATION

This requires a new table to be created in C<~/db.db>:

=for example begin

   CREATE TABLE passwords( id INTEGER PRIMARY KEY, hash, owner );

=for example end

=cut


=head1 DESCRIPTION

This module contains the code relating to usernames/passwords,
which tests logins etc.  It supports a legacy system, and will
auto-migrate to bcrypt as users login.

=cut

=head1 AUTHOR

Steve Kemp <steve@steve.org.uk>

=cut

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 Steve Kemp <steve@steve.org.uk>.

This library is free software. You can modify and or distribute it under
the same terms as Perl itself.

=cut



use strict;
use warnings;

package DHCP::User::Auth;

use DHCP::Config;
use Singleton::DBI;


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

Test whether a given login is valid.

=end doc

=cut

sub test_login
{
    my ( $self, %params ) = (@_);

    return 0 unless ( $params{ 'username' } );
    return 0 unless ( $params{ 'password' } );

    if ( $self->_is_new( $params{ 'username' } ) )
    {
        return ( $self->test_login_new(%params) );
    }
    else
    {
        my $result = $self->test_login_old(%params);

        if ( $result )
        {
            #
            # Set the password here - so that we migrate
            # to bcrypt.
            #
            $self->set_password( username => $params{'username'} ,
                                 password => $params{'password'} );
        }
        return( $result ):
    }
}


=begin doc

Update a user's password.

=end doc

=cut

sub set_password
{
    my ( $self, %params ) = (@_);

    my $user = $params{ 'username' };
    my $pass = $params{ 'password' };

    $user = lc($user);

    #
    #  We're only going to set the password in the new
    # table - so we don't need to make this conditional
    # at all
    #


    #
    #  Find the user_id
    #

    #
    #  Delete any existing record
    #

    #
    #  Set the password.
    #
}


=begin doc

Has this user got a new-style, salted, password?

=end doc

=cut

sub _is_new
{
    my ( $self, $login ) = (@_);

    my $db = Singleton::DBI->instance() || die "Missing DB-handle";
    my $sql =
      $db->prepare(
        "SELECT a.hash FROM passwords AS a JOIN users AS b WHERE a.owner=b.id AND b.login=?"
      ) or
      die "Failed to prepare";

    $sql->execute($login) or
      die "Failed to execute";
    my $found = $sql->fetchrow_array();

    return ( $found ? 1 : 0 );
}


=begin doc

Test a username/password for validity with the old-scheme.

=end doc

=cut

sub test_login_old
{
    my ( $self, %params ) = (@_);

    my $user = $params{ 'username' };
    my $pass = $params{ 'password' };

    $user = lc($user);

    #
    #  Hash the users password with our Salt
    #
    my $sha = Digest::SHA->new();
    $sha->add($DHCP::Config::SALT);
    $sha->add($pass);
    my $hash = $sha->hexdigest();

    #
    #  Lookup
    #
    my $db = Singleton::DBI->instance() || die "Missing DB-handle";

    my $sql =
      $db->prepare("SELECT login FROM users WHERE ( login=? AND password=? )")
      or
      die "Failed to prepare";

    $sql->execute( $user, $hash ) or
      die "Failed to execute";
    my $found = $sql->fetchrow_array();

    return ( $found ? $found : undef );
}


=begin doc

Test the given login/password for validity with the new-style
bcrypt setup.

=end doc

=cut

sub test_login_new
{
    my ( $self, %params ) = (@_);
}


1;
