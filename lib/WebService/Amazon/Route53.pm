package WebService::Amazon::Route53;

use warnings;
use strict;

use Carp;
use Digest::HMAC_SHA1;
use LWP::UserAgent;
use MIME::Base64;
use Tie::IxHash;
use URI::Escape;
use XML::Simple;

=head1 NAME

WebService::Amazon::Route53 - Perl interface to Amazon Route 53 API

=head1 VERSION

Version 0.013

=cut

our $VERSION = '0.013';

=head1 SYNOPSIS

WebService::Amazon::Route53 provides an interface to Amazon Route 53 DNS
service.

    use WebService::Amazon::Route53;

    my $r53 = WebService::Amazon::Route53->new(id => 'ROUTE53ID',
                                               key => 'SECRETKEY');
    
    # Create a new zone
    $r53->create_hosted_zone(name => 'example.com.',
                             caller_reference => 'example.com_migration_01');
    
    # Get zone information
    my $zone = $r53->find_hosted_zone(name => 'example.com.');
    
    # Create a new record
    $r53->change_resource_record_sets(zone_id => $zone->{id},
                                      action => 'create',
                                      name => 'www.example.com.',
                                      type => 'A',
                                      ttl => 86400,
                                      value => '12.34.56.78');

    # Modify records
    $r53->change_resource_record_sets(zone_id => $zone->{id},
        changes => [
            {
                action => 'delete',
                name => 'www.example.com.',
                type => 'A',
                ttl => 86400,
                value => '12.34.56.78'
            },
            {
                action => 'create',
                name => 'www.example.com.',
                type => 'A',
                ttl => 86400,
                records => [
                    '34.56.78.90',
                    '56.78.90.12'
                ]
            }
        ]);

=cut

my $url_base        = 'https://route53.amazonaws.com/';
my $url_api_version = '2011-05-05/';
my $api_url         = $url_base . $url_api_version;

=head1 METHODS

Required parameters are marked as such, other parameters are optional.

Instance methods return C<undef> on failure. More detailed error information can
be obtained by calling L<"error">.

=head2 new

Creates a new instance of WebService::Amazon::Route53.

    my $r53 = WebService::Amazon::Route53->new(id => 'ROUTE53ID',
                                               key => 'SECRETKEY');

Parameters:

=over 4

=item * id

B<(Required)> AWS access key ID.

=item * key

B<(Required)> Secret access key.

=back

=cut

sub new
{
    my ( $class, %args ) = @_;

    my $self = {};
    bless( $self, $class );

    if ( !defined $args{ 'id' } )
    {
        carp "Required parameter 'id' is not defined";
    }

    if ( !defined $args{ 'key' } )
    {
        carp "Required parameter 'key' is not defined";
    }

    $self->{ 'id' }  = $args{ 'id' };
    $self->{ 'key' } = $args{ 'key' };

    $self->{ 'xs' } = XML::Simple->new;

    $self->{ 'ua' } = LWP::UserAgent->new;
    $self->{ 'ua' }->agent("WebService::Amazon::Route53/$VERSION (Perl)");

    # Last error
    $self->{ error } = {};

    return $self;
}

# Amazon expects XML elements in specific order, so we'll need to pass the data
# to XML::Simple as ordered hashes
sub _ordered_hash (%)
{
    tie my %hash => 'Tie::IxHash';
    %hash = @_;
    \%hash;
}

sub _get_server_date
{
    my ($self) = @_;

    my $response = $self->{ 'ua' }->get( $url_base . 'date' );
    my $date     = $response->headers->header('Date');

    if ( !$date )
    {
        carp "Can't get Amazon server date";
    }

    return $date;
}

sub _send_request
{
    my ( $self, $request ) = @_;

    my $date = $self->_get_server_date;

    my $hmac = Digest::HMAC_SHA1->new( $self->{ 'key' } );
    $hmac->add($date);
    my $sig = encode_base64( $hmac->digest, undef );

    my $auth =
      'AWS3-HTTPS AWSAccessKeyId=' . $self->{ 'id' } . ',' .
      'Algorithm=HmacSHA1,Signature=' . $sig;

    $request->header( 'Content-Type'         => 'text/xml' );
    $request->header( 'Date'                 => $date );
    $request->header( 'X-Amzn-Authorization' => $auth );

    my $response = $self->{ 'ua' }->request($request);

    return $response;
}

sub _parse_error
{
    my ( $self, $xml ) = @_;

    my $data = $self->{ xs }->XMLin($xml);

    $self->{ error } = { type    => $data->{ Error }->{ Type },
                         code    => $data->{ Error }->{ Code },
                         message => $data->{ Error }->{ Message } };
}

=head2 list_hosted_zones

Gets a list of hosted zones.

Called in scalar context:

    $zones = $r53->list_hosted_zones(max_items => 15);

Called in list context:

    ($zones, $next_marker) = $r53->list_hosted_zones(marker => '456ZONEID',
                                                     max_items => 15);
    
Parameters:

=over 4

=item * marker

Indicates where to begin the result set. This is the ID of the last hosted zone
which will not be included in the results.

=item * max_items

The maximum number of hosted zones to retrieve.

=back

Returns: A reference to an array of hash references, containing zone data.
Example:

    $zones = [
        {
            'id' => '/hostedzone/123ZONEID',
            'name' => 'example.com.',
            'caller_reference' => 'ExampleZone',
            'config' => {
                'comment' => 'This is my first hosted zone'
            }
        },
        {
            'id' => '/hostedzone/456ZONEID',
            'name' => 'example2.com.',
            'caller_reference' => 'ExampleZone2',
            'config' => {
                'comment' => 'This is my second hosted zone'
            }
        }
    ];
    
When called in list context, it also returns the next marker to pass to a
subsequent call to C<list_hosted_zones> to get the next set of results. If this
is the last set of results, next marker will be C<undef>.

=cut

sub list_hosted_zones
{
    my ( $self, %args ) = @_;

    my $url       = $api_url . 'hostedzone';
    my $separator = '?';

    if ( defined $args{ 'marker' } )
    {
        $url .= $separator . 'marker=' . uri_escape( $args{ 'marker' } );
        $separator = '&';
    }

    if ( defined $args{ 'max_items' } )
    {
        $url .= $separator . 'maxitems=' . uri_escape( $args{ 'max_items' } );
    }

    my $response = $self->_send_request( HTTP::Request->new( GET => $url ) );

    if ( !$response->is_success )
    {
        $self->_parse_error( $response->decoded_content );
        return undef;
    }

    # Parse the returned XML data
    my $data =
      $self->{ 'xs' }
      ->XMLin( $response->decoded_content, ForceArray => ['HostedZone'] );
    my $zones = [];
    my $next_marker;

    foreach my $zone_data ( @{ $data->{ HostedZones }->{ HostedZone } } )
    {
        my $zone = { 'id'               => $zone_data->{ Id },
                     'name'             => $zone_data->{ Name },
                     'caller_reference' => $zone_data->{ CallerReference },
                   };

        if ( exists $zone_data->{ Config } )
        {
            $zone->{ config } = {};

            if ( exists $zone_data->{ Config }->{ Comment } )
            {
                $zone->{ config }->{ comment } =
                  $zone_data->{ Config }->{ Comment };
            }
        }

        push( @$zones, $zone );
    }

    if ( exists $data->{ NextMarker } )
    {
        $next_marker = $data->{ NextMarker };
    }

    return wantarray ? ( $zones, $next_marker ) : $zones;
}

=head2 get_hosted_zone

Gets hosted zone data.

    $zone = get_hosted_zone(zone_id => '123ZONEID');
    
Parameters:

=over 4

=item * zone_id

B<(Required)> Hosted zone ID.

=back

Returns: A reference to a hash containing zone data. Example:

    $zone = {
        'id' => '/hostedzone/123ZONEID'
        'name' => 'example.com.',
        'caller_reference' => 'ExampleZone',
        'config' => {
            'comment' => 'This is my first hosted zone'
        }
    };

=cut

sub get_hosted_zone
{
    my ( $self, %args ) = @_;

    if ( !defined $args{ 'zone_id' } )
    {
        carp "Required parameter 'zone_id' is not defined";
    }

    my $zone_id = $args{ 'zone_id' };

    # Strip off the "/hostedzone/" part, if present
    $zone_id =~ s!^/hostedzone/!!;

    my $url = $api_url . 'hostedzone/' . $zone_id;

    my $response = $self->_send_request( HTTP::Request->new( GET => $url ) );

    if ( !$response->is_success )
    {
        $self->_parse_error( $response->decoded_content );
        return undef;
    }

    my $data =
      $self->{ 'xs' }
      ->XMLin( $response->decoded_content, ForceArray => ['NameServer'] );

    my $zone = {'id'               => $data->{ HostedZone }->{ Id },
                'name'             => $data->{ HostedZone }->{ Name },
                'caller_reference' => $data->{ HostedZone }->{ CallerReference }
               };

    if ( exists $data->{ HostedZone }->{ Config } )
    {
        $zone->{ config } = {};

        if ( exists $data->{ HostedZone }->{ Config }->{ Comment } )
        {
            $zone->{ config }->{ comment } =
              $data->{ HostedZone }->{ Config }->{ Comment };
        }
    }

    return $zone;
}

=head2 find_hosted_zone

Finds the first hosted zone with the given name.

    $zone = $r53->find_hosted_zone(name => 'example.com.');
    
Parameters:

=over 4

=item * name

B<(Required)> Hosted zone name.

=back

Returns: A reference to a hash containing zone data (see L<"get_hosted_zone">),
or C<0> if there is no hosted zone with the given name.

=cut

sub find_hosted_zone
{
    my ( $self, %args ) = @_;

    if ( !defined $args{ 'name' } )
    {
        carp "Required parameter 'name' is not defined";
    }

    if ( $args{ 'name' } !~ /\.$/ )
    {
        $args{ 'name' } .= '.';
    }

    my $found_zone = 0;
    my $marker;

  ZONES: while (1)
    {
        my $zones =
          $self->list_hosted_zones( max_items => 100,
                                    marker    => $marker );

        if ( !defined $zones )
        {

            # We can assume $self->{error} is already set
            return undef;
        }

        my $zone;

        foreach $zone (@$zones)
        {
            if ( $zone->{ name } eq $args{ 'name' } )
            {
                $found_zone = $zone;
                last ZONES;
            }
        }

        if ( @$zones < 100 )
        {

            # Less than 100 zones have been returned -- no more zones to get
            last ZONES;
        }
        else
        {

            # Get the marker from the last returned zone
            ( $marker = $zones->[@$zones - 1]->{ 'id' } ) =~ s!^/hostedzone/!!;
        }
    }

    return $found_zone;
}

=head2 create_hosted_zone

Creates a new hosted zone.

    $response = $r53->create_hosted_zone(name => 'example.com.',
                                         caller_reference => 'example.com_01');

Parameters:

=over 4

=item * name

B<(Required)> New hosted zone name.

=item * caller_reference

B<(Required)> A unique string that identifies the request.

=back

Returns: A reference to a hash containing new zone data, change description,
and name servers information. Example:

    $response = {
        'zone' => {
            'id' => '/hostedzone/123ZONEID'
            'name' => 'example.com.',
            'caller_reference' => 'example.com_01',
            'config' => {}
        },
        'change_info' => {
            'id' => '/change/123CHANGEID'
            'submitted_at' => '2011-08-30T23:54:53.221Z',
            'status' => 'PENDING'
        },
        'delegation_set' => {
            'name_servers' => [
                'ns-001.awsdns-01.net',
                'ns-002.awsdns-02.net',
                'ns-003.awsdns-03.net',
                'ns-004.awsdns-04.net'
            ]
        },
    };

=cut

sub create_hosted_zone
{
    my ( $self, %args ) = @_;

    if ( !defined $args{ 'name' } )
    {
        carp "Required parameter 'name' is not defined";
    }

    if ( !defined $args{ 'caller_reference' } )
    {
        carp "Required parameter 'caller_reference' is not defined";
    }

    # Make sure the domain name ends with a dot
    if ( $args{ 'name' } !~ /\.$/ )
    {
        $args{ 'name' } .= '.';
    }

    my $data = _ordered_hash(
             'xmlns' => 'https://route53.amazonaws.com/doc/' . $url_api_version,
             'Name'  => [$args{ 'name' }],
             'CallerReference'  => [$args{ 'caller_reference' }],
             'HostedZoneConfig' => $args{ 'comment' } ?
               { 'Comment' => [$args{ 'comment' }] } :
               undef,
    );

    my $xml = $self->{ 'xs' }->XMLout( $data,
                                       SuppressEmpty => 1,
                                       NoSort        => 1,
                                       RootName => 'CreateHostedZoneRequest'
                                     );

    $xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $xml;

    my $response = $self->_send_request(
           HTTP::Request->new( POST => $api_url . 'hostedzone', undef, $xml ) );

    if ( !$response->is_success )
    {
        $self->_parse_error( $response->decoded_content );
        return undef;
    }

    $data =
      $self->{ xs }
      ->XMLin( $response->decoded_content, ForceArray => ['NameServer'] );

    my $ret = {
              zone => {
                  id               => $data->{ HostedZone }->{ Id },
                  name             => $data->{ HostedZone }->{ Name },
                  caller_reference => $data->{ HostedZone }->{ CallerReference }
              },
              change_info => {
                          id           => $data->{ ChangeInfo }->{ Id },
                          status       => $data->{ ChangeInfo }->{ Status },
                          submitted_at => $data->{ ChangeInfo }->{ SubmittedAt }
              },
              delegation_set => {
                     name_servers =>
                       $data->{ DelegationSet }->{ NameServers }->{ NameServer }
              } };

    if ( exists $data->{ HostedZone }->{ Config } )
    {
        $ret->{ zone }->{ config } = {};

        if ( exists $data->{ HostedZone }->{ Config }->{ Comment } )
        {
            $ret->{ zone }->{ config }->{ comment } =
              $data->{ HostedZone }->{ Config }->{ Comment };
        }
    }

    return $ret;
}

=head2 delete_hosted_zone

Deletes a hosted zone.

    $change_info = $r53->delete_hosted_zone(zone_id => '123ZONEID');
    
Parameters:

=over 4

=item * zone_id

B<(Required)> Hosted zone ID.

=back

Returns: A reference to a hash containing change information. Example:

    $change_info = {
        'id' => '/change/123CHANGEID'
        'submitted_at' => '2011-08-31T00:04:37.456Z',
        'status' => 'PENDING'
    };

=cut

sub delete_hosted_zone
{
    my ( $self, %args ) = @_;

    if ( !defined $args{ 'zone_id' } )
    {
        carp "Required parameter 'zone_id' is not defined";
    }

    my $zone_id = $args{ 'zone_id' };

    # Strip off the "/hostedzone/" part, if present
    $zone_id =~ s!^/hostedzone/!!;

    my $response = $self->_send_request(
          HTTP::Request->new( DELETE => $api_url . 'hostedzone/' . $zone_id ) );

    if ( !$response->is_success )
    {
        $self->_parse_error( $response->decoded_content );
        return undef;
    }

    my $data = $self->{ xs }->XMLin( $response->decoded_content );

    my $change_info = { id           => $data->{ ChangeInfo }->{ Id },
                        status       => $data->{ ChangeInfo }->{ Status },
                        submitted_at => $data->{ ChangeInfo }->{ SubmittedAt }
                      };

    return $change_info;
}

=head2 list_resource_record_sets

Lists resource record sets for a hosted zone.

Called in scalar context:

    $record_sets = $r53->list_resource_record_sets(zone_id => '123ZONEID');
    
Called in list context:

    ($record_sets, $next_record) =
        $r53->list_resource_record_sets(zone_id => '123ZONEID');
    
Parameters:

=over 4

=item * zone_id

B<(Required)> Hosted zone ID.

=item * name

The first domain name (in lexicographic order) to retrieve.

=item * type

DNS record type of the next resource record set to retrieve.

=item * identifier

Set identifier for the next source record set to retrieve. This is needed when
the previous set of results has been truncated for a given DNS name and type.

=item * max_items

The maximum number of records to be retrieved. The default is 100, and it's the
maximum allowed value.

=back

Returns: A reference to an array of hash references, containing record set data.
Example:

    $record_sets = [
        {
            name => 'example.com.',
            type => 'MX'
            ttl => 86400,
            records => [
                '10 mail.example.com'
            ]
        },
        {
            name => 'example.com.',
            type => 'NS',
            ttl => 172800,
            records => [
                'ns-001.awsdns-01.net.',
                'ns-002.awsdns-02.net.',
                'ns-003.awsdns-03.net.',
                'ns-004.awsdns-04.net.'
            ]
        }
    ];

When called in list context, it also returns a reference to a hash, containing
information on the next record which can be passed to a subsequent call to
C<list_resource_record_sets> to get the next set of records (using the C<name>
and C<type> parameters). Example:

    $next_record = {
        name => 'www.example.com.',
        type => 'A'
    };
    
If this is the last set of records, next record will be C<undef>.

=cut

sub list_resource_record_sets
{
    my ( $self, %args ) = @_;

    if ( !defined $args{ 'zone_id' } )
    {
        carp "Required parameter 'zone_id' is not defined";
    }

    my $zone_id = $args{ 'zone_id' };

    # Strip off the "/hostedzone/" part, if present
    $zone_id =~ s!^/hostedzone/!!;

    my $url       = $api_url . 'hostedzone/' . $zone_id . '/rrset';
    my $separator = '?';

    if ( defined $args{ 'name' } )
    {
        $url .= $separator . 'name=' . uri_escape( $args{ 'name' } );
        $separator = '&';
    }

    if ( defined $args{ 'type' } )
    {
        $url .= $separator . 'type=' . uri_escape( $args{ 'type' } );
        $separator = '&';
    }

    if ( defined $args{ 'identifier' } )
    {
        $url .=
          $separator . 'identifier=' . uri_escape( $args{ 'identifier' } );
        $separator = '&';
    }

    if ( defined $args{ 'max_items' } )
    {
        $url .= $separator . 'maxitems=' . uri_escape( $args{ 'max_items' } );
    }

    my $response = $self->_send_request( HTTP::Request->new( GET => $url ) );

    if ( !$response->is_success )
    {
        $self->_parse_error( $response->decoded_content );
        return undef;
    }

    my $data = $self->{ 'xs' }->XMLin( $response->decoded_content,
                        ForceArray => ['ResourceRecordSet', 'ResourceRecord'] );

    my $record_sets = [];
    my $next_record;

    foreach
      my $set_data ( @{ $data->{ ResourceRecordSets }->{ ResourceRecordSet } } )
    {
        my $records = [];

        foreach
          my $record ( @{ $set_data->{ ResourceRecords }->{ ResourceRecord } } )
        {
            push( @$records, $record->{ Value } );
        }

        my $record_set = { 'name'    => $set_data->{ Name },
                           'type'    => $set_data->{ Type },
                           'ttl'     => $set_data->{ TTL },
                           'records' => $records
                         };

        if ( exists $set_data->{ SetIdentifier } )
        {
            $record_set->{ set_identifier } =
              $set_data->{ SetIdentifier };
        }

        if ( exists $set_data->{ Weight } )
        {
            $record_set->{ weight } =
              $set_data->{ Weight };
        }

        # TODO: Add support for AliasTarget data

        push( @$record_sets, $record_set );
    }

    if ( exists $data->{ NextRecordName } )
    {
        $next_record = { name => $data->{ NextRecordName },
                         type => $data->{ NextRecordType } };
    }

    return wantarray ? ( $record_sets, $next_record ) : $record_sets;
}

=head2 change_resource_record_sets

Makes changes to DNS record sets.

    $change_info = $r53->change_resource_record_sets(zone_id => '123ZONEID',
            changes => [
                # Delete the current A record
                {
                    action => 'delete',
                    name => 'www.example.com.',
                    type => 'A',
                    ttl => 86400,
                    value => '12.34.56.78'
                },
                # Create a new A record with a different value
                {
                    action => 'create',
                    name => 'www.example.com.',
                    type => 'A',
                    ttl => 86400,
                    value => '34.56.78.90'
                },
                # Create two new MX records
                {
                    action => 'create',
                    name => 'example.com.',
                    type => 'MX',
                    ttl => 86400,
                    records => [
                        '10 mail.example.com',
                        '20 mail2.example.com'
                    ]
                }
            ]);
        
If there is just one change to be made, you can use the simplified call syntax,
and pass the change parameters directly, instead of using the C<changes>
parameter: 

    $change_info = $r53->change_resource_record_sets(zone_id => '123ZONEID',
                                                     action => 'delete',
                                                     name => 'www.example.com.',
                                                     type => 'A',
                                                     ttl => 86400,
                                                     value => '12.34.56.78');

Parameters:

=over 4

=item * zone_id

B<(Required)> Hosted zone ID.

=item * changes

B<(Required)> A reference to an array of hashes, describing the changes to be
made. If there is just one change, the array may be omitted and change
parameters may be passed directly.

=back

Change parameters:

=over 4

=item * action

B<(Required)> The action to perform (C<"create"> or C<"delete">).

=item * name

B<(Required)> The name of the domain to perform the action on.

=item * type

B<(Required)> The DNS record type.

=item * ttl

The DNS record time to live (TTL), in seconds.

=item * records

A reference to an array of strings that represent the current or new record
values. If there is just one value, you can use the C<value> parameter instead.

=item * value

Current or new DNS record value. For multiple record values, use the C<records>
parameter.

=back

Returns: A reference to a hash containing change information. Example:

    $change_info = {
        'id' => '/change/123CHANGEID'
        'submitted_at' => '2011-08-31T00:04:37.456Z',
        'status' => 'PENDING'
    };

=cut

sub change_resource_record_sets
{
    my ( $self, %args ) = @_;

    if ( !defined $args{ 'zone_id' } )
    {
        carp "Required parameter 'zone_id' is not defined";
    }

    if (    !defined( $args{ changes } )
         &&
         !( defined( $args{ action } ) &&
            defined( $args{ name } ) &&
            defined( $args{ type } ) &&
            ( defined( $args{ records } ) || defined( $args{ value } ) ) ) )
    {
        carp "Either the 'changes', or the 'action', 'name', 'type', " .
          "and 'records'/'value' paremeters must be defined";
    }

    my $zone_id = $args{ 'zone_id' };

    # Strip off the "/hostedzone/" part, if present
    $zone_id =~ s!^/hostedzone/!!;

    my $changes;

    if ( defined $args{ 'changes' } )
    {
        $changes = $args{ 'changes' };
    }
    else
    {

        # Simplified syntax for single changes
        delete $args{ 'zone_id' };
        $changes = [\%args];
    }

    my $data = _ordered_hash(
             'xmlns' => 'https://route53.amazonaws.com/doc/' . $url_api_version,
             'ChangeBatch' => {
                 'Comment' => $args{ 'comment' } ? [$args{ 'comment' }] : undef,
                 'Changes' => [{ 'Change' => [] }] } );

    foreach my $change (@$changes)
    {
        my $change_data = {'Action' => [uc $change->{ action }],
                           'ResourceRecordSet' =>
                             _ordered_hash(
                               'Name'            => [$change->{ name }],
                               'Type'            => [$change->{ type }],
                               'TTL'             => [$change->{ ttl }],
                               'ResourceRecords' => [{ 'ResourceRecord' => [] }]
                             ) };

        if ( exists $change->{ records } )
        {
            foreach my $value ( @{ $change->{ records } } )
            {
                push(
                      @{  $change_data->{ ResourceRecordSet }
                            ->{ ResourceRecords }[0]->{ ResourceRecord }
                        },
                      { 'Value' => [$value] } );
            }
        }
        elsif ( exists $change->{ value } )
        {
            push(
                 @{  $change_data->{ ResourceRecordSet }->{ ResourceRecords }[0]
                       ->{ ResourceRecord }
                   },
                 { 'Value' => [$change->{ value }] } );
        }

        push( @{ $data->{ ChangeBatch }->{ Changes }[0]->{ Change } },
              $change_data
            );
    }

    my $xml = $self->{ 'xs' }->XMLout(
                                   $data,
                                   SuppressEmpty => 1,
                                   NoSort        => 1,
                                   RootName => 'ChangeResourceRecordSetsRequest'
    );

    $xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $xml;

    my $response = $self->_send_request(
                     HTTP::Request->new(
                         POST => $api_url . 'hostedzone/' . $zone_id . '/rrset',
                         undef, $xml
                     ) );

    if ( !$response->is_success )
    {
        $self->_parse_error( $response->decoded_content );
        return undef;
    }

    $data = $self->{ xs }->XMLin( $response->decoded_content );

    my $change_info = { id           => $data->{ ChangeInfo }->{ Id },
                        status       => $data->{ ChangeInfo }->{ Status },
                        submitted_at => $data->{ ChangeInfo }->{ SubmittedAt }
                      };

    return $change_info;
}

=head2 error

Returns the last error.

    $error = $r53->error;
    
Returns: A reference to a hash containing the type, code, and message of the
last error. Example:

    $error = {
        'type' => 'Sender',
        'message' => 'FATAL problem: UnsupportedCharacter encountered at  ',
        'code' => 'InvalidDomainName'
    };

=cut

sub error
{
    my ($self) = @_;

    return $self->{ error };
}

=head1 AUTHOR

Michal Wojciechowski, C<< <odyniec at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-webservice-amazon-route53 at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WebService-Amazon-Route53>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WebService::Amazon::Route53


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WebService-Amazon-Route53>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/WebService-Amazon-Route53>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WebService-Amazon-Route53>

=item * Search CPAN

L<http://search.cpan.org/dist/WebService-Amazon-Route53/>

=back


=head1 SEE ALSO

=over 4

=item * Amazon Route 53 API Reference

L<http://docs.amazonwebservices.com/Route53/latest/APIReference/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Michal Wojciechowski.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of WebService::Amazon::Route53
