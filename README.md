DHCP.io
-------

This repository contains the code behind the [DHCP.io](http://dhcp.io/) website,
which provides a self-hosted Dynamic-DNS system.

Users can register any hostname beneath a given DNS zone, and easily
update those hostnames to point to arbitrary IPv4 or IPv6 addresses.

For example if you deployed the code with the hostname "`spare.io`", then a user
"`bob`" would control the hostname "`bob.spare.io`".

> **NOTE**:  It is currently assumed a single user can control only a single hostname.


Implementation
---------------

The code is written in Perl, using the [CGI::Application](http://search.cpan.org/perldoc?CGI%3A%3AApplication) framework.

The logins for all users are stored in a [Redis](http://redis.io/) instance
running on the local-host.

For the serving the actual Dynamic-DNS entries Amazon's Route53 service is used.


Installation
------------

The code relies upon the following modules being present and installed:

* CGI::Application
  * `apt-get install libcgi-application-perl`
* [CGI::Application::Plugin::Throttle](http://search.cpan.org/dist/CGI-Application-Plugin-Throttle/)
  * Bundled into the distribution, as it isn't packaged for Debian.
* Data::UUID
  * `apt-get install libtie-ixhash-perl libdata-uuid-libuuid-perl`
* HTML::Template
  * `apt-get install libhtml-template-perl`
* Redis
  * `apt-get install libredis-perl`
* WebService::Amazon::Route53
  * Bundled into the distribution, as it isn't packaged for Debian.

These modules have other dependencies which you might not have present.
To test you have all the required packages please run:

    make test

or:

    perl t/00-load.t


Finally you'll also need a Redis server running on the same host as
the application, as this is used to store login sessions along with the
user-data.

Clone the code, and rename "`lib/DHCP/Config.pm.example`" to be `lib/DHCP/Config.pm`, updating it to contain your credentials.


Running Locally
---------------

The installation section, above, should be complete enough that you're
able to run the application.

For testing purposes a **sample** lighttpd configuration file is included
within the repository - this contains the appropriate rewrite-rules to
make the code function with pretty URLs:

    * /create/?        -> /cgi-bin/index.cgi?mode=create
    * /faq/?           -> /cgi-bin/index.cgi?mode=faq
    * /home/?          -> /cgi-bin/index.cgi?mode=home
    * /login           -> /cgi-bin/index.cgi?mode=login
    * /logout          -> /cgi-bin/index.cgi?mode=logout
    * /set/(.*)/(.*)/? -> /cgi-bin/index.cgi?mode=set;token=$1;ip=$2
    * /set/(.*)/?      -> /cgi-bin/index.cgi?mode=set;token=$1
    * /set/?           -> /cgi-bin/index.cgi?mode=set

If you have `lighttpd` installed then you should be able to launch the
application on your local system via:

    $ make local
    Launching lighttpd on http://localhost:2000/
    lighttpd -f conf/lighttpd.conf -D

Press Ctrl-c to terminate, otherwise open http://localhost:2000 in your
browser.

> **NOTE**: You'll need to have Redis installed locally too.


Steve
--
