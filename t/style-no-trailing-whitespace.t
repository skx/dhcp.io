#!/usr/bin/perl -w
#
#  Ensure that none of our scripts contain trailing whitespace.
#
# Steve
# --


use strict;
use File::Find;
use Test::More qw( no_plan );


#
#  Find all the files beneath the current directory,
# and call 'checkFile' with the name.
#
find( { wanted => \&checkFile, no_chdir => 1 }, '.' );



#
#  Check a file.
#
#
sub checkFile
{

    # The file.
    my $file = $File::Find::name;

    # We don't care about directories
    return if ( !-f $file );

    # Nor about backup files.
    return if ( $file =~ /~$/ );

    # or Makefiles
    return if ( $file =~ /Makefile/ );

    # See if it is a shell/perl file.
    my $isShell = 0;
    my $isPerl  = 0;

    # Read the file.
    open( my $handle, "<", $file ) or
      die "Failed to read $file - $!";
    foreach my $line (<$handle>)
    {
        if ( ( $line =~ /\/bin\/sh/ ) ||
             ( $line =~ /\/bin\/bash/ ) )
        {
            $isShell = 1;
        }
        if ( $line =~ /\/usr\/bin\/perl/ )
        {
            $isPerl = 1;
        }
    }
    close($handle);

    #
    #  We don't care about files which are neither perl nor shell.
    #
    if ( $isShell || $isPerl )
    {

        #
        #  Count trailing whitespace..
        #
        my $count = countTrailing($file);

        is( $count, 0, "Script has no trailing whitespace characters: $file" );
    }
}



#
#  Count and return the number of lines with trailng whitespace present.
#
sub countTrailing
{
    my ($file) = (@_);
    my $count = 0;

    open( my $handle, "<", $file ) or
      die "Cannot open $file - $!";
    foreach my $line (<$handle>)
    {

        # If we found a line with any then increase the count by one
        # rather than the number of characters found.
        if ( $line =~ /^(.*)([\t ]+)$/ )
        {
            $count += 1;
        }
    }
    close($handle);

    return ($count);
}
