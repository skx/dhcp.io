DHCP.io
-------

This repository contains the code behind the [DHCP.io](http://dhcp.io/) service,
which provides a self-hosted Dynamic-DNS system.

Users can register up to five hostnames beneath a given DNS zone, and easily
update those names to point to arbitrary IPv4 or IPv6 addresses.

For example if you deployed the code with the hostname "`example.io`", then a user
"`bob`" would control the hostname "`bob.example.io`", and could also claim four more names.



Overview
--------

The code is written in Perl, using the [CGI::Application](http://search.cpan.org/perldoc?CGI%3A%3AApplication) framework.

The logins and record-associations for all users are stored in an SQLite
database, making deployment nice and simple.

A [Redis](http://redis.io/) instance is used for session-storage, and zone-caching.

For serving the actual Dynamic-DNS entries Amazon's Route53 service is used.


Requirements
------------

To deploy this code you'll need:

* A domain name, beneath which you'll let users register accounts.
* A working Perl installation.
* A [Redis](http://redis.io/) server.
* An account with [Amazon's Route53 DNS service](http://aws.amazon.com/route53/).
   * You'll need to update the configuration module with your secret key, access token, and zone identifier.


Installation
------------

The code relies upon the following modules being present and installed:

* CGI::Application
  * `apt-get install libcgi-application-perl`
* [CGI::Application::Plugin::Throttle](http://search.cpan.org/dist/CGI-Application-Plugin-Throttle/)
  * Bundled into the distribution, as it isn't packaged for Debian.
* Data::UUID
  * `apt-get install libtie-ixhash-perl libdata-uuid-libuuid-perl`
* DBI
  * `apt-get install libdbi-perl libdbd-sqlite3-perl`
* HTML::Template
  * `apt-get install libhtml-template-perl`
* JSON
  * `apt-get install libjson-perl`
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
the application, as this is used to store login sessions.

Clone the code, and rename "`lib/DHCP/Config.pm.example`" to be `lib/DHCP/Config.pm`, updating it to contain your credentials.


Running/Testing Locally
-----------------------

The installation section should be complete enough that you're
able to run the application for real.

However for testing purposes a sample [lighttpd](http://www.lighttpd.net/) configuration file
is also included within this repository.  The configuration file contains
all the required "rewrite rules", for example:

    ^/create/?        -> /cgi-bin/index.cgi?mode=create

If you have `lighttpd` installed then you should be able to launch the
application on your local system via:

    $ make local
    ..
    Launching lighttpd on http://localhost:2000/
    lighttpd -f conf/lighttpd.conf -D

Press Ctrl-c to terminate, otherwise open http://localhost:2000 in your
browser.

> **NOTE**: You'll need to have Redis installed locally too.


Steve
--
