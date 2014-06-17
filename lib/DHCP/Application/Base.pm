
=head1 NAME

DHCP::Application::Base - A base class for CGI::Application apps.

=head1 DESCRIPTION

This class is a Base-class for a site built with L<CGI::Application>.

This takes care of session setup/teardown, and
contains some utility methods for redirection, etc.

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


#
# Hierarchy.
#
package DHCP::Application::Base;
use base 'CGI::Application';

#
# Standard module(s)
#
use CGI::Session;
use HTML::Template;
use Redis;




=begin doc

Create our session, and connect to redis.

=end doc

=cut

sub cgiapp_init
{
    my $self  = shift;
    my $query = $self->query();

    #
    # Open our redis connection.
    #
    $self->{ 'redis' } = Redis->new();

    my $cookie_name   = 'CGISESSID';
    my $cookie_expiry = '+7d';
    my $sid           = $query->cookie($cookie_name) || undef;

    # session setup
    my $session = CGI::Session->new( "driver:redis",
                                     $sid,
                                     {  Redis  => $self->{ 'redis' },
                                        Expire => 60 * 60 * 24
                                     } );

    #
    # If we can't use Redis then we'll use a filesystem
    # based session-store
    #
    if ( !$session )
    {
        $session = CGI::Session->new( undef, $sid, { Directory => '/tmp' } );
    }


    # assign the session object to a param
    $self->param( session => $session );

    # send a cookie if needed
    if ( !defined $sid or $sid ne $session->id )
    {
        my $cookie = $query->cookie( -name    => $cookie_name,
                                     -value   => $session->id,
                                     -expires => $cookie_expiry,
                                   );
        $self->header_props( -cookie => $cookie );
    }

    binmode STDIN,  ":encoding(utf8)";
    binmode STDOUT, ":encoding(utf8)";

}

=begin doc

Cleanup our session and close our redis connection.

=end doc

=cut

sub teardown
{
    my ($self) = shift;

    #
    #  Flush the sesions
    #
    my $session = $self->param('session');
    $session->flush() if ( defined($session) );

    #
    #  Disconnect.
    #
    my $redis = $self->{ 'redis' };
    $redis->quit() if ($redis);
}



=begin doc

Redirect to the given URL.

=end doc

=cut

sub redirectURL
{
    my ( $self, $url ) = (@_);

    #
    #  Cookie name & expiry
    #
    my $cookie_name   = 'CGISESSID';
    my $cookie_expiry = '+7d';

    #
    #  Get the session identifier
    #
    my $query   = $self->query();
    my $session = $self->param('session');

    my $id = "";
    $id = $session->id() if ($session);

    #
    #  Create/Get the cookie
    #
    my $cookie = $query->cookie( -name    => $cookie_name,
                                 -value   => $id,
                                 -expires => $cookie_expiry,
                               );

    $self->header_add( -location => $url,
                       -status   => "302",
                       -cookie   => $cookie
                     );
    $self->header_type('redirect');
    return "";

}



=begin doc

Load a template from our ./templates directory - which is outside the
web root directory for safety.


If templates.local contains a match first then prefer that.

=end doc

=cut


sub load_template
{
    my ( $self, $file, %options ) = (@_);

    my $path = "";

    foreach my $dir (qw! ../templates.local/ ../../templates.local/ ../templates/ ../../templates/ !)
    {
        $path = $dir if ( -d $dir );
    }
    die "No path" unless ( defined($path) );

    my $template = HTML::Template->new( filename => $file,
                                        path     => [$path],
                                        %options,
                                        die_on_bad_params => 0,
                                      );
    return ($template);
}



=begin doc

Load a file from beneath the project root, if it exists.

=end doc

=cut

sub loadFile
{
    my ( $self, $file ) = (@_);

    my $path;

    foreach my $dir (qw! ../../ ../  ./ !)
    {
        $path = $dir . $file if ( -e $dir . $file );
    }

    return unless ( defined($path) );

    #
    #  Load the file
    #
    my $text = "";

    open( my $handle, "<", $path );
    while ( my $line = <$handle> )
    {
        $text .= $line;
    }
    close($handle);

    return ($text);
}


=begin doc

Called when an unknown mode is encountered.

=end doc

=cut

sub unknown_mode
{
    my ( $self, $requested ) = (@_);

    return ("mode not found $requested");
}




1;


