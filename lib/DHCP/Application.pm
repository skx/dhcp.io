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
use DHCP::User::Auth;




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
        'read_only' => 'read_only',

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

        # Update a profile.
        'profile_email'    => 'profile_email',
        'profile_password' => 'profile_password',

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

        # view profile
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
    my $template = $self->load_template("pages/login.tmpl");
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

    # If we're in read-only mode then just terminate.
    if ($DHCP::Config::READ_ONLY)
    {
        return ( $self->redirectURL("/read-only/") );
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


    # If we're in read-only mode then just terminate.
    if ($DHCP::Config::READ_ONLY)
    {
        return ( $self->redirectURL("/read-only/") );
    }


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
    my $template =
      $self->load_template( "pages/home.tmpl", loop_context_vars => 1 );

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
    # Limit on records - Nobody can have more than ten.
    #
    if ( $records && ( scalar(@$records) > 10 ) )
    {
        $template->param( exceeded => 1 );
    }

    #
    #  If you're "magic" you can have 5+
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
    #  Load the template.
    #
    my $template = $self->load_template("pages/login.tmpl");

    #
    #  Populate the template.
    #
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
    if ( $q->param('submit') )
    {
        #
        #  Bump the user's login-count.
        #
        $redis->incr($tkey);
        $redis->expire( $tkey, 300 );

        #
        #  Username and Password from the login form.
        #
        my $lname = $q->param('lname');
        my $lpass = $q->param('lpass');

        my $logged_in = undef;

        #
        #  Run the test
        #
        if ( $lname && $lpass )
        {
            my $user = DHCP::User::Auth->new();
            $logged_in =
              $user->test_login( username => $lname,
                                 password => $lpass );
        }

        if ($logged_in)
        {
            #
            #  Setup the session variables.
            #
            $session->param( "logged_in",    $lname );
            $session->param( "failed_login", undef );
            $session->flush();

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
                return ( $self->redirectURL("/home") );
            }
        }
        else
        {
            $template->param( login_error => 1 );
            $template->param( login_name => $lname ) if ($lname);
        }
    }

    #
    #  Show the form.
    #
    return $template->output();
}


=begin doc

Update a valid sub-domain.

=end doc

=cut

sub set
{
    my ($self) = (@_);
    my $q = $self->query();

    # If we're in read-only mode then just terminate.
    if ($DHCP::Config::READ_ONLY)
    {
        return ( $self->redirectURL("/read-only/") );
    }

    #
    #  Get the record to update and the IP to use.
    #
    my $token = $q->param("token");
    my $ip = $q->param("ip") || $ENV{ 'REMOTE_ADDR' };

    #
    #  Has the user updated recently?
    #
    my $redis  = Singleton::Redis->instance();
    my $update = $redis->get("DHCP:UPDATE:$ip");

    if ($update)
    {
        my $threshold = $DHCP::Config::THRESHOLD;
        return ("Updates are limited to once every $threshold seconds.");
    }

    #
    # If there is a threshold in-place then record the user's most recent
    # update against it.
    #
    my $threshold = $DHCP::Config::THRESHOLD;
    if ( $threshold && ( $threshold =~ /^([0-9]+)$/ ) )
    {
        $redis->set( "DHCP:UPDATE:$ip", 1 );
        $redis->expire( "DHCP:UPDATE:$ip", $threshold );
    }

    #
    #  See if we can find a user by token
    #
    my $temp = DHCP::User->new();
    my $user = $temp->getUserFromToken($token);

    if ($user)
    {
        my $owner = $temp->getOwnerFromDomain($user);

        #
        # Get the owner's email address.  If they have none
        # their update will be rejected.
        #
        my $data = $temp->get( user => $owner );
        my $mail = $data->{ 'email' };

        if ( defined($mail) && ( length($mail) > 0 ) && ( $mail =~ /@/ ) )
        {
            $temp->setRecord( $user, $ip, $owner );
            return ($ip);
        }
        else
        {
            return "Update dropped from user without email address.";
        }
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


    # If we're in read-only mode then just terminate.
    if ($DHCP::Config::READ_ONLY)
    {
        return ( $self->redirectURL("/read-only/") );
    }


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

Allow the user to delete a name completely.

If a user has `foo.dhcp.io` this function is called when the user
tries to delete it.  This will :

* Remove the AAAA record, if present.
* Remove the A record, if present.
* Remove the name `foo` from the user's database entry.

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

    # If we're in read-only mode then just terminate.
    if ($DHCP::Config::READ_ONLY)
    {
        return ( $self->redirectURL("/read-only/") );
    }

    #
    #  Get the name we're deleting, and the type.
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
    #  Get all the names/values for the current user.
    #
    #  Create the helper to do the deletion.
    #
    my $temp = DHCP::User->new();
    my $data = $temp->getAllData($existing);
    my $dns  = DHCP::Records->new();



    #
    #  If the record currently exists for the user then delete it.
    #
    my $deleted = 0;

    foreach my $entry (@$data)
    {
        if ( $entry->{ 'name' } eq $record )
        {
            if ( ( $type eq "AAAA" ) &&
                 ( $entry->{ 'ipv6' } ) )
            {
                $dns->removeRecord( $record, 'AAAA', $entry->{ 'ipv6' } );
                $deleted = 1;
            }
            if ( ( $type eq "A" ) &&
                 ( $entry->{ 'ipv4' } ) )
            {
                $dns->removeRecord( $record, 'A', $entry->{ 'ipv4' } );
                $deleted = 1;
            }
        }
    }

    return ( $self->redirectURL("/home") );
}



=begin doc

If a user has `foo.dhcp.io` this function is called when the user
tries to delete either the A or the AAAA record associated with this
name.

This will result in NXDOMAIN for that type.

NOTE: The user still has the name registered, it will just fail to resolve.
To remove the name entirely then see `delete`.

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

    # If we're in read-only mode then just terminate.
    if ($DHCP::Config::READ_ONLY)
    {
        return ( $self->redirectURL("/read-only/") );
    }

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
    #  Get all the names/values for the current user.
    #
    #  Create the helper to do the deletion.
    #
    my $temp = DHCP::User->new();
    my $data = $temp->getAllData($existing);
    my $dns  = DHCP::Records->new();

    #
    #  If the record currently exists for the user then delete it.
    #
    my $deleted = 0;

    foreach my $entry (@$data)
    {
        if ( $entry->{ 'name' } eq $record )
        {
            $dns->removeRecord( $record, 'A', $entry->{ 'ipv4' } )
              if ( $entry->{ 'ipv4' } );

            $dns->removeRecord( $record, 'AAAA', $entry->{ 'ipv6' } )
              if ( $entry->{ 'ipv6' } );

            $deleted = 1;
        }
    }

    if ($deleted)
    {
        my $user = DHCP::User->new();
        $user->deleteRecord( $existing, $record );
    }

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

Show the user that the site is in read-only mode.

=end doc

=cut

sub read_only
{
    my $self = shift;

    #  Load the template.
    my $template = $self->load_template("pages/read_only.tmpl");

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
    # Persist the username, if any.
    #
    my $session  = $self->param('session');
    my $existing = $session->param('logged_in');
    $template->param( username => $existing ) if ($existing);

    return ( $template->output() );
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

    if ($logs)
    {
        my @logs = reverse(@$logs);

        $template->param( logs => \@logs );
    }
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
    #  Load the template
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

        $template->param( invalid_token => 1 );
    }



    #
    #  Cancelling?
    #
    if ( $q->param("cancel") )
    {
        return ( $self->redirectURL("/") );
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

                #
                # Send the email.
                #
                my $smtp =
                  Net::SMTP::SSL->new( $DHCP::Config::SMTP_HOST,
                                       Port  => $DHCP::Config::SMTP_PORT,
                                       Debug => 0
                                     );

                $smtp->auth( $DHCP::Config::SMTP_USERNAME,
                             $DHCP::Config::SMTP_PASSWORD ) ||
                  die "Authentication failed!\n";

                $smtp->mail( $FROM . "\n" );
                $smtp->to( $dat->{ 'email' } );
                $smtp->data();
                $smtp->datasend( $et->output() );
                $smtp->dataend();
                $smtp->quit;
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


    # If we're in read-only mode then just terminate.
    if ($DHCP::Config::READ_ONLY)
    {
        return ( $self->redirectURL("/read-only/") );
    }


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

View your own profile.

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

    my $data = $user->get( user => $existing );
    $template->param( email => $data->{ 'email' } )
      if ( $data && $data->{ 'email' } );

    return ( $template->output() );
}


=begin doc

Allow the user to change their email address.

=end doc

=cut

sub profile_email
{
    my ($self) = (@_);

    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  Not logged in?
    #
    my $existing = $session->param('logged_in');
    return ( $self->login_required() ) unless ( defined($existing) );

    my $template = $self->load_template("pages/profile_email.tmpl");
    $template->param( username => $existing );

    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }

    #
    #  Get the user
    #
    my $user = DHCP::User->new();


    #
    #  Is the user cancelling?
    #
    if ( $q->param("cancel") )
    {
        return ( $self->redirectURL("/profile") );
    }


    #
    #  Is the user submitting?
    #
    if ( $q->param("submit") )
    {

        # Get the email from the form
        my $email = $q->param("email");

        if ( length $email )
        {

            # Save it
            $user->set( mail => $email,
                        user => $existing );

            $template->param( saved => 1 );
        }
    }

    # Get the updated/new values
    my $data = $user->get( user => $existing );
    $template->param( email => $data->{ 'email' } )
      if ( $data && $data->{ 'email' } );

    # Show the template
    return ( $template->output() );
}


=begin doc

Allow the user to change their password.

=end doc

=cut

sub profile_password
{
    my ($self) = (@_);

    my $q       = $self->query();
    my $session = $self->param('session');

    #
    #  Not logged in?
    #
    my $existing = $session->param('logged_in');
    return ( $self->login_required() ) unless ( defined($existing) );

    my $template = $self->load_template("pages/profile_password.tmpl");
    $template->param( username => $existing );

    my $z = $DHCP::Config::ZONE;
    $z =~ s/\.$//g;
    $template->param( "zone" => $z );
    if ( $z =~ /^(.*)\.(.*)$/ )
    {
        $template->param( "uc_zone" => uc($1) . "." . $2 );
    }

    #
    #  Get the user
    #
    my $user = DHCP::User->new();


    #
    #  Is the user cancelling?
    #
    if ( $q->param("cancel") )
    {
        return ( $self->redirectURL("/profile") );
    }


    #
    #  Is the user submitting?
    #
    if ( $q->param("submit") )
    {

        # Get the passwords from the form
        my $pass1 = $q->param("password");
        my $pass2 = $q->param("confirm");

        if ( $pass1 && $pass2 )
        {
            if ( $pass1 eq $pass2 )
            {
                my $helper = DHCP::User::Auth->new();
                $helper->set_password( username => $existing,
                                       password => $pass1 );

                $template->param( saved => 1 );
            }
            else
            {
                $template->param( password_mismatch => 1 );
            }
        }
        else
        {
            $template->param( password_empty => 1 );
        }
    }

    # Show the template
    return ( $template->output() );
}


1;
