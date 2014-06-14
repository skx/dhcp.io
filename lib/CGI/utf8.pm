
=head1 NAME

CGI::utf8 - A helper to decode UTF8 correctly.

=cut

=head1 SYNOPSIS

=for example begin

    #!/usr/bin/perl -w

    use CGI::utf8;

    use strict;

    my $cgi = CGI->new();
    my $p   = $cgi->param( "foo" );

=for example end

=cut

use strict;
use warnings;

package CGI::utf8;

BEGIN
{
    use strict;
    use warnings;
    use CGI;
    use Encode;

    {
        no warnings 'redefine';
        my $param_org = \&CGI::param;

        my $might_decode = sub {
            my $p = shift;

            # make sure upload() filehandles are not modified
            return
              ( !$p || ( ref $p && fileno($p) ) ) ? $p :
                eval {decode_utf8($p)} || $p;
        };

        *CGI::param = sub {
            my $q = $_[0];    # assume object calls always
            my $p = $_[1];

            # setting a param goes through the original interface
            goto &$param_org if scalar @_ != 2;

            return wantarray ?
              map {$might_decode->($_)} $q->$param_org($p) :
              $might_decode->( $q->$param_org($p) );
          }
    }
}



=head1 LICENSE

Source: http://www.perlmonks.org/?node_id=651574

Author: http://www.perlmonks.org/?node_id=448370

Author

=cut

1;
