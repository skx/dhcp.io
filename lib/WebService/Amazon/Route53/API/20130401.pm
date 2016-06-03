package WebService::Amazon::Route53::API::20130401;

use warnings;
use strict;

use Carp;
use URI::Escape;

use WebService::Amazon::Route53::API;
use parent 'WebService::Amazon::Route53::API';

=head1 METHODS

=head2 new

Creates a new instance of WebService::Amazon::Route53::API::20130401.

This method should not be used directly -- instead, call
L<WebService::Amazon::Route53>->new and pass the desired API version as the
C<version> argument.

=cut

sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);

    $self->{api_version} = '2013-04-01';
    $self->{api_url} = $self->{base_url} . $self->{api_version} . '/';

    return $self;
}

=head2 list_hosted_zones

Gets a list of hosted zones.

    $response = $r53->list_hosted_zones(max_items => 15);
    
Parameters:

=over 4

=item * marker

Indicates where to begin the result set. This is the ID of the last hosted zone
which will not be included in the results.

=item * max_items

The maximum number of hosted zones to retrieve.

=back

Returns: A reference to a hash containing zone data, and a next marker if more
zones are available. Example:

    $response = {
        'hosted_zones' => [
            {
                'id' => '/hostedzone/123ZONEID',
                'name' => 'example.com.',
                'caller_reference' => 'ExampleZone',
                'config' => {
                    'comment' => 'This is my first hosted zone'
                },
                'resource_record_set_count' => '10'
            },
            {
                'id' => '/hostedzone/456ZONEID',
                'name' => 'example2.com.',
                'caller_reference' => 'ExampleZone2',
                'config' => {
                    'comment' => 'This is my second hosted zone'
                },
                'resource_record_set_count' => '7'
            }
        ],
        'next_marker' => '456ZONEID'
    ];
    
=cut

sub list_hosted_zones {
    my ($self, %args) = @_;
    
    my $url = $self->{api_url} . 'hostedzone';
    my $separator = '?';
    
    if (defined $args{'marker'}) {
        $url .= $separator . 'marker=' . uri_escape($args{'marker'});
        $separator = '&';
    }
    
    if (defined $args{'max_items'}) {
        $url .= $separator . 'maxitems=' . uri_escape($args{'max_items'});
    }
    
    my $response = $self->_request('GET', $url);
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    # Parse the returned XML data
    my $data = $self->{'xs'}->XMLin($response->{content},
        ForceArray => [ 'HostedZone' ]);
    my $zones = [];
    my $next_marker;
    
    foreach my $zone_data (@{$data->{HostedZones}{HostedZone}}) {
        push(@$zones, _parse_hosted_zone_response($zone_data));
    }
    
    if (exists $data->{NextMarker}) {
        $next_marker = $data->{NextMarker};
    }
    
    return {
        hosted_zones => $zones,
        (next_marker => $next_marker) x defined $next_marker
    };
}

=head2 get_hosted_zone

Gets hosted zone data.

    $response = get_hosted_zone(zone_id => '123ZONEID');
    
Parameters:

=over 4

=item * zone_id

B<(Required)> Hosted zone ID.

=back

Returns: A reference to a hash containing zone data and name servers
information. Example:

    $response = {
        'hosted_zone' => {
            'id' => '/hostedzone/123ZONEID'
            'name' => 'example.com.',
            'caller_reference' => 'ExampleZone',
            'config' => {
                'comment' => 'This is my first hosted zone'
            },
            'resource_record_set_count' => '10'
        },
        'delegation_set' => {
            'name_servers' => [
                'ns-001.awsdns-01.net',
                'ns-002.awsdns-02.net',
                'ns-003.awsdns-03.net',
                'ns-004.awsdns-04.net'
            ]
        }
    };

=cut

sub get_hosted_zone {
    my ($self, %args) = @_;
    
    if (!defined $args{'zone_id'}) {
        carp "Required parameter 'zone_id' is not defined";
    }
    
    my $zone_id = $args{'zone_id'};
    
    # Strip off the "/hostedzone/" part, if present
    $zone_id =~ s!^/hostedzone/!!;

    my $url = $self->{api_url} . 'hostedzone/' . $zone_id;
    
    my $response = $self->_request('GET', $url);
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    my $data = $self->{'xs'}->XMLin($response->{content},
        ForceArray => [ 'NameServer' ]);
    
    return {
        hosted_zone => _parse_hosted_zone_response($data->{HostedZone}),
        delegation_set => {
            name_servers => $data->{DelegationSet}{NameServers}{NameServer}
        }
    };
}

=head2 find_hosted_zone

Finds the first hosted zone with the given name.

    $response = $r53->find_hosted_zone(name => 'example.com.');
    
Parameters:

=over 4

=item * name

B<(Required)> Hosted zone name.

=back

Returns: A reference to a hash containing zone data and name servers information
(see L<"get_hosted_zone">), or a false value if there is no hosted zone with the
given name.

=cut

sub find_hosted_zone {
    my ($self, %args) = @_;
    
    if (!defined $args{'name'}) {
        carp "Required parameter 'name' is not defined";
    }
    
    if ($args{'name'} !~ /\.$/) {
        $args{'name'} .= '.';
    }
    
    my $found_zone;
    my $marker;
    
    ZONES: while (1) {
        my $response = $self->list_hosted_zones(max_items => 100,
            marker => $marker);
            
        if (!defined $response) {
            # We can assume $self->{error} is already set
            return;
        }
        
        my $zones = $response->{hosted_zones};
        my $zone;
        
        foreach $zone (@$zones) {
            if ($zone->{name} eq $args{'name'}) {
                $found_zone = $zone;
                last ZONES;
            }
        }
        
        if (@$zones < 100) {
            # Less than 100 zones have been returned -- no more zones to get
            last ZONES;
        }
        else {
            # Get the marker from the last returned zone
            ($marker = $zones->[@$zones-1]->{'id'}) =~ s!^/hostedzone/!!;
        }
    }

    if ($found_zone) {
        return $self->get_hosted_zone(zone_id => $found_zone->{id});
    }
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
        'hosted_zone' => {
            'id' => '/hostedzone/123ZONEID'
            'name' => 'example.com.',
            'caller_reference' => 'example.com_01',
            'config' => {},
            'resource_record_set_count' => '2'
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

sub create_hosted_zone {
    my ($self, %args) = @_;
    
    if (!defined $args{'name'}) {
        carp "Required parameter 'name' is not defined";
    }
    
    if (!defined $args{'caller_reference'}) {
        carp "Required parameter 'caller_reference' is not defined";
    }
    
    # Make sure the domain name ends with a dot
    if ($args{'name'} !~ /\.$/) {
        $args{'name'} .= '.';
    }
    
    my $data = _ordered_hash(
        'xmlns' => $self->{base_url} . 'doc/'. $self->{api_version} . '/',
        'Name' => [ $args{'name'} ],
        'CallerReference' => [ $args{'caller_reference'} ],
        'HostedZoneConfig' => $args{'comment'} ? {
            'Comment' => [ $args{'comment'} ]
        } : undef,
    );
    
    my $xml = $self->{'xs'}->XMLout($data, SuppressEmpty => 1, NoSort => 1,
        RootName => 'CreateHostedZoneRequest');
    
    $xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $xml;
    
    my $response = $self->_request('POST', $self->{api_url} . 'hostedzone',
        { content => $xml });
        
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    $data = $self->{xs}->XMLin($response->{content},
        ForceArray => [ 'NameServer' ]);
    
    return {
        hosted_zone => _parse_hosted_zone_response($data->{HostedZone}),
        change_info => {
            id => $data->{ChangeInfo}{Id},
            status => $data->{ChangeInfo}{Status},
            submitted_at => $data->{ChangeInfo}{SubmittedAt},
        },
        delegation_set => {
            name_servers => $data->{DelegationSet}{NameServers}{NameServer},
        }
    };
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

sub delete_hosted_zone {
    my ($self, %args) = @_;
    
    if (!defined $args{'zone_id'}) {
        carp "Required parameter 'zone_id' is not defined";
    }
    
    my $zone_id = $args{'zone_id'};
    
    # Strip off the "/hostedzone/" part, if present
    $zone_id =~ s!^/hostedzone/!!;

    my $response = $self->_request('DELETE',
        $self->{api_url} . 'hostedzone/' . $zone_id);
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    my $data = $self->{xs}->XMLin($response->{content});
        
    my $change_info = {
        id => $data->{ChangeInfo}{Id},
        status => $data->{ChangeInfo}{Status},
        submitted_at => $data->{ChangeInfo}{SubmittedAt}
    };
    
    return $change_info;
}

=head2 list_resource_record_sets

Lists resource record sets for a hosted zone.

    $response = $r53->list_resource_record_sets(zone_id => '123ZONEID');
    
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

Returns: A hash reference containing record set data, and optionally (if more
records are available) the name, type, and set identifier of the next record to
retrieve. Example:

    $response = {
        resource_record_sets => [
            {
                name => 'example.com.',
                type => 'MX'
                ttl => 86400,
                resource_records => [
                    '10 mail.example.com'
                ]
            },
            {
                name => 'example.com.',
                type => 'NS',
                ttl => 172800,
                resource_records => [
                    'ns-001.awsdns-01.net.',
                    'ns-002.awsdns-02.net.',
                    'ns-003.awsdns-03.net.',
                    'ns-004.awsdns-04.net.'
                ]
            }
        ],
        next_record_name => 'example.com.',
        next_record_type => 'A',
        next_record_identifier => '1'
    };

=cut

sub list_resource_record_sets {
    my ($self, %args) = @_;
    
    if (!defined $args{'zone_id'}) {
        carp "Required parameter 'zone_id' is not defined";
    }
    
    my $zone_id = $args{'zone_id'};

    # Strip off the "/hostedzone/" part, if present
    $zone_id =~ s!^/hostedzone/!!;

    my $url = $self->{api_url} . 'hostedzone/' . $zone_id . '/rrset';
    my $separator = '?';
    
    if (defined $args{'name'}) {
        $url .= $separator . 'name=' . uri_escape($args{'name'});
        $separator = '&';
    }
    
    if (defined $args{'type'}) {
        $url .= $separator . 'type=' . uri_escape($args{'type'});
        $separator = '&';
    }
    
    if (defined $args{'identifier'}) {
        $url .= $separator . 'identifier=' . uri_escape($args{'identifier'});
        $separator = '&';
    }

    if (defined $args{'max_items'}) {
        $url .= $separator . 'maxitems=' . uri_escape($args{'max_items'});
    }
    
    my $response = $self->_request('GET', $url);
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    my $data = $self->{'xs'}->XMLin($response->{content},
        ForceArray => [ 'ResourceRecordSet', 'ResourceRecord' ]);
    
    my $record_sets = [];
    my $next_record;
    
    foreach my $set_data (@{$data->{ResourceRecordSets}{ResourceRecordSet}}) {
        my $record_set = {
            name => $set_data->{Name},
            type => $set_data->{Type},
        };

        # Basic syntax
        
        if (exists $set_data->{TTL}) {
            $record_set->{ttl} = $set_data->{TTL};
        }

        if (exists $set_data->{ResourceRecords}) {
            my $records = [];

            foreach my $record (@{$set_data->{ResourceRecords}{ResourceRecord}}) {
                push(@$records, $record->{Value});
            }

            $record_set->{resource_records} = $records;
        }

        if (exists $set_data->{HealthCheckId}) {        
            $record_set->{health_check_id} = $set_data->{HealthCheckId};
        }

        # Weighted resource record sets

        if (exists $set_data->{SetIdentifier}) {
            $record_set->{set_identifier} = $set_data->{SetIdentifier};
        }
        
        if (exists $set_data->{Weight}) {
            $record_set->{weight} = $set_data->{Weight};
        }

        # Alias resource record sets

        if (exists $set_data->{AliasTarget}) {
            $record_set->{alias_target} = {
                hosted_zone_id => $set_data->{AliasTarget}{HostedZoneId},
                dns_name => $set_data->{AliasTarget}{DNSName},
                evaluate_target_health =>
                    $set_data->{AliasTarget}{EvaluateTargetHealth} eq 'true' ?
                    1 : 0
            };
        }

        # Latency resource record sets

        if (exists $set_data->{Region}) {
            $record_set->{region} = $set_data->{Region};
        }

        # Failover resource record sets

        if (exists $set_data->{Failover}) {
            $record_set->{failover} = lc $set_data->{Failover};
        }
        
        push(@$record_sets, $record_set); 
    }

    my $ret = { resource_record_sets => $record_sets };
    
    if (exists $data->{NextRecordName}) {
        $ret->{next_record_name} = $data->{NextRecordName};
    }

    if (exists $data->{NextRecordType}) {
        $ret->{next_record_type} = $data->{NextRecordType};
    }

    if (exists $data->{NextRecordIdentifier}) {
        $ret->{next_record_identifier} = $data->{NextRecordIdentifier};
    }
    
    return $ret;
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

B<(Required)> The action to perform (C<"create">, C<"delete">, or C<"upsert">).

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

=item * health_check_id

ID of a Route53 health check.

=item * set_identifier

Unique description for this resource record set.

=item * weight

Weight of this resource record set (in the range 0 - 255).

=item * alias_target

Information about the CloudFront distribution, Elastic Load Balancing load
balancer, Amazon S3 bucket, or resource record set to which queries are being
redirected. A hash reference with the following fields:

=over

=item * hosted_zone_id

Hosted zone ID for the CloudFront distribution, Amazon S3 bucket, Elastic Load
Balancing load balancer, or Amazon Route 53 hosted zone.

=item * dns_name

DNS domain name for the CloudFront distribution, Amazon S3 bucket, Elastic Load
Balancing load balancer, or another resource record set in this hosted zone.

=item * evaluate_target_health

Inherit the health of the referenced resource record sets (C<0> or C<1>).

=back

=item * region

Amazon EC2 region name.

=item * failover

Make this a primary or secondary failover resource record set (C<"primary"> or
C<"secondary">).

=back

Returns: A reference to a hash containing change information. Example:

    $change_info = {
        'id' => '/change/123CHANGEID'
        'submitted_at' => '2011-08-31T00:04:37.456Z',
        'status' => 'PENDING'
    };

=cut

sub change_resource_record_sets {
    my ($self, %args) = @_;
    
    if (!defined $args{'zone_id'}) {
        carp "Required parameter 'zone_id' is not defined";
    }
    
    if (!defined($args{changes}) && !(defined($args{action}) &&
        defined($args{name}) && defined($args{type}) && 
            (defined($args{records}) || defined($args{value}))))
    {
        carp "Either the 'changes', or the 'action', 'name', 'type', " .
            "and 'records'/'value' paremeters must be defined";
    }
    
    my $zone_id = $args{'zone_id'};
    
    # Strip off the "/hostedzone/" part, if present
    $zone_id =~ s!^/hostedzone/!!;
    
    my $changes;
    
    if (defined $args{'changes'}) {
        $changes = $args{'changes'};
    }
    else {
        # Simplified syntax for single changes
        delete $args{'zone_id'};
        $changes = [ \%args ];
    }

    my $data = _ordered_hash(
        'xmlns' => $self->{base_url} . 'doc/' . $self->{api_version} . '/',
        'ChangeBatch' => {
            'Comment' => defined $args{'comment'} ? [
                $args{'comment'}
            ] : undef,
            'Changes' => [
                {
                    'Change' => []
                }
            ]
        }
    );
    
    foreach my $change (@$changes) {
        my $change_data = _ordered_hash(
            'Action' => [ uc $change->{action} ],
            'ResourceRecordSet' => _ordered_hash(
                'Name' => [ $change->{name} ],
                'Type' => [ $change->{type} ],
            )
        );

        my $change_rrset = $change_data->{ResourceRecordSet};

        # Basic syntax

        if (exists $change->{ttl}) {
            $change_rrset->{TTL} = [ $change->{ttl} ];
        }

        if (exists $change->{value}) {
            $change->{records} = [ delete $change->{value} ];
        }
        
        if (exists $change->{records}) {
            $change_rrset->{ResourceRecords} = [ { ResourceRecord => [] } ];
            foreach my $value (@{$change->{records}}) {
                push(@{$change_rrset->{ResourceRecords}[0]
                    {ResourceRecord}}, { 'Value' => [ $value ] });
            }
        }

        if (exists $change->{health_check_id}) {
            $change_rrset->{HealthCheckId} = [ $change->{health_check_id} ];
        }

        # Weighted resource record sets

        if (exists $change->{set_identifier}) {
            $change_rrset->{SetIdentifier} = [ $change->{set_identifier} ];
        }

        if (exists $change->{weight}) {
            $change_rrset->{Weight} = [ $change->{weight} ];
        }

        # Alias resource record sets

        if (exists $change->{alias_target}) {
            $change_rrset->{AliasTarget} = _ordered_hash(
                HostedZoneId    => [ $change->{alias_target}{hosted_zone_id} ],
                DNSName         => [ $change->{alias_target}{dns_name} ],
                EvaluateTargetHealth => [
                    $change->{alias_target}{evaluate_target_health} ?
                        'true' : 'false'
                ],
            );
        }

        # Latency resource record sets

        if (exists $change->{region}) {
            $change_rrset->{Region} = [ $change->{region} ];
        }

        # Failover resource record sets

        if (exists $change->{failover}) {
            $change_rrset->{Failover} = [ uc $change->{failover} ];
        }
        
        push(@{$data->{ChangeBatch}{Changes}[0]{Change}}, $change_data);
    }

    my $xml = $self->{'xs'}->XMLout($data, SuppressEmpty => 1, NoSort => 1,
        RootName => 'ChangeResourceRecordSetsRequest');
        
    $xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $xml;
        
    my $response = $self->_request('POST', 
        $self->{api_url} . 'hostedzone/' . $zone_id . '/rrset', 
        { content => $xml });
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }

    $data = $self->{xs}->XMLin($response->{content});
        
    my $change_info = {
        id => $data->{ChangeInfo}{Id},
        status => $data->{ChangeInfo}{Status},
        submitted_at => $data->{ChangeInfo}{SubmittedAt}
    };
    
    return $change_info;
}

=head2 get_change

Gets current status of a change batch request.

    $change_info = $r53->get_change(change_id => '123FOO456');

Parameters:

=over 4

=item * change_id

B<(Required)> The ID of the change batch request.

=back

Returns: A reference to a hash containing change information. Example:

    $change_info = {
        'id' => '/change/123FOO456'
        'submitted_at' => '2011-08-31T00:04:37.456Z',
        'status' => 'PENDING'
    };

=cut

sub get_change {
    my ($self, %args) = @_;
    
    if (!defined $args{change_id}) {
        carp "Required parameter 'change_id' is not defined";
    }
    
    my $change_id = $args{change_id};
    
    # Strip off the "/change/" part, if present
    $change_id =~ s!^/change/!!;
    
    my $response = $self->_request('GET',
        $self->{api_url} . 'change/' . $change_id);
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }

    my $data = $self->{xs}->XMLin($response->{content});
        
    my $change_info = {
        id => $data->{ChangeInfo}{Id},
        status => $data->{ChangeInfo}{Status},
        submitted_at => $data->{ChangeInfo}{SubmittedAt}
    };
    
    return $change_info;
}

=head2 create_health_check

Creates a new health check.

    $response = $r53->create_health_check(
        caller_reference => 'check_01',
        type => 'http',
        fully_qualified_domain_name => 'example.com',
        request_interval => 10
    );

Parameters:

=over 4

=item * caller_reference

B<(Required)> A unique string that identifies the request.

=item * type

B<(Required)> The type of health check to be created (C<"http">, C<"https">,
C<"http_str_match">, C<"https_str_match">, or C<"tcp">).

=item * ip_address

The IPv4 address of the endpoint on which to perform health checks.

=item * port

The port on the endpoint on which to perform health checks. Required when the
type is C<tcp>, optional for other types (if omitted, the default value of C<80>
is used).

=item * resource_path

The path to request when performing health checks (applies to all types except
C<tcp>).

=item * fully_qualified_domain_name

Fully qualified domain name to be used in checks (applies to all types except
C<tcp>).

=item * search_string

The string to search for in the response body from the specified resource
(applies to C<http_str_match> and C<https_str_match>).

=item * request_interval

The number of seconds between the time when a response is received and the time
when the next health check request is sent (C<10> or C<30>, default: C<30>).

=item * failure_threshold

The number of consecutive health checks that an endpoint must pass or fail to
change the current status of the endpoint from unhealthy to healthy or vice
versa (a value between C<1> and C<10>, default: C<3>).

=back

Returns: A reference to a hash containing health check information. Example:

    $response = {
        'health_check' => {
            'id' => '01ab23cd-45ef-67ab-89cd-01ab23cd45ef',
            'caller_reference' => 'check_01',
            'health_check_config' => {
                'type' => 'http',
                'fully_qualified_domain_name' => 'example.com',
                'request_interval' => '10',
                'failure_threshold' => '3',
                'port' => '80'
            }
        }
    };

=cut

sub create_health_check {
    my ($self, %args) = @_;
    
    if (!defined $args{caller_reference}) {
        carp "Required parameter 'caller_reference' is not defined";
    }
    
    if (!defined $args{type}) {
        carp "Required parameter 'type' is not defined";
    }
    
    my $data = _ordered_hash(
        'xmlns' => $self->{base_url} . 'doc/'. $self->{api_version} . '/',
        'CallerReference' => [ $args{caller_reference} ],
        'HealthCheckConfig' => _ordered_hash,
    );

    if (exists $args{ip_address}) {
        $data->{HealthCheckConfig}{IPAddress} = [ $args{ip_address} ];
    }

    if (exists $args{port}) {
        $data->{HealthCheckConfig}{Port} = [ $args{port} ];
    }

    $data->{HealthCheckConfig}{Type} = [ uc $args{type} ];

    if (exists $args{resource_path}) {
        $data->{HealthCheckConfig}{ResourcePath} = [ $args{resource_path} ];
    }

    if (exists $args{fully_qualified_domain_name}) {
        $data->{HealthCheckConfig}{FullyQualifiedDomainName} =
            [ $args{fully_qualified_domain_name} ];
    }
    
    if (exists $args{search_string}) {
        $data->{HealthCheckConfig}{SearchString} = [ $args{search_string} ];
    }

    if (exists $args{request_interval}) {
        $data->{HealthCheckConfig}{RequestInterval} =
            [ $args{request_interval} ];
    }

    if (exists $args{failure_threshold}) {
        $data->{HealthCheckConfig}{FailureThreshold} =
            [ $args{failure_threshold} ];
    }

    my $xml = $self->{'xs'}->XMLout($data, SuppressEmpty => 1, NoSort => 1,
        RootName => 'CreateHealthCheckRequest');
    
    $xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $xml;

    my $response = $self->_request('POST', $self->{api_url} . 'healthcheck',
        { content => $xml });
        
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    $data = $self->{xs}->XMLin($response->{content});
    
    return {
        health_check => _parse_health_check_response($data->{HealthCheck})
    };
}

=head2 get_health_check

Gets information about a specific health check.

    $response = $r53->get_health_check(
        health_check_id => '01ab23cd-45ef-67ab-89cd-01ab23cd45ef');

Parameters:

=over 4

=item * health_check_id

B<(Required)> The ID of the health check to be deleted.

=back

Returns: A reference to a hash containing health check information. Example:

    $response = {
        'health_check' => {
            'id' => '01ab23cd-45ef-67ab-89cd-01ab23cd45ef',
            'caller_reference' => 'check_01',
            'health_check_config' => {
                'type' => 'http',
                'fully_qualified_domain_name' => 'example.com',
                'request_interval' => '10',
                'failure_threshold' => '3',
                'port' => '80'
            }
        }
    };

=cut

sub get_health_check {
    my ($self, %args) = @_;
    
    if (!defined $args{health_check_id}) {
        carp "Required parameter 'health_check_id' is not defined";
    }
    
    my $health_check_id = $args{health_check_id};
    
    my $response = $self->_request('GET',
        $self->{api_url} . 'healthcheck/' . $health_check_id);
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    my $data = $self->{xs}->XMLin($response->{content});

    return {
        health_check => _parse_health_check_response($data->{HealthCheck})
    };
}

=head2 list_health_checks

Gets a list of health checks.

    $response = $r53->list_health_checks(max_items => 10);

Parameters:

=over 4

=item * marker

Indicates where to begin the results set. This is the ID of the first health
check to include in the results.

=item * max_items

The maximum number of health checks to retrieve.

=back

Returns: A reference to a hash containing health check data, and a next marker
if more health checks are available. Example:

    $response = {
        'health_checks' => [
            {
                'id' => '01ab23cd-45ef-67ab-89cd-01ab23cd45ef',
                'caller_reference' => 'check_01',
                'health_check_config' => {
                    'type' => 'http',
                    'fully_qualified_domain_name' => 'example.com',
                    'request_interval' => '10',
                    'failure_threshold' => '3',
                    'port' => '80'
            },
            {
                'id' => 'ab23cd01-ef45-ab67-cd89-ab23cd45ef01',
                'caller_reference' => 'check_02',
                'health_check_config' => {
                    'type' => 'https',
                    'fully_qualified_domain_name' => 'example.com',
                    'request_interval' => '30',
                    'failure_threshold' => '3',
                    'port' => '443'
            },
        ],
        'next_marker' => '23cd01ab-45ef-67ab-89cd-23cd45ef01ab'
    };

=cut

sub list_health_checks {
    my ($self, %args) = @_;
    
    my $url = $self->{api_url} . 'healthcheck';
    my $separator = '?';
    
    if (defined $args{'marker'}) {
        $url .= $separator . 'marker=' . uri_escape($args{'marker'});
        $separator = '&';
    }
    
    if (defined $args{'max_items'}) {
        $url .= $separator . 'maxitems=' . uri_escape($args{'max_items'});
    }
    
    my $response = $self->_request('GET', $url);
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    my $data = $self->{'xs'}->XMLin($response->{content},
        ForceArray => [ 'HealthCheck' ]);
    my $health_checks = [];
    my $next_marker;
    
    foreach my $hc_data (@{$data->{HealthChecks}{HealthCheck}}) {
        push(@$health_checks, _parse_health_check_response($hc_data));
    }
    
    if (exists $data->{NextMarker}) {
        $next_marker = $data->{NextMarker};
    }
    
    return {
        health_checks => $health_checks,
        (next_marker => $next_marker) x defined $next_marker
    };
}

=head2 delete_health_check

Deletes a health check.

    $result = $r53->delete_health_check(
        health_check_id => '01ab23cd-45ef-67ab-89cd-01ab23cd45ef');
    
Parameters:

=over 4

=item * health_check_id

B<(Required)> The ID of the health check to be deleted.

=back

Returns: C<1> if the health check was successfully deleted, a false value
otherwise.

=cut

sub delete_health_check {
    my ($self, %args) = @_;
    
    if (!defined $args{health_check_id}) {
        carp "Required parameter 'health_check_id' is not defined";
    }
    
    my $health_check_id = $args{health_check_id};
    
    my $response = $self->_request('DELETE',
        $self->{api_url} . 'healthcheck/' . $health_check_id);
    
    if (!$response->{success}) {
        $self->_parse_error($response->{content});
        return;
    }
    
    return 1;
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

# Subroutines used internally

sub _parse_hosted_zone_response {
    my ($data) = @_;

    my $hosted_zone = {
        id => $data->{Id},
        name => $data->{Name},
        caller_reference => $data->{CallerReference},
        resource_record_set_count => $data->{ResourceRecordSetCount},
    };

    if (exists $data->{Config}) {
        $hosted_zone->{config} = {};
        
        if (exists $data->{Config}{Comment}) {
            $hosted_zone->{config}{comment} = $data->{Config}{Comment};
        }
    }

    return $hosted_zone;
}

sub _parse_health_check_response {
    my ($data) = @_;

    my $health_check = {
        id => $data->{Id},
        caller_reference => $data->{CallerReference},
    };

    my $health_check_config = {
        type => lc $data->{HealthCheckConfig}{Type},
    };

    my %fields = (
        IPAddress                   => 'ip_address',
        Port                        => 'port',
        ResourcePath                => 'resource_path',
        FullyQualifiedDomainName    => 'fully_qualified_domain_name',
        SearchString                => 'search_string',
        RequestInterval             => 'request_interval',
        FailureThreshold            => 'failure_threshold',       
    );

    for (keys %fields) {
        if (exists $data->{HealthCheckConfig}{$_}) {
            $health_check_config->{$fields{$_}} =
                $data->{HealthCheckConfig}{$_};
        }
    }

    $health_check->{health_check_config} = $health_check_config;

    return $health_check;
}

1;
