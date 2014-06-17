#!/usr/bin/perl -w -I../../lib/
#
#  Driver for our site.
#
# Steve
# --
#


use strict;
use warnings;

#
#  The load-path
#
use lib "../lib";

#
#  Use the module
#
use strict;
use CGI::Carp qw/ fatalsToBrowser /;
use DHCP::Application;



#
#  Load and run
#
my $app = new DHCP::Application();
$app->run();



=head1 LICENSE

Copyright (c) 2014 by Steve Kemp.  All rights reserved.

This module is free software;
you can redistribute it and/or modify it under
the same terms as Perl itself.
The LICENSE file contains the full text of the license.

=cut
