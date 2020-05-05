
=head1 NAME

Singleton::DBI - A singleton wrapper around a DBI object.

=head1 SYNOPSIS

=for example begin

    #!/usr/bin/perl -w

    use Singleton::DBI;
    use strict;

    my $db = Singleton::DBI->instance();

    $db->do( "UPDATE users SET cool=1 WHERE username='steve'" );

=for example end


=head1 DESCRIPTION


This object is a Singleton wrapper around our DBI object.

=cut


package Singleton::DBI;


use strict;
use warnings;
use DHCP::Config;


#
#  The DBI modules for accessing the database.
#
use DBI;


#
#  The single, global, instance of this object
#
my $_dbh = undef;



=head2 instance

Gain access to the single instance of our database connection.

=cut

sub instance
{
    $_dbh ||= (shift)->new();

    return ($_dbh);
}


=head2 new

Create a new instance of this object.  This is only ever called once
since this object is used as a Singleton.

=cut

sub new
{

    #
    #  Get our SQLite file.
    #
    my $db = $DHCP::Config::DB_PATH;

    my $create = 0;
    $create = 1 if ( !-e $db );

    my $dbh = DBI->connect( "dbi:SQLite:dbname=$db", "", "" );

    if ($create)
    {

        #
        #  Users
        #
        $dbh->do(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, login, password, email, ip);"
        );

        #
        #  DNS records
        #
        $dbh->do(
             "CREATE TABLE records (id INTEGER PRIMARY KEY, name, token, owner)"
        );

        #
        #  Update logs
        #
        $dbh->do(
            "CREATE TABLE logs (id INTEGER PRIMARY KEY, domain, changed_from, changed_to, ip, owner, timestamp DATE DEFAULT (datetime('now','localtime')))"
        );
    }
    else
    {
        my @tables = $dbh->tables();
        my $found  = 0;
        foreach my $table (@tables)
        {
            $found = 1 if ( $table =~ /logs/i );
        }

        $dbh->do(
            "CREATE TABLE logs (id INTEGER PRIMARY KEY, domain, changed_from, changed_to, ip, owner, timestamp DATE DEFAULT (datetime('now','localtime')))"
          )
          unless ($found);

    }

    return ($dbh);
}



1;



=head1 AUTHOR

Steve Kemp

http://www.steve.org.uk/

=cut



=head1 LICENSE

Copyright (c) 2014 by Steve Kemp.  All rights reserved.

This module is free software;
you can redistribute it and/or modify it under
the same terms as Perl itself.
The LICENSE file contains the full text of the license.

=cut
