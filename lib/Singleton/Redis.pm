
=head1 NAME

Singleton::Redis - A singleton wrapper around a Redis object.

=head1 SYNOPSIS

=for example begin

    #!/usr/bin/perl -w

    use Singleton::Redis;
    use strict;

    my $db = Singleton::Redis->instance();

    $db->set( "foo", "bar" );

=for example end


=head1 DESCRIPTION


This object is a Singleton wrapper around our Redis object.

=cut


package Singleton::Redis;


use strict;
use warnings;


#
#  The Redis module.
#
use Redis;


#
#  The single, global, instance of this object
#
my $_h = undef;



=head2 instance

Gain access to the single instance of our database connection.

=cut

sub instance
{
    $_h ||= (shift)->new();

    return ($_h);
}


=head2 new

Create a new instance of this object.  This is only ever called once
since this object is used as a Singleton.

=cut

sub new
{
    return ( Redis->new() );
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
