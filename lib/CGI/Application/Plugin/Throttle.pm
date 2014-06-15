package CGI::Application::Plugin::Throttle;

our $VERSION = '0.1';

#
# export the rate_limit method into the using CGI::App and setup the
# prerun callback
#
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

    bless( $self, $class );
    return $self;
}


sub throttle
{
    my $cgi_app = shift;
    return $cgi_app->{ __throttle_obj } if $cgi_app->{ __throttle_obj };

    my $throttle = $cgi_app->{ __throttle_obj } = __PACKAGE__->new();
    return $throttle;
}


#
# intercept the run-mode call
#
sub prerun_callback
{
    my $cgi_app = shift;
    my $self    = $cgi_app->throttle;

    #
    #  Bump the count for this client.
    #
    my $redis = $self->{ 'redis' } || return;
    my $ip = $ENV{ 'REMOTE_ADDR' };

    #
    #  Increase the count, and set the expiry.
    #
    $redis->incr("THROTTLE:$ip");
    $redis->expire( "THROTTLE:$ip", $self->{'period'} );

    #
    #  Get the current hit-count.
    #
    my $cur = $redis->get("THROTTLE:$ip");

    print STDERR
      "IP $ip has $cur/$self->{'limit'} will go to $self->{'exceeded'}";

    #
    #  If too many redirect.
    #
    if ( ($cur) && ( $cur > $self->{ 'limit' } ) )
    {
        $cgi_app->prerun_mode( $self->{ 'exceeded' } );
    }
}

sub configure
{
    my ( $self, %args ) = (@_);

    #
    #  Default rate-limiting period:
    #
    #   100 requests in 60 seconds.
    #
    $self->{ 'limit' }    = $args{ 'limit' }  || 100;
    $self->{ 'period' }   = $args{ 'period' } || 60;

    #
    #  The handle to Redis for state-tracking
    #
    $self->{ 'redis' }    = $args{ 'redis' };

    #
    #  The run-mode to redirect to on violition.
    #
    $self->{ 'exceeded' } = $args{ 'exceeded' } || "slow_down";
}

1;
