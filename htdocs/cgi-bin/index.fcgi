#!/usr/bin/perl -w -I../../lib/
#
#  Driver for our site.
#
# Steve
# --
#


use strict;
use warnings;


use lib "../lib";


#
#  Use the module
#
use strict;
use warnings;
use CGI::Carp qw/ fatalsToBrowser /;
use CGI::Fast();
use DHCP::Application;



#
#  Load and run - catching errors.
#
eval {
    while ( my $q = CGI::Fast->new() )
    {
        my $a = DHCP::Application->new( QUERY => $q );
        $a->run();
    }
};
if ($@)
{
    print "Content-type: text/plain\n\n";
    print "ERROR: $@";
}



=head1 LICENSE

Copyright (c) 2014 by Steve Kemp.  All rights reserved.

This module is free software;
you can redistribute it and/or modify it under
the same terms as Perl itself.
The LICENSE file contains the full text of the license.

=cut
