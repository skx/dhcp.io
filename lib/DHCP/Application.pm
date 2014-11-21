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

#
# We don't need abusive clients.
#
use CGI::Application::Plugin::Throttle;
use UUID::Tiny;

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
use DHCP::Records;
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

        # Index/Home for anonymous/signed-in users.
        'index' => 'index',
        'home'  => 'home',

        # Log lookup
        'logs' => 'logs',

        # static-page serving
        'static' => 'static',

        # Create a new user/record
        'create' => 'create',
        'record' => 'record',

        # Delete an A/AAAA record
        'delete' => 'delete',

        # Delete a profile == account
        'profile_delete' => 'profile_delete',

        # Remove a hostname
        'remove' => 'remove',

        # Edit/Set the IP for a record.
        'set'  => 'set',
        'edit' => 'edit',

        # login / logout
        'login'  => 'application_login',
        'logout' => 'application_logout',

        # forgot password / password reset
        'forgotten' => 'forgotten',

        # profile
        'profile' => 'profile',

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
    $self->throttle()->configure( redis    => Singleton::Redis->instance(),
                                  limit    => 100,
                                  period   => 60,
                                  exceeded => "slow_down"
                                );
}



=begin doc

Redirect if the user needs to login to access the specific page.

=end doc

=cut

sub login_required
{
    my ($self) = (@_);

    #
    #  Load the template
    #
    my $template = $self->load_template("pages/login.template");
    $template->param( target => $ENV{ 'REQUEST_URI' } );


    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }


    #
    #  Update the cache
    #
    return ( $template->output() );
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

    my $closed = $DHCP::Config::CLOSED;


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
    my $template = $self->load_template("pages/create.tmpl");

    if ($closed)
    {
        $template->param( closed => 1 );
    }

    #
    #  Set the zone in the template
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }

    #
    #  Is the user submitting?
    #
    if ( ( $q->param("submit") ) && ( !$closed ) )
    {
        my $name = $q->param("zone");
        my $pass = $q->param("password");
        my $mail = $q->param("email");
        my $ip   = $ENV{ 'REMOTE_ADDR' };

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
        #  Avoid one-letter registration.
        #
        if ( length($name) < 2 )
        {
            $template->param( error => "That name is too short." );
            return ( $template->output() );
        }

        #
        #  If the user exists
        #
        my $tmp = DHCP::User->new();
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
        $tmp->createUser( $name, $pass, $mail, $ip );

        #
        #  Now return.
        #
        $template->param( created => 1 );
    }

    return ( $template->output() );
}



=begin doc

Create a new record assocated with the current user.

=end doc

=cut

sub record
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');


    #
    #  Not logged in?
    #
    my $existing = $session->param('logged_in');
    return ( $self->login_required() ) unless ( defined($existing) );


    #
    #  Get the attempted name
    #
    my $name = $q->param("name");

    #
    #  Is the name empty?
    #
    if ( !$name )
    {
        return ("Missing name");
    }

    #
    #  Ensure it is only a single record
    #
    if ( $name =~ /\./ )
    {
        return ("Single names only - no subrecords");
    }

    #
    #  Is the name forbidden?
    #
    foreach my $denied (@DHCP::Config::FORBIDDEN)
    {
        return "Name forbidden" if ( $denied eq $name );
    }

    #
    #  If it doesn't exist ..
    #
    my $user = DHCP::User->new();

    if ( $user->recordPresent($name) )
    {
        return "Name already in use";
    }

    #
    #  Create the record
    #
    $user->addRecord( $existing, $name );
    return ( $self->redirectURL("/home") );
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
    return ( $self->login_required() ) unless ( defined($existing) );


    #
    #  Load the homepage template.
    #
    my $template = $self->load_template("pages/home.tmpl");

    #
    #  Set the zone in the template
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }

    #
    #  Find the token for the users' zone-control
    #
    my $user = DHCP::User->new();

    #
    # Get the records a user owns.
    #
    # This method will return several things:
    #
    #   Names the user has
    #   The token for each name.
    #   Their current IPv4 + IPv6 addresses.
    #
    my $records = $user->getAllData($existing);
    $template->param( records => $records ) if ($records);
    $template->param( username => $existing );

    #
    # Limit on records.
    #
    if ( $records && ( scalar(@$records) >= 5 ) )
    {
        $template->param( exceeded => 1 )
          unless ( $DHCP::Config::MAGIC->{ $existing } );
    }

    #
    #  Render.
    #
    return ( $template->output() );
}


=begin doc

Show a static page of text.

=end doc

=cut

sub static
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
    my $template = $self->load_template("pages/static.tmpl");

    #
    #  Set the zone in the template
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }


    #
    #  Get the text to show
    #
    my $file = $q->param("file");
    die "Missing file" unless ($file);
    die "Exploit Attempt" if ( $file !~ /^([a-z]+)\.txt$/ );

    open( my $handle, "<", "../../templates/static/$file" ) or
      die "Failed to open - $!";

    my $text = "";
    while ( my $line = <$handle> )
    {
        $text .= $line;
    }
    close($handle);

    $template->param( text => $text );

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
    my $template = $self->load_template("pages/index.tmpl");

    #
    #  Set the zone in the template
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }

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
    #  If the user is being throttled then tell them so.
    #
    my $redis = Singleton::Redis->instance();

    #
    #  The key we store login attempts.
    #
    my $tkey = "THROTTLE:IP:";
    $tkey .= $ENV{ 'REMOTE_ADDR' } if ( $ENV{ 'REMOTE_ADDR' } );

    my $throttle = $redis->get($tkey) || 0;
    if ( defined($throttle) && ( $throttle >= 5 ) )
    {
        return ( $self->redirectURL("/throttle/") );
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
        my $user = DHCP::User->new();
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
        #
        # Login succeeded.  If we have a redirection target:
        #
        # 1:  Close session.
        # 2:  Redirect + Set-Cookie
        # 3:  Exit.
        #
        my $target = $q->param("target");
        if ( defined($target) && ( $target =~ /^\// ) )
        {

            return ( $self->redirectURL($target) );
        }
        else
        {

            #
            #  Just return to the homepage.
            #
            return ( $self->redirectURL("/home") );
        }
    }
    else
    {

        #
        #  Bump the user's login-count.
        #
        $redis->incr($tkey);
        $redis->expire( $tkey, 300 );

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
        my $template = $self->load_template("pages/login.template");
        $template->param( login_name => $lname ) if ($lname);


        my $z = $DHCP::Config::ZONE;
        $z =~ s/\.$//g;
        $template->param( "zone" => $z );
        if ( $z =~ /^(.*)\.(.*)$/ )
        {
            $template->param( "uc_zone" => uc($1) . "." . $2 );
        }

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
    my $temp = DHCP::User->new();
    my $user = $temp->getUserFromToken($token);

    if ($user)
    {
        my $owner = $temp->getOwnerFromDomain($user);

        $temp->setRecord( $user, $ip, $owner );
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
    return ( $self->login_required() ) unless ( defined($existing) );


    #
    #  Get the name we're editing, remember there might be
    # more than one for each user
    #
    my $record = $q->param("record");
    if ( !defined($record) )
    {
        return ( $self->redirectURL("/") );
    }

    #
    #  Security Test.
    #
    #  Get all the values for the current user, and ensure that
    # they have control over the record
    #
    my $temp = DHCP::User->new();
    my $data = $temp->getAllData($existing);

    #
    #  Look for a match
    #
    my $match = 0;
    my $ipv4  = undef;
    my $ipv6  = undef;

    foreach my $entry (@$data)
    {
        if ( $entry->{ 'name' } eq $record )
        {
            $match = 1;

            #
            #  Get the values in case we're not submitted and we
            # need to show them to the user.
            #
            $ipv4 = $entry->{ 'ipv4' } if ( $entry->{ 'ipv4' } );
            $ipv6 = $entry->{ 'ipv6' } if ( $entry->{ 'ipv6' } );
        }
    }

    return ( $self->redirectURL("/") ) if ( !$match );


    #
    #  Load the template
    #
    my $template = $self->load_template("pages/edit.tmpl");
    $template->param( username => $existing ) if ($existing);
    $template->param( record => $record );

    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }

    #
    #  Populate values.
    #
    $template->param( ipv4 => $ipv4 ) if ($ipv4);
    $template->param( ipv6 => $ipv6 ) if ($ipv6);


    if ( $q->param("submit") )
    {

        #
        #  Get the values.
        #
        my $ipv4 = $q->param("ipv4") || undef;
        my $ipv6 = $q->param("ipv6") || undef;

        my $uh = DHCP::User->new();

        $uh->setRecord( $record, $ipv4, $existing ) if ($ipv4);
        $uh->setRecord( $record, $ipv6, $existing ) if ($ipv6);

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
    return ( $self->login_required() ) unless ( defined($existing) );



    #
    #  Get the name we're editing, remember there might be
    # more than one for each user
    #
    my $record = $q->param("record");
    my $type   = $q->param("type");
    my $value  = $q->param("val");

    #
    #  Ensure the values are present.
    #
    if ( !defined($record) ||
         !defined($type) ||
         !defined($value) )
    {
        return ( $self->redirectURL("/") );
    }


    #
    #  Security Test.
    #
    #  Get all the values for the current user, and ensure that
    # they have control over the record
    #
    my $temp = DHCP::User->new();
    my $data = $temp->getAllData($existing);

    #
    #  Look for a match
    #
    my $match = 0;
    foreach my $entry (@$data)
    {
        $match = 1 if ( $entry->{ 'name' } eq $record );
    }

    return ( $self->redirectURL("/") ) if ( !$match );

    my $tmp = DHCP::Records->new();
    $tmp->removeRecord( $record, $type, $value );


    return ( $self->redirectURL("/home") );
}



=begin doc

Allow the user to delete a hostname.

=end doc

=cut

sub remove
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  The user must be logged in.
    #
    my $existing = $session->param('logged_in');
    return ( $self->login_required() ) unless ( defined($existing) );

    #
    #  Get the name we're editing, remember there might be
    # more than one for each user
    #
    my $record = $q->param("record");

    #
    #  Ensure the values are present.
    #
    if ( !defined($record) )
    {
        return ( $self->redirectURL("/") );
    }


    #
    #  Security Test.
    #
    #  Get all the values for the current user, and ensure that
    # they have control over the record
    #
    my $temp = DHCP::User->new();
    my $data = $temp->getAllData($existing);

    #
    #  Look for a match
    #
    my $match = 0;
    foreach my $entry (@$data)
    {
        $match = 1 if ( $entry->{ 'name' } eq $record );
    }

    return ( $self->redirectURL("/") ) if ( !$match );

    #
    #  Lookup the current value(s) of the record.
    #
    my $tmp = DHCP::Records->new();
    my $cur = $tmp->lookup($record);

    #
    #  Delete the IPv4 address, if present.
    #
    if ( $cur && $cur->{ 'ipv4' } )
    {
        $tmp->removeRecord( $record, 'A', $cur->{ 'ipv4' } );
    }

    #
    #  Delete the IPv6 address if present.
    #
    if ( $cur && $cur->{ 'ipv6' } )
    {
        $tmp->removeRecord( $record, 'AAAA', $cur->{ 'ipv4' } );
    }

    #
    #  Now remove the records from the users DB-entry.
    #
    my $user = DHCP::User->new();
    $user->deleteRecord( $existing, $record );

    return ( $self->redirectURL("/home") );
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


=begin doc

Show the user their logs.

=end doc

=cut

sub logs
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  The user must be logged in.
    #
    my $existing = $session->param('logged_in');
    return ( $self->login_required() ) unless ( defined($existing) );

    #
    #  Load the template
    #
    my $template = $self->load_template("pages/logs.tmpl");
    $template->param( username => $existing ) if ($existing);

    #
    #  Populate the domain.
    #
    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }

    #
    #  Get the logs
    #
    my $helper = DHCP::User->new();
    my $logs   = $helper->logs($existing);

    $template->param( logs => $logs ) if ($logs);
    return ( $template->output() );

}


=begin doc

Forgotten password handler.

=end doc

=cut

sub forgotten
{
    my ($self)  = (@_);
    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  Logged in?  Return to home.
    #
    my $existing = $session->param('logged_in');
    if ( defined($existing) )
    {
        return ( $self->redirectURL("/home/") );
    }

    #
    #  Are we handling a password-reset?  If so we'll do the
    # lookup and login here.
    #
    #
    my $token = $q->param("token");

    if ($token)
    {

        #
        #  Get the user this token applies to.
        #
        my $redis = Singleton::Redis->instance();
        my $u     = $redis->get("PASSWORD:RESET:$token");

        #
        #  See if that user exists.
        #
        if ($u)
        {
            my $tmp = DHCP::User->new();
            if ( $tmp->present($u) )
            {

                #
                #  The token is dead.
                #
                $redis->del("PASSWORD:RESET:$token");

                $session->param( "logged_in",    $u );
                $session->param( "failed_login", undef );
                $session->flush();

                # Redirect the user to their profile page.
                return ( $self->redirectURL("/profile/") );
            }
        }

        die 'invalid token';
    }

    #
    #  Load the page
    #
    my $template = $self->load_template("pages/forgotten.tmpl");

    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }


    #
    #  Did the user submit the page?
    #
    if ( $q->param("submit") )
    {

        #
        #  The text the user entered - trimmed.
        #
        my $txt = $q->param("text") || "";
        $txt =~ s/^\s+|\s+$//g;

        #
        #  Nothing entered?  Return.
        #
        return $template->output() if ( !length($txt) );

        #
        #  Find the user.
        #
        my $user = DHCP::User->new();
        my $obj  = $user->find($txt);

        if ( !$obj )
        {
            $template->param( not_found => 1 );
            return ( $template->output() );
        }
        else
        {
            my $dat = $user->get( user => $obj );

            # Create a reset-token
            my $token = UUID::Tiny::create_uuid_as_string();
            my $redis = Singleton::Redis->instance();
            $redis->set( "PASSWORD:RESET:$token", $obj );
            $redis->expire( "PASSWORD:RESET:$token", 60 * 60 * 12 );

            #
            # Send the actual email - if there was an address
            # found.
            #
            if ( $dat && $dat->{ 'email' } )
            {
                my $et = $self->load_template("email/forgotten.tmpl");
                $et->param( username => $obj,
                            to       => $dat->{ 'email' },
                            from     => $DHCP::Config::SENDER,
                            token    => $token
                          );
                open( SENDMAIL,
                      "|/usr/lib/sendmail -t -f $DHCP::Config::SENDER" ) or
                  die "Cannot open sendmail: $!";
                print( SENDMAIL $et->output() );
                close(SENDMAIL);
            }

            # Show the result.
            $template->param( check_email => 1 );
            return ( $template->output() );
        }
    }

    return ( $template->output() );
}


=begin doc

Delete the profile/account.

=end doc

=cut

sub profile_delete
{
    my ($self) = (@_);

    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  Not logged in?
    #
    my $existing = $session->param('logged_in');
    return ( $self->login_required() ) unless ( defined($existing) );


    #
    #  Has the user confirmed?
    #
    if ( $q->param("confirm") )
    {

        #
        # Get the submitted session ID
        #
        my $csrf = $q->param("token");


        if ( $session->id() eq $csrf )
        {

            my $user = DHCP::User->new();
            $user->deleteUser($existing);

            return ( $self->application_logout() );
        }
        else
        {

            # hack attempt
            return ( $self->redirectURL("/") );
        }

    }
    else
    {
        my $template = $self->load_template("pages/profile_delete.tmpl");
        $template->param( username => $existing,
                          token    => $session->id() );

        my $z = $DHCP::Config::ZONE;
        $z =~ s/\.$//g;
        $template->param( "zone" => $z );
        if ( $z =~ /^(.*)\.(.*)$/ )
        {
            $template->param( "uc_zone" => uc($1) . "." . $2 );
        }

        return ( $template->output() );
    }
}


=begin doc

View/Edit the profile.

=end doc

=cut

sub profile
{
    my ($self) = (@_);

    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  Not logged in?
    #
    my $existing = $session->param('logged_in');
    return ( $self->login_required() ) unless ( defined($existing) );

    my $user = DHCP::User->new();

    my $template = $self->load_template("pages/profile.tmpl");
    $template->param( username => $existing );

    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }

    #
    #  If the user is submitting.
    #
    if ( $q->param("submit") )
    {
        my $email = $q->param("email");
        my $pass = $q->param("pass") || "";
        if ($email)
        {
            $user->set( mail => $email,
                        user => $existing );
            $template->param( thanks => 1 );
        }
        if ( $pass && length($pass) > 0 )
        {
            $user->set( pass => $pass,
                        user => $existing );
            $template->param( thanks => 1 );
        }
    }

    my $data = $user->get( user => $existing );
    $template->param( email => $data->{ 'email' } )
      if ( $data && $data->{ 'email' } );

    return ( $template->output() );
}

1;


