package Morg::Helpers::XMLtoJSON;
use base 'Mojolicious::Plugin';

use XML::Simple;
use Mojo::Util qw(decamelize);

sub register {
    my ($self, $app) = @_;
    # $app->helper(to_json => sub { return to_json(@_) });
};


1
