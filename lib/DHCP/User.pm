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

# Our code
use DHCP::Records;
use DHCP::Config;
use Singleton::DBI;

# Standard modules.
use Digest::SHA;
use Data::UUID::LibUUID;


=begin doc

Constructor.

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

Create a new user on the system.

=end doc

=cut

sub createUser
{
    my ( $self, $user, $pass, $mail, $ip ) = (@_);

    $user = lc($user);


    #
    #  Now hash the users password with our Salt
    #
    my $sha = Digest::SHA->new();
    $sha->add($DHCP::Config::SALT);
    $sha->add($pass);
    my $hash = $sha->hexdigest();

    my $db = Singleton::DBI->instance() || die "Missing DB-handle";
    my $sql = $db->prepare(
                "INSERT INTO users (login,password,email,ip) VALUES( ?,?,?,?)");
    $sql->execute( $user, $hash, $mail, $ip );
    $sql->finish();

    #
    #  Get the user-id
    #
    $sql = $db->prepare("SELECT id FROM users WHERE login=?") or
      die "Failed to prepare statement";
    $sql->execute($user) or
      die "Failed to execute statement";
    my $user_id = $sql->fetchrow_array();
    $sql->finish();

    #
    # Now add a new record for them.
    #
    $sql =
      $db->prepare("INSERT INTO records( name, token, owner ) VALUES( ?,?,?)")
      or
      die "Failed to prepare statement";
    $sql->execute( $user, new_uuid_string(), $user_id ) or
      die "Failed to execute statement";
    $sql->finish();
}


=begin doc

Add a record to the user's set

=end doc

=cut

sub addRecord
{
    my ( $self, $user, $name ) = (@_);

    my $db = Singleton::DBI->instance() || die "Missing DB-handle";

    #
    #  Get the user-id
    #
    my $sql = $db->prepare("SELECT id FROM users WHERE login=?") or
      die "Failed to prepare statement";
    $sql->execute($user) or
      die "Failed to execute statement";
    my $user_id = $sql->fetchrow_array();
    $sql->finish();

    die "No user ID" unless ( $user_id && ( $user_id =~ /^([0-9]+)$/ ) );
    $sql =
      $db->prepare("INSERT INTO records( name, token, owner ) VALUES( ?,?,?)")
      or
      die "Failed to prepare statement";
    $sql->execute( $name, new_uuid_string(), $user_id ) or
      die "Failed to execute statement";
    $sql->finish();

}


=begin doc

Does the given record exist?

=end doc

=cut

sub recordPresent
{
    my ( $self, $name ) = (@_);

    my $db = Singleton::DBI->instance() || die "Missing DB-handle";
    my $sql = $db->prepare("SELECT name FROM records WHERE name=?");
    $sql->execute($name);
    my $found = $sql->fetchrow_array() || "";
    $sql->finish();

    return ( $found ? $found : undef );

}


=begin doc

Delete a user, by username.

=end doc

=cut

sub deleteUser
{
    my ( $self, $user ) = (@_);

    $user = lc($user);

    #
    #  Get all data pertaining to this user, so that we can delete
    # their DNS records
    #
    my $data = $self->getAllData($user);

    #
    # Create a helper for removing the old DNS records.
    #
    my $helper = DHCP::Records->new( redis => $self->{ 'redis' } );

    foreach my $entry (@$data)
    {
        if ( $entry->{ 'ipv4' } )
        {
            $helper->removeRecord( $entry->{ 'name' }, "A",
                                   $entry->{ 'ipv4' } );
        }
        if ( $entry->{ 'ipv6' } )
        {
            $helper->removeRecord( $entry->{ 'name' },
                                   "AAAA", $entry->{ 'ipv6' } );

        }
    }


    #
    #  Get the user-id
    #
    my $db = Singleton::DBI->instance() || die "Missing DB-handle";
    my $sql = $db->prepare("SELECT id FROM users WHERE login=?") or
      die "Failed to prepare statement";
    $sql->execute($user) or
      die "Failed to execute statement";
    my $user_id = $sql->fetchrow_array();
    $sql->finish();

    #
    #  Delete the records from the database.
    #
    $sql = $db->prepare("DELETE FROM records WHERE owner=?") or
      die "Failed to prepare";
    $sql->execute($user_id);
    $sql->finish();

    #
    #  Delete the user from the database.
    #
    $sql = $db->prepare("DELETE FROM users WHERE id=?") or
      die "Failed to prepare";
    $sql->execute($user_id);
    $sql->finish();

}


=begin doc

Find the user who owns the given domain.

=end doc

=cut

sub getOwnerFromDomain
{
    my ( $self, $record ) = (@_);

    #
    #  Fetch the zones and tokens.
    #
    my $db = Singleton::DBI->instance() || die "Missing DB-handle";

    my $sql = $db->prepare(
        "SELECT a.login FROM users AS a JOIN records AS b WHERE ( a.id=b.owner AND b.name =?) "
      ) or
      die "Failed to prepare";
    $sql->execute($record) or die "Failed to execute:" . $db->errstr();


    my $found = $sql->fetchrow_array();

    return ($found);
}


=begin doc

Discover which record corresponds to the specified token.

=end doc

=cut

sub getUserFromToken
{
    my ( $self, $token ) = (@_);

    my $db = Singleton::DBI->instance() || die "Missing DB-handle";

    my $sql = $db->prepare("SELECT name FROM records WHERE token=?") or
      die "Failed to prepare statement";
    $sql->execute($token) or
      die "Failed to execute statement";
    my $name = $sql->fetchrow_array();
    $sql->finish();

    return ($name);
}



=begin doc

Set the value of a record to the given IP.

This invokes the Amazon Route53 API to do the necessary.  It is an uglier
method than I'd like.

=end doc

=cut

sub setRecord
{
    my ( $self, $record, $ip, $owner ) = (@_);

    #
    # Create a helper
    #
    my $helper = DHCP::Records->new( redis => $self->{ 'redis' } );

    #
    #  Get the existing records - we need to see if the record
    # we're setting a new value to an existing record, or creating a new one.
    #
    my $existing = $helper->getRecords();

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
    my $old_ip = $existing->{ $type }{ $record } || undef;


    #
    #  If we have an old IP and it is not different to the new IP
    # then we do nothing.
    #
    if ( ( $old_ip && $ip ) &&
         ( $old_ip eq $ip ) )
    {
        return;
    }

    #
    #  If we got the old IP then we have to apply a "delete" + "create"
    # pair of events.
    #
    if ($old_ip)
    {
        $helper->removeRecord( $record, $type, $old_ip );
    }

    $helper->createRecord( $record, $type, $ip );

    #
    #  Get the user-id
    #
    my $db = Singleton::DBI->instance() || die "Missing DB-handle";

    my $sql = $db->prepare("SELECT id FROM users WHERE login=?") or
      die "Failed to prepare statement";
    $sql->execute($owner) or
      die "Failed to execute statement";
    my $user_id = $sql->fetchrow_array();
    $sql->finish();

    #
    #  Log the update.
    #
    $sql = $db->prepare(
        "INSERT INTO logs (domain,changed_from, changed_to, ip, owner) VALUES(?,?,?,?,?);"
      ) or
      die "Failed to prepare statement:" . $db->errstr();
    $sql->execute( $record, $old_ip, $ip, $ENV{ 'REMOTE_ADDR' }, $user_id ) or
      die "Failed to execute statement";
    $sql->finish();

}




=begin doc

Get the data belonging to the user. names/tokens belonging to the given user.

=end doc

=cut

sub getAllData
{
    my ( $self, $user ) = (@_);

    my $results;

    #
    # Lookup the live values of all zones.
    #
    my $tmp = DHCP::Records->new( redis => $self->{ 'redis' } );
    my $live = $tmp->getRecords();


    #
    #  Fetch the zones and tokens.
    #
    my $db = Singleton::DBI->instance() || die "Missing DB-handle";

    my $sql = $db->prepare(
        "SELECT a.name,a.token FROM records AS a JOIN users AS b WHERE ( a.owner = b.id AND b.login=? ) ORDER BY a.name ASC"
      ) or
      die "Failed to prepare";
    $sql->execute($user) or die "Failed to execute";


    my ( $dom, $token );
    $sql->bind_columns( undef, \$dom, \$token );

    while ( $sql->fetch() )
    {
        my $present = $live->{ 'A' }{ $dom } || $live->{ 'AAAA' }{ $dom };
        push( @$results,
              {  name    => $dom,
                 token   => $token,
                 present => $present,
                 ipv4    => $live->{ 'A' }{ $dom } ? $live->{ 'A' }{ $dom } :
                   undef,
                 ipv6 => $live->{ 'AAAA' }{ $dom } ? $live->{ 'AAAA' }{ $dom } :
                   undef,
              } );

    }
    $sql->finish();

    return ($results);
}


=begin doc

Test a login.

Return undef on failure, otherwise return the username.

=end doc

=cut

sub testLogin
{
    my ( $self, $user, $pass ) = (@_);

    $user = lc($user);

    #
    #  Hash the users password with our Salt
    #
    my $sha = Digest::SHA->new();
    $sha->add($DHCP::Config::SALT);
    $sha->add($pass);
    my $hash = $sha->hexdigest();

    #
    #  Does the user exist?  If not then it's a failure.
    #
    return unless ( $self->present($user) );


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

Is the given username already present?

=end doc

=cut

sub present
{
    my ( $self, $user ) = (@_);

    $user = lc($user) if ($user);

    my $db = Singleton::DBI->instance() || die "Missing DB-handle";
    my $sql = $db->prepare("SELECT login FROM users WHERE login=?");
    $sql->execute($user);
    my $found = $sql->fetchrow_array() || undef;
    $sql->finish();

    return ( $found ? 1 : 0 );

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

    foreach my $denied (@DHCP::Config::FORBIDDEN)
    {
        return 1 if ( $denied eq $user );
    }

    return 0;
}


=begin doc

Return the most recent logs.

=end doc

=cut

sub logs
{
    my ( $self, $user ) = (@_);

    my $logs;
    $user = lc($user) if ($user);

    my $db = Singleton::DBI->instance() || die "Missing DB-handle";

    my $sql = $db->prepare(
        "SELECT a.domain,a.changed_from,a.changed_to,a.ip,a.timestamp FROM logs AS a JOIN users AS b WHERE ( a.owner = b.id AND b.login=? ) ORDER by a.id ASC LIMIT 100"
      ) or
      die "Failed to prepare" . $db->errstr();

    $sql->execute($user) or die "Failed to execute";

    my ( $record, $old, $new, $source, $time );
    $sql->bind_columns( undef, \$record, \$old, \$new, \$source, \$time );

    while ( $sql->fetch() )
    {
        push( @$logs,
              {  old    => $old,
                 new    => $new,
                 record => $record,
                 source => $source,
                 time   => $time
              } );
    }


    $sql->finish();

    return ($logs);
}
1;
