package Integrations::Confirm::IslandRoads;

use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
with 'Role::Config';

has config_filename => (
    is => 'ro',
    default => 'island_roads_confirm',
);

sub _build_config_file {
    my $self = shift;
    path(__FILE__)->parent(4)->realpath->child('conf/council-' . $self->config_filename . '.yml');
}

1;