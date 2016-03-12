package Owl::UserAgent::Google;

use Mojo::Base 'Mojo::UserAgent';

has 'token';

# check http://mojolicio.us/perldoc/Mojo/UserAgent#start

# sub new {
#     my $self = shift;

#     return $self->SUPER::new;
# }

sub build_tx {
    my $self = shift;
    if ($self->token) {
	my $tx = $self->SUPER::build_tx(@_);
	$tx->req->headers->authorization('Bearer ' . $self->token->{access_token});
	return $tx;
    } else {
	return $self->SUPER::build_tx(@_);
    }
}

1
