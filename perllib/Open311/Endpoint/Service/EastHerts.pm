package Open311::Endpoint::Service::EastHerts;
use Moo;
extends 'Open311::Endpoint::Service';
use Open311::Endpoint::Service::Attribute;

has '+attributes' => (
    is => 'ro',
    default => sub { [
        Open311::Endpoint::Service::Attribute->new(
            code => 'easting',
            variable => 0, # set by server
            datatype => 'number',
            required => 1,
            description => 'easting',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'northing',
            variable => 0, # set by server
            datatype => 'number',
            required => 1,
            description => 'northing',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'fixmystreet_id',
            variable => 0, # set by server
            datatype => 'string',
            required => 1,
            description => 'external system ID',
        ),
    ] },
);

1;
