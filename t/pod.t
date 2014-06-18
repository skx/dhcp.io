#!/usr/bin/perl -Ilib/ -I../lib/

use strict;
use warnings;

use Test::More;

# Ensure a recent version of Test::Pod

my $min_tp = 1.22;

## no critic
eval "use Test::Pod $min_tp";
## use critic

plan skip_all => "Test::Pod $min_tp required for testing POD" if $@;

all_pod_files_ok();
