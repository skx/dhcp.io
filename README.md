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
* HTML::Template
  * `apt-get install libhtml-template-perl`
* Net::DNS
  * `apt-get install libnet-dns-perl`
* Redis
  * `apt-get install libredis-perl`
* Data::UUID
  * `apt-get install libtie-ixhash-perl libdata-uuid-libuuid-perl`
* WebService::Amazon::Route53
  * Bundled into the distribution, as it isn't packaged for Debian (Stable).

Clone the code, and rename "`lib/DHCP/Config.pm.example`" to be `lib/DHCP/Config.pm`, updating it to contain your credentials.

You'll want to setup some rewrite rules:

    * /create/?        -> /cgi-bin/index.cgi?mode=create
    * /faq/?           -> /cgi-bin/index.cgi?mode=faq
    * /home/?          -> /cgi-bin/index.cgi?mode=home
    * /login           -> /cgi-bin/index.cgi?mode=login
    * /logout          -> /cgi-bin/index.cgi?mode=logout
    * /set/(.*)/(.*)/? -> /cgi-bin/index.cgi?mode=set;token=$1;ip=$2
    * /set/(.*)/?      -> /cgi-bin/index.cgi?mode=set;token=$1
    * /set/?           -> /cgi-bin/index.cgi?mode=set

Otherwise you should now be good to go.


Steve
--
