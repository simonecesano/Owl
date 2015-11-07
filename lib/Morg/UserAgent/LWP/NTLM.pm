package Morg::UserAgent::LWP::NTLM;

use Moose;
use LWP::UserAgent;
use Authen::NTLM;
use HTTP::Request;
use Data::Dump qw/dump/;

has [qw/user password endpoint/] => ( is => 'rw' );

has 'ua' => ( is => 'rw', default => sub { LWP::UserAgent->new(keep_alive => 1) } );

sub post {
    my $self = shift;
    my $content = shift;
    my $ua = $self->ua;
    my $request = HTTP::Request->new('POST' , $self->endpoint);
    my $response;
    # $request->authorization_basic($self->user, $self->password);
    $request->header('Content-Type' => 'text/xml');
    $request->content($content);
    $response = $ua->request($request);

    $ua->add_handler("request_send",  sub { print STDERR join "\n",
						$self->user, $self->password, '';
					    return });
    # $ua->add_handler("response_done", sub { shift->dump; return });

    # print '-' x 80;
    # print dump $request->headers;
    # print '-' x 80;
    # print dump $response->headers;
    # print '-' x 80;
    if ($response->code eq '401') {
	foreach my $auth_header ($response->header('WWW-Authenticate')) {
	    if ($auth_header =~ /^NTLM/) {
		$response = $self->_ntlm_authenticate($content);
		last;
	    }
	}
    }
    return $response;
}
 
sub _ntlm_authenticate {
    my $self = shift;
    my $content = shift;
    my $ua = $self->ua;
    ntlmv2(2);
    ntlm_user($self->user);
    ntlm_password($self->password);

    my $auth_value = "NTLM " . ntlm();
    # ntlm_reset();
    my $request = HTTP::Request->new('POST' , $self->endpoint);
    $request->header('Content-Type' => 'text/xml','Authorization' => $auth_value);
    $request->content($content);
    # print '-' x 80;
    # print dump $request->headers;
    # print '-' x 80;

    my $response = $ua->request($request);
    foreach my $auth_header ($response->header('WWW-Authenticate')) {
	if($auth_header =~ /^NTLM/) {
	    $auth_value = $auth_header;
	    $auth_value =~ s/^NTLM //;
	    last;
	}
    }
    $auth_value = "NTLM " . ntlm($auth_value);

    $request = HTTP::Request->new('POST' , $self->endpoint);
    $request->header('Content-Type' => 'text/xml','Authorization' => $auth_value);
    $request->content($content);
    # print '-' x 80;
    # print dump $request->headers;
    # print '-' x 80;

    
    $response = $ua->request($request);
    ntlm_reset();
    return $response;
}

__PACKAGE__->meta->make_immutable;

1;

__DATA__

TlRMTVNTUAABAAAAB6IAAAgACAAgAAAAAAAAAAgAAABjZXNhbnNpbQ==
TlRMTVNTUAABAAAAB6IAAAgACAAgAAAAAAAAAAgAAABjZXNhbnNpbQ==
