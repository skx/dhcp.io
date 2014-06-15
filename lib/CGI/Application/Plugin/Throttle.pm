
=head1 NAME

CGI::Application::Plugin::Throttle - Limit accesses to runmodes.

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

=head1 DESCRIPTION

This module allows you to enforce a throttle on incoming requests to
your application, based upon the remote IP address.

This module stores a count of accesses in a Redis key-store, and
and once hits from a particular source exceeed the specified threshold
the user will be redirected to the run-mode you've specified.

=cut

=head1 POTENTIAL ISSUES / CONCERNS

Users who share IP addresses, because they are behind a common-gateway
for example, will all suffer if the threshold is too low.

This module will apply to all run-modes, because it seems likely that
this is the most common case.  If you have a preference for some modes
to be excluded please do contact the author.


=cut

=head1 AUTHOR

Steve Kemp <steve@steve.org.uk>

=cut

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 Steve Kemp <steve@steve.org.uk>.

This library is free software. You can modify and or distribute it under
the same terms as Perl itself.

=cut



package CGI::Application::Plugin::Throttle;

our $VERSION = '0.1';




=begin doc

Force the C<throttle> method into the caller's namespace, and
configure the prerun hook.

=end doc

=cut

sub import
{
    my $pkg     = shift;
    my $callpkg = caller;

    {
        no strict qw(refs);
        *{ $callpkg . '::throttle' } = \&throttle;
    }
    $callpkg->add_callback( 'prerun' => \&prerun_callback );

}


=begin doc

Constructor.

=end doc

=cut

sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};

    #
    #  Configure defaults.
    #
    $self->{ 'limit' }    = 100;
    $self->{ 'period' }   = 60;
    $self->{ 'exceeded' } = "slow_down";
    $self->{ 'prefix' }   = "THROTTLE";

    bless( $self, $class );
    return $self;
}


=being doc

Allow the caller to gain access to the throttle object.

=end doc

=cut

sub throttle
{
    my $cgi_app = shift;
    return $cgi_app->{ __throttle_obj } if $cgi_app->{ __throttle_obj };

    my $throttle = $cgi_app->{ __throttle_obj } = __PACKAGE__->new();
    return $throttle;
}


=begin doc

Hook invoked by L<CGI::Application> prior to execution.

Test that the remote user hasn't exceeded our limit, if they have
redirect the user.

=end doc

=cut

sub prerun_callback
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
    my $key = $self->{ 'prefix' };

    #
    #  Build up the key based on the:
    #
    #  1.  User using HTTP Basic-Auth, if present.
    #  2.  The remote IP address.
    #  3.  The remote user-agent.
    #
    foreach my $env ( qw! REMOTE_USER REMOTE_ADDR HTTP_USER_AGENT ! )
    {
        if ( $ENV{$env} )
        {
            $key .= ":";
            $key .= $ENV{$env};
        }
    }

    #
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
        $cgi_app->prerun_mode( $self->{ 'exceeded' } );
    }

    #
    #  Otherwise if we've been called with a mode merge it in
    #
    if ( $cgi_app->query->url_param( $cgi_app->mode_param ) )
    {
        $cgi_app->prerun_mode( $cgi_app->query->url_param( $cgi_app->mode_param ) )
   }

}


=begin doc

Allow the caller configure their limit.

=end doc

=cut

sub configure
{
    my ( $self, %args ) = (@_);

    #
    #  Default rate-limiting period:
    #
    #   100 requests in 60 seconds.
    #
    $self->{ 'limit' }  = $args{ 'limit' }  || 100;
    $self->{ 'period' } = $args{ 'period' } || 60;

    #
    #  Redis key-prefix
    #
    $self->{ 'prefix' } = $args{ 'prefix' } || "THROTTLE";

    #
    #  The handle to Redis for state-tracking
    #
    $self->{ 'redis' } = $args{ 'redis' };

    #
    #  The run-mode to redirect to on violition.
    #
    $self->{ 'exceeded' } = $args{ 'exceeded' } || "slow_down";
}

1;
