#!/usr/bin/perl
#
#  Test that none of our scripts contain any literal TAB characters.
#
# Steve
# --


use strict;
use warnings;

use Test::More qw( no_plan );

## no critic (Eval)
eval "use Test::NoTabs;";
## use critic

plan skip_all => "Test::NoTabs required for testing." if $@;

all_perl_files_ok();
