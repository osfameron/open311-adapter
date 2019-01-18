package Open311::Endpoint::Integration::Alloy;

use Moo;
use List::Util 'first';
use DateTime::Format::W3CDTF;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

use Open311::Endpoint::Service::UKCouncil::Alloy;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::CanBeNonPublic;

use Path::Tiny;


around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    die unless $args{jurisdiction_id}; # Must have one by here
    $args{config_file} //= path(__FILE__)->parent(5)->realpath->child("conf/council-$args{jurisdiction_id}.yml")->stringify;
    return $class->$orig(%args);
};

has jurisdiction_id => (
    is => 'ro',
);

has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::CanBeNonPublic',
);

has alloy => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new }
);

has config => (
    is => 'lazy',
    default => sub { $_[0]->alloy->config }
);

=head2 service_class

Subclasses can override this to provide their own custom Service class, e.g.
if they want to have extra attributes on all services. We use the
UKCouncil::Alloy class which requests the asset's resource ID as a
separate attribute, so we can attach the defect to the appropriate asset
in Alloy.

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Alloy'
);


sub services {
    my $self = shift;

    my $sources = $self->alloy->get_sources();
    my @services = ();
    for my $source (@$sources) {

        my %service = (
            description => $source->{description},
            service_name => $source->{description},
            service_code => $self->service_code_for_source($source),
        );
        my $o311_service = $self->service_class->new(%service);
        for my $attrib (@{$source->{attributes}}) {
            my %overrides = ();
            if (defined $self->config->{service_attribute_overrides}->{$attrib->{name}}) {
                %overrides = %{ $self->config->{service_attribute_overrides}->{$attrib->{name}} };
            }

            push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(
                code => $attrib->{id},
                description => $attrib->{description},
                datatype => $attrib->{datatype},
                required => $attrib->{required},
                values => $attrib->{values},
                %overrides,
            );
        }
        push @services, $o311_service;
    }
    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    # Get the service code from the args/whatever
    # get the appropriate source type
    my $sources = $self->alloy->get_sources();
    my $source = first { $self->service_code_for_source($_) eq $service->service_code } @$sources;

    # TODO: upload any photos and get their resource IDs, set attachment attribute IDs (?)

    # extract attribute values
    my $resource_id = $args->{attributes}->{asset_resource_id} + 0;
    my $resource = {
        # This is seemingly fine to omit, inspections created via the
        # Alloy web UI don't include it anyway.
        networkReference => undef,

        # This appears to be shared amongst all asset types for now,
        # as everything is based off one design.
        sourceId => $source->{source_id},

        # This is how we link this inspection to a particular asset.
        # The parent_attribute_id tells Alloy what kind of asset we're
        # linking to, and the resource_id is the specific asset.
        # It's a list so perhaps an inspection can be linked to many
        # assets, and maybe even many different asset types, but for
        # now one is fine.
        parents => {
            "$source->{parent_attribute_id}" => [ $resource_id ],
        },

        # No way to include the SRS in the GeoJSON, sadly, so
        # requires another API call to reproject. Beats making
        # open311-adapter geospatially aware, anyway :)
        geoJson => {
            type => "Point",
            coordinates => $self->reproject_coordinates($args->{long}, $args->{lat}),
        }
    };

    # The Open311 attributes received from FMS may not include all the
    # the attributes we need to fully describe the Alloy resource,
    # and indeed these may change on a per-source or per-council basis.
    # Call out to process_attributes which can manipulate the resource
    # attributes (apply defaults, calculate values) as required.
    # This may be overridden by a subclass for council-specific things.
    $resource->{attributes} = $self->process_attributes($source, $args);

    # post it up
    my $response = $self->alloy->api_call("resource", undef, $resource);

    # create a new Request and return it
    return $self->new_request(
        service_request_id => $self->service_request_id_for_resource($response)
    );

}

sub service_request_id_for_resource {
    my ($self, $resource) = @_;

    # get the Alloy inspection reference
    # This may be overridden by subclasses depending on the council's workflow.
    # This default behaviour just uses the resource ID which will always
    # be present.
    return $resource->{resourceId};
}

sub service_code_for_source {
    my ($self, $source) = @_;

    return $source->{source_id} . "_" . $source->{parent_attribute_id};
}

sub process_attributes {
    my ($self, $source, $args) = @_;

    my $attributes = { %{ $args->{attributes} } };
    my $defaults = $self->config->{resource_attribute_defaults};

    foreach (qw/report_url fixmystreet_id northing easting asset_resource_id title description/) {
        delete $attributes->{$_};
    }

    # TODO: Right now this applies defaults regardless of the source type
    # This is OK whilst we have a single design, but we might need to
    # have source-type-specific defaults when multiple designs are in use.
    $attributes = {
        %$attributes,
        %$defaults
    };

    return $attributes;
}

sub reproject_coordinates {
    my ($self, $lon, $lat) = @_;

    my $point = $self->alloy->api_call("projection/point", {
        x => $lon,
        y => $lat,
        srcCode => "4326",
        dstCode => "900913",
    });

    return [ $point->{x}, $point->{y} ];
}

1;