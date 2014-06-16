
=head1 NAME

CGI::Application::Plugin::Throttle - Rate-Limiting for CGI::Application-based applications, using Redis for persistence.

=head1 SYNOPSIS

  use CGI::Application::Plugin::Throttle;


  # Your application
  sub setup {
    ...

    # Create a redis handle
    my $redis = Redis->new();

    # Configure throttling
    $self->throttle()->configure( redis => $redis,
                                  prefix => "REDIS:KEY:PREFIX",
                                  limit => 100,
                                  period => 60,
                                  exceeded => "slow_down_champ" );


=cut


=head1 DESCRIPTION

This module allows you to enforce a throttle on incoming requests to
your application, based upon the remote IP address.

This module stores a count of accesses in a Redis key-store, and
once hits from a particular source exceeed the specified threshold
the user will be redirected to the run-mode you've specified.

=cut


=head1 POTENTIAL ISSUES / CONCERNS

Users who share IP addresses, because they are behind a common-gateway
for example, will all suffer if the threshold is too low.  We attempt to
mitigate this by building the key using a combination of the remote
IP address, and the remote user-agent.

This module will apply to all run-modes, because it seems likely that
this is the most common case.  If you have a preference for some modes
to be excluded please do contact the author.

=cut




use strict;
use warnings;

package CGI::Application::Plugin::Throttle;


our $VERSION = '0.3';


=head1 METHODS


=head2 import

Force the C<throttle> method into the caller's namespace, and
configure the prerun hook which is used by L<CGI::Application>.

=cut

sub import
{
    my $pkg     = shift;
    my $callpkg = caller;

    {
        no strict qw(refs);
        *{ $callpkg . '::throttle' } = \&throttle;
    }

    if ( UNIVERSAL::can( $callpkg, "add_callback" ) )
    {
        $callpkg->add_callback( 'prerun' => \&throttle_callback );
    }

}


=head2 new

Constructor.

This method is used internally, and not expected to be invoked externally.

The defaults are setup here, although they can be overridden in the
L</"configure"> method.

=cut

sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};

    #
    #  Configure defaults.
    #
    $self->{ 'limit' }  = 100;
    $self->{ 'period' } = 60;
    $self->{ 'prefix' } = "THROTTLE";

    #
    #  Run mode to redirect to on exceed.
    #
    $self->{ 'exceeded' } = "slow_down";


    bless( $self, $class );
    return $self;
}



=head2 throttle

Gain access to the throttle object.

=cut

sub throttle
{
    my $cgi_app = shift;
    return $cgi_app->{ __throttle_obj } if $cgi_app->{ __throttle_obj };

    my $throttle = $cgi_app->{ __throttle_obj } = __PACKAGE__->new();
    return $throttle;
}



=head2 _get_redis_key

Build and return the Redis key to use for this particular remote
request.

The key is built from the C<prefix> string set in L</"configure"> method,
along with:

=over 8

=item The remote IP address of the client.

=item The remote HTTP Basic-Auth username of the client.

=item The remote User-Agent

=back

=cut

sub _get_redis_key
{
    my $self = shift;
    my $key  = $self->{ 'prefix' };

    #
    #  Build up the key based on the:
    #
    #  1.  User using HTTP Basic-Auth, if present.
    #  2.  The remote IP address.
    #  3.  The remote user-agent.
    #
    foreach my $env (qw! REMOTE_USER REMOTE_ADDR HTTP_USER_AGENT !)
    {
        if ( $ENV{ $env } )
        {
            $key .= ":";
            $key .= $ENV{ $env };
        }
    }

    return ($key);
}


=head2 count

Return the number of times the remote client has hit a run mode, along
with the maximum allowed visits:

=for example begin

      sub your_run_mode
      {
          my ($self) = (@_);

          my( $count, $max ) = $self->throttle()->count();
          return( "$count visits seen - maximum is $max." );
      }

=for example end

=cut

sub count
{
    my ($self) = (@_);

    my $visits = 0;
    my $max    = $self->{ 'limit' };

    if ( $self->{ 'redis' } )
    {
        my $key = $self->_get_redis_key();
        $visits = $self->{ 'redis' }->get($key);
    }
    return ( $visits, $max );
}


=head2 throttle_callback

This method is invoked by L<CGI::Application>, as a hook.

The method is responsible for determining whether the remote client
which triggered the current request has exceeded their request
threshold.

If the client has made too many requests their intended run-mode will
be changed to to redirect them.

=cut

sub throttle_callback
{
    my $cgi_app = shift;
    my $self    = $cgi_app->throttle();

    #
    # Get the redis handle
    #
    my $redis = $self->{ 'redis' } || return;

    #
    # The key relating to this user.
    #
    my $key = $self->_get_redis_key();

    #  Increase the count, and set the expiry.
    #
    $redis->incr($key);
    $redis->expire( $key, $self->{ 'period' } );

    #
    #  Get the current hit-count.
    #
    my $cur = $redis->get($key);

    #
    #  If too many redirect.
    #
    if ( ($cur) && ( $self->{ 'exceeded' } ) && ( $cur > $self->{ 'limit' } ) )
    {

        #
        #  Redirect to a different run-mode..
        #
        if ( $self->{ 'exceeded' } )
        {
            $cgi_app->prerun_mode( $self->{ 'exceeded' } );
        }
    }

    #
    #  Otherwise if we've been called with a mode merge it in
    #
    if ( $cgi_app->query->url_param( $cgi_app->mode_param ) )
    {
        $cgi_app->prerun_mode(
                           $cgi_app->query->url_param( $cgi_app->mode_param ) );
    }

}


=head2 configure

This method is what the user will invoke to configure the throttle-limits.

It is expected that within the users L<CGI::Application> setup method
there will be code similar to this:

=for example begin

    sub setup {
        my $self = shift;

        my $r = Redis->new();

        $self->throttle()->configure( %args )
    }

=for example end

The arguments hash contains the following known keys:

=over 8

=item C<redis>

A L<Redis> handle object.

=item C<limit>

The maximum number of requests that the remote client may make, in the given period of time.

=item C<period>

The period of time which requests are summed for.  The period is specified in seconds and if more than C<limit> requests are sent then the client will be redirected.

=item C<prefix>

This module uses L<Redis> to store the counts of client requests.  Redis is a key-value store, and each key used by this module is given a prefix to avoid collisions.  You may specify your prefix here.

=item C<exceeded>

The C<run_mode> to redirect the client to, when their request-count has exceeded the specified limit.

=back

=cut

sub configure
{
    my ( $self, %args ) = (@_);

    #
    #  Default rate-limiting period:
    #
    #   100 requests in 60 seconds.
    #
    $self->{ 'limit' }  = $args{ 'limit' }  if ( $args{ 'limit' } );
    $self->{ 'period' } = $args{ 'period' } if ( $args{ 'period' } );

    #
    #  Redis key-prefix
    #
    $self->{ 'prefix' } = $args{ 'prefix' } if ( $args{ 'prefix' } );

    #
    #  The handle to Redis for state-tracking
    #
    $self->{ 'redis' } = $args{ 'redis' } if ( $args{ 'redis' } );

    #
    #  The run-mode to redirect to on violition.
    #
    $self->{ 'exceeded' } = $args{ 'exceeded' } if ( $args{ 'exceeded' } );

}



=head1 AUTHOR

Steve Kemp <steve@steve.org.uk>

=cut

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 Steve Kemp <steve@steve.org.uk>.

This library is free software. You can modify and or distribute it under
the same terms as Perl itself.

=cut



1;
