#!/usr/bin/perl -Ilib/ -I../lib/

use strict;
use warnings;


use Test::More qw! no_plan !;


BEGIN {use_ok("Digest::SHA")}
require_ok("Digest::SHA");

BEGIN {use_ok("DBI")}
require_ok("DBI");

BEGIN {use_ok("Carp")}
require_ok("Carp");

BEGIN {use_ok("CGI::Application::Plugin::Throttle")}
require_ok("CGI::Application::Plugin::Throttle");

BEGIN {use_ok("CGI::Session")}
require_ok("CGI::Session");

BEGIN {use_ok("Data::UUID::LibUUID")}
require_ok("Data::UUID::LibUUID");

BEGIN {use_ok("DHCP::Application")}
require_ok("DHCP::Application");

BEGIN {use_ok("DHCP::Application::Base")}
require_ok("DHCP::Application::Base");

BEGIN {use_ok("DHCP::Records")}
require_ok("DHCP::Records");

BEGIN {use_ok("DHCP::User")}
require_ok("DHCP::User");

BEGIN {use_ok("Digest::SHA")}
require_ok("Digest::SHA");

BEGIN {use_ok("Getopt::Long")}
require_ok("Getopt::Long");

BEGIN {use_ok("HTML::Template")}
require_ok("HTML::Template");

BEGIN {use_ok("LWP::UserAgent")}
require_ok("LWP::UserAgent");

BEGIN {use_ok("Redis")}
require_ok("Redis");

BEGIN {use_ok("URI::Escape")}
require_ok("URI::Escape");

BEGIN {use_ok("WebService::Amazon::Route53")}
require_ok("WebService::Amazon::Route53");

BEGIN {use_ok("XML::Simple")}
require_ok("XML::Simple");
