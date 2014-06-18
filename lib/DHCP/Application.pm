# -*- cperl -*- #

=head1 NAME

DHCP::Application - A CGI::Application .. application

=head1 DESCRIPTION

This module implements a simple, self-hosted, Dynamic-DNS system.

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
# Hierarchy
#
package DHCP::Application;
use base 'DHCP::Application::Base';

use CGI::Application::Plugin::Throttle;


#
#  This is is a sanity-check which will make the failure to follow
# instructions more explicit to users.
#
BEGIN
{

    ## no critic
    eval "use DHCP::Config";
    ## use critic
    if ($@)
    {
        print <<EOF;
Content-type: text/plain

The module lib/DHCP/Config.pm is not present.

You're supposed to rename lib/DHCP/Config.pm.example, and edit the
contents to make this application functional.
EOF
        exit(0);
    }
}

#
# Our code.
#
use DHCP::User;




=begin doc

Setup our run-mode mappings, and the defaults for the application.

=end doc

=cut

sub setup
{
    my $self = shift;

    $self->run_modes(

        # Rate-Limit
        'slow_down' => 'slow_down',

        # Index/Home for signed-in users.
        'index' => 'index',
        'home'  => 'home',

        # FAQ-page
        'faq' => 'faq',

        # Create a new user
        'create' => 'create',

        # Delete an A/AAAA record
        'delete' => 'delete',

        # Mark a feature as not available
        'capture' => 'capture',

        # Edit/Set the IP for a record.
        'set'  => 'set',
        'edit' => 'edit',

        # login / logout
        'login'  => 'application_login',
        'logout' => 'application_logout',

        # called on unknown mode.
        'AUTOLOAD' => 'unknown_mode',
    );

    #
    #  Start mode + mode name
    #
    $self->header_add( -charset => 'utf-8' );
    $self->start_mode('index');
    $self->mode_param('mode');


    #
    #  Configure the throttling.
    #
    $self->throttle()->configure( redis    => $self->{ 'redis' },
                                  limit    => 100,
                                  period   => 60,
                                  exceeded => "slow_down"
                                );
}


=begin doc

Create a new account.

=end doc

=cut

sub create
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  Already logged in?
    #
    my $existing = $session->param('logged_in');
    if ( defined($existing) )
    {
        return ( $self->redirectURL("/home") );
    }

    #
    #  Load the template.
    #
    my $template = $self->load_template("create.tmpl");

    #
    #  Set the zone in the template
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );

    #
    #  Is the user submitting?
    #
    if ( $q->param("submit") )
    {
        my $name = $q->param("zone");
        my $pass = $q->param("password");
        my $mail = $q->param("email");

        #
        #  If the zone is empty then we're done
        #
        if ( !defined($name) || !length($name) )
        {
            $template->param( error => "You must supply a name." );
            return ( $template->output() );
        }

        #
        #  If the password is empty then we're done
        #
        if ( !defined($pass) || !length($pass) )
        {
            $template->param( error => "You must supply a password." );
            return ( $template->output() );
        }

        #
        #  If the user exists
        #
        my $tmp = DHCP::User->new( redis => $self->{ 'redis' } );
        if ( $tmp->present($name) )
        {
            $template->param( error => "That name is already taken." );
            return ( $template->output() );
        }

        #
        #  If the user is taking a forbidden name, deny it.
        #
        if ( $tmp->forbidden($name) )
        {
            $template->param( error => "That name is forbidden." );
            return ( $template->output() );
        }

        #
        #  OK create the name.
        #
        $tmp->createUser( $name, $pass, $mail );

        #
        #  Now return.
        #
        $template->param( created => 1 );
    }

    return ( $template->output() );
}




=begin doc

Show the user's login page.

=end doc

=cut

sub home
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');


    #
    #  Not logged in?
    #
    my $existing = $session->param('logged_in');
    if ( !defined($existing) )
    {
        return ( $self->redirectURL("/") );
    }

    #
    #  Load the homepage template.
    #
    my $template = $self->load_template("home.tmpl");

    #
    #  Set the zone in the template
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );


    #
    #  Find the token for the users' zone-control
    #
    my $user = DHCP::User->new( redis => $self->{ 'redis' } );
    $template->param( token    => $user->getToken($existing) );
    $template->param( username => $existing );

    #
    # Lookup the live values
    #
    my $tmp = DHCP::Records->new();
    my $ips = $tmp->lookup($existing);

    $template->param( ipv4 => $ips->{ 'ipv4' }, present => 1 )
      if ( $ips->{ 'ipv4' } );
    $template->param( ipv6 => $ips->{ 'ipv6' }, present => 1 )
      if ( $ips->{ 'ipv6' } );

    #
    #  Render.
    #
    return ( $template->output() );
}


=begin doc

Show the FAQ-page.

=end doc

=cut

sub faq
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');


    #
    #  Not logged in?
    #
    my $existing = $session->param('logged_in');

    #
    #  Load the template & render
    #
    my $template = $self->load_template("faq.tmpl");


    #
    #  Set the zone in the template
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );

    #
    #  Set the login name.
    #
    $template->param( username => $existing ) if ($existing);

    return ( $template->output() );
}



=begin doc

Show the index page.

=end doc

=cut

sub index
{
    my ($self) = (@_);
    my $session = $self->param('session');


    #
    #  Already logged in?  Send them home.
    #
    my $existing = $session->param('logged_in');
    if ( defined($existing) )
    {
        return ( $self->redirectURL("/home") );
    }

    #
    #  Show the front-page.
    #
    my $template = $self->load_template("index.tmpl");

    #
    #  Set the zone in the template
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );

    return ( $template->output() );
}



=begin doc

Allow a login to be carried out.

=end doc

=cut

sub application_login
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');


    #
    #  Already logged in?
    #
    my $existing = $session->param('logged_in');
    if ( defined($existing) )
    {
        return ( $self->redirectURL("/") );
    }

    #
    # Login results.
    #
    my ($logged_in) = undef;

    #
    #  Username and Password from the login form.
    #
    my $lname = $q->param('lname');
    my $lpass = $q->param('lpass');

    #
    # Do the login
    #
    if ( defined($lname) &&
         length($lname) &&
         defined($lpass) &&
         length($lpass) )
    {
        my $user = DHCP::User->new( redis => $self->{ 'redis' } );
        $logged_in = $user->testLogin( $lname, $lpass );
    }

    #
    #  If it worked
    #
    if ( defined($logged_in) && ($logged_in) )
    {

        #
        #  Setup the session variables.
        #
        $session->param( "logged_in",    $lname );
        $session->param( "failed_login", undef );
        $session->flush();

        #
        #  Return to the homepage.
        #
        return ( $self->redirectURL("/home") );
    }
    else
    {

        #
        #  Login failed, or some details missing.
        #
        $session->param( 'logged_in', undef );
        $session->clear('logged_in');
        $session->param( 'login_name', $lname );
        $session->close();

        #
        #  Load the template
        #
        my $template = $self->load_template("login.template");
        $template->param( login_name => $lname ) if ($lname);


        #
        # User submitted a login attempt which failed.
        #
        $template->param( login_error => 1 );

        #
        #  Display it.
        #
        return $template->output();
    }
}


=begin doc

Update a valid sub-domain.

=end doc

=cut

sub set
{
    my ($self) = (@_);
    my $q = $self->query();

    #
    #  Get the record to update and the IP to use.
    #
    my $token = $q->param("token");
    my $ip = $q->param("ip") || $ENV{ 'REMOTE_ADDR' };

    #
    #  See if we can find a user by token
    #
    my $temp = DHCP::User->new( redis => $self->{ 'redis' } );
    my $user = $temp->getUserFromToken($token);

    if ($user)
    {
        $temp->setRecord( $user, $ip );
        return ($ip);
    }
    else
    {

        #
        #  Attempting to update a record which has no valid token.
        #
        return ( $self->redirectURL("/") );
    }
}


=begin doc

Update a valid record, via the web-page.

=end doc

=cut

sub edit
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  The user must be logged in.
    #
    my $existing = $session->param('logged_in');
    if ( !defined($existing) )
    {
        return ( $self->redirectURL("/") );
    }

    #
    #  Get the helper.
    #
    my $helper = DHCP::Records->new( redis => $self->{ 'redis' } );

    #
    #  Load the template
    #
    my $template = $self->load_template("edit.tmpl");
    $template->param( username => $existing ) if ($existing);

    #
    #  Populate values.
    #
    my $records = $helper->getRecords();
    $template->param( ipv4 => $records->{ 'A' }{ $existing } )
      if ( $records->{ 'A' }{ $existing } );
    $template->param( ipv6 => $records->{ 'AAAA' }{ $existing } )
      if ( $records->{ 'AAAA' }{ $existing } );


    if ( $q->param("submit") )
    {

        #
        #  Get the values.
        #
        my $ipv4 = $q->param("ipv4") || undef;
        my $ipv6 = $q->param("ipv6") || undef;

        my $uh = DHCP::User->new( redis => $self->{'redis'} );
        $uh->setRecord( $existing, $ipv4 ) if ($ipv4);
        $uh->setRecord( $existing, $ipv6 ) if ($ipv6);

        $template->param( updated => 1 );
    }

    return ( $template->output() );
}




=begin doc

Allow the user to delete a record.

=end doc

=cut

sub delete
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');



    #
    #  The user must be logged in.
    #
    my $existing = $session->param('logged_in');
    if ( !defined($existing) )
    {
        return ( $self->redirectURL("/") );
    }

    #
    #  Get the type to delete.
    #
    my $type = $q->param("type");
    my $name = $q->param("name");
    my $ip   = $q->param("ip");

    if ( lc($name) eq lc($existing) )
    {
        my $tmp = DHCP::Records->new();
        $tmp->removeRecord( $name, $type, $ip );


        return ( $self->redirectURL("/home") );
        return "Deleting $name - $type";
    }
    else
    {

        # Tried to delete a record belonging to somebody else.
        return ( $self->redirectURL("/") );
    }
}


=begin doc

Logout the current user.

=end doc

=cut

sub application_logout
{
    my ($self) = (@_);
    my $session = $self->param('session');

    $session->param( 'logged_in', undef );
    $session->clear('logged_in');
    $self->param( 'session', undef );
    $session->close();
    return ( $self->redirectURL("/") );
}



=begin doc

Mark a feature as being unavailable, but capture the user's email addres.

=end doc

=cut

sub capture
{
    my $self = shift;

    my $q       = $self->query();
    my $session = $self->param('session');


    my $template = $self->load_template("interest.tmpl");

    my $existing = $session->param('logged_in');
    $template->param( username => $existing ) if ( $existing );

    if ( $q->param("submit") )
    {
        my $email = $q->param("email");
        my $comm = $q->param("comments") || "";

        #
        #  Load the template
        #
        my $mt = $self->load_template("interest.email.tmpl");
        $mt->param( email => $email,
                    comm  => $comm );
        $mt->param( username => $existing ) if ( $existing );

        open( SENDMAIL, "|/usr/lib/sendmail -t" ) or
          die "Cannot open sendmail: $!";
        print( SENDMAIL $mt->output() );
        close(SENDMAIL);

        $template->param( thanks => 1 );

    }

    return ( $template->output() );
}



=begin doc

Called when the user is too busy.

=end doc

=cut

sub slow_down
{
    my $self = shift;

    my ( $count, $max ) = $self->throttle()->count();
    return (
        "Rate-Limit exceeded  - $count visits seen - maximum is $max - in the past 60 seconds."
    );
}


1;


