package WebService::Amazon::Route53;

use warnings;
use strict;

# ABSTRACT: Perl interface to Amazon Route 53 API

# VERSION

use Carp;
use Module::Load;

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
    my $response = $r53->find_hosted_zone(name => 'example.com.');
    my $zone = $response->{hosted_zone};
    
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

my @versions = ( qw/ 20110505 20130401 / );

=head1 METHODS

Required parameters are marked as such, other parameters are optional.

Instance methods return a false value on failure. More detailed error
information can be obtained by calling L<"error">.

The methods described below correspond to the 2013-04-01 version of the Route53
API. For the 2011-05-05 version, see
L<WebService::Amazon::Route53::API::20110505>.

=head2 new

Creates a new instance of a WebService::Amazon::Route53 API class.

    my $r53 = WebService::Amazon::Route53->new(id => 'ROUTE53ID',
                                               key => 'SECRETKEY');

Based on the value of the C<version> parameter, the matching subclass of
WebService::Amazon::Route53::API is instantiated (e.g., for C<version> set to
C<"2013-04-01">, L<WebService::Amazon::Route53::API::20130401> is used). If the
C<version> parameter is omitted, the latest supported version is selected
(currently C<"2013-04-01">).

Parameters:

=over 4

=item * id

B<(Required)> AWS access key ID.

=item * key

B<(Required)> Secret access key.

=item * version

Route53 API version (either C<"2013-04-01"> or C<"2011-05-05">, default:
C<"2013-04-01">).

=back

=cut

sub new {
    my ($class, %args) = @_;
    
    # Use most recent API version by default
    my $version = $versions[$#versions];

    if (defined $args{'version'}) {
        ($version = $args{'version'}) =~ s/[^0-9]//g;

        if (!grep { $_ eq $version } @versions) {
            croak "Unknown API version";
        }
    }

    delete $args{version};

    load "WebService::Amazon::Route53::API::$version";

    return ('WebService::Amazon::Route53::API::' . $version)->new(%args);
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

=head1 SEE ALSO

=for :list

* L<Amazon Route 53 API Reference|http://docs.amazonwebservices.com/Route53/latest/APIReference/>

=cut

1; # End of WebService::Amazon::Route53
