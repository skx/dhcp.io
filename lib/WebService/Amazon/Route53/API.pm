package WebService::Amazon::Route53::API;

use warnings;
use strict;

use Carp;
use Digest::HMAC_SHA1;
use HTTP::Tiny;
use MIME::Base64;
use Tie::IxHash;
use XML::Simple;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(_ordered_hash);

=for Pod::Coverage new error

=cut

sub new {
    my ($class, %args) = @_;

    #skx
    $WebService::Amazon::Route53::VERSION = "101" unless ( $WebService::Amazon::Route53::VERSION );

    my $self = {};

    if (!defined $args{id}) {
        carp "Required parameter 'id' is not defined";
    }
    
    if (!defined $args{key}) {
        carp "Required parameter 'key' is not defined";
    }

    $self->{id} = $args{id};
    $self->{key} = $args{key};

    # Initialize an instance of XML::Simple
    $self->{xs} = XML::Simple->new;

    # Initialize the user agent object
    $self->{ua} = HTTP::Tiny->new(
        agent => 'WebService::Amazon::Route53/' .
            $WebService::Amazon::Route53::VERSION . ' (Perl)'
    );

    # Keep track of the last error
    $self->{error} = {};

    $self->{base_url} = 'https://route53.amazonaws.com/';

    return bless $self, $class;
}

sub error {
    my ($self) = @_;
    
    return $self->{error};
}

# "Private" methods

sub _get_server_date {
    my ($self) = @_;
    
    my $response = $self->{ua}->get($self->{base_url} . 'date');
    my $date = $response->{headers}->{'date'};
    
    if (!$date) {
        carp "Can't get Amazon server date";
    }
    
    return $date;    
}

sub _request {
    my ($self, $method, $url, $options) = @_;
    
    my $date = $self->_get_server_date;
    
    my $hmac = Digest::HMAC_SHA1->new($self->{'key'});
    $hmac->add($date);
    my $sig = encode_base64($hmac->digest, undef);
    
    my $auth = 'AWS3-HTTPS AWSAccessKeyId=' . $self->{'id'} . ',' .
        'Algorithm=HmacSHA1,Signature=' . $sig;
    # Remove trailing newlines, if any
    $auth =~ s/\n//g;
    
    $options = {} if !defined $options;

    $options->{headers}->{'Content-Type'} = 'text/xml';
    $options->{headers}->{'Date'} = $date;
    $options->{headers}->{'X-Amzn-Authorization'} = $auth;
    
    my $response = $self->{ua}->request($method, $url, $options);

    return $response;    
}

sub _parse_error {
    my ($self, $xml) = @_;
    
    my $data = $self->{xs}->XMLin($xml);
    
    $self->{error} = {
        type => $data->{Error}->{Type},
        code => $data->{Error}->{Code},
        message => $data->{Error}->{Message}
    };
}

# Helpful subroutines

# Amazon expects XML elements in specific order, so we'll need to pass the data
# to XML::Simple as ordered hashes
sub _ordered_hash (%) {
    tie my %hash => 'Tie::IxHash';
    %hash = @_;
    \%hash
}

1;
