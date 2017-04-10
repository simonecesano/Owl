#!/usr/bin/env perl
use lib "./lib";

use Mojolicious::Lite;
use Mojo::Util qw(decamelize);

use Data::Dump qw/dump/;
use DateTime;
use DateTime::Format::Strptime;
use Try::Tiny;

use Morg::UserAgent::LWP::NTLM;
use Owl::UserAgent::Google;
use Calendar::Translator::EWS::Google;

# Documentation browser under "/perldoc"
plugin 'PODRenderer';

my $config = plugin 'Config';

$config->{google}->{key} ||= $ENV{GOOGLE_KEY};
$config->{google}->{secret} ||= $ENV{GOOGLE_SECRET};

plugin 'o_auth2', { google => $config->{google} };


get '/' => sub {
  my $c = shift;
  $c->render(template => 'landing');
};


any '/login' => sub {
    my $c = shift;
    unless ($c->param('passwd')) { 
	$c->render(template => 'login');
    } else {
	$c->session(expiration => 60 * 60 * 24 * 2);
	$c->stash(name => $c->param('user'));
	my $soap = $c->render_to_string('ews/resolvenames', format => 'xml');
	app->log->info($soap);

	my $ua = Morg::UserAgent::LWP::NTLM->new(user     => $c->param('user'),
						 password => $c->param('passwd'),
						 endpoint => $c->param('url'));

	my $response = $ua->post($soap);
	app->log->info($response->decoded_content);
	if ($response->is_success) {
	    my $xml = Mojo::DOM->new($response->decoded_content);

	    for (qw/EmailAddress GivenName/) {
		app->log->info(decamelize($_));
		$c->session('ews_' . decamelize($_), $xml->at($_)->text) if $xml->at($_)
	    }
	    
	    for (grep { $c->param($_) || 1} (qw/passwd user url/)) {
		$c->session('ews_' . $_ => $c->param($_));
		app->log->info($_)
	    }
	    $c->redirect_to('/me');
	} else {
	    $c->redirect_to('/error');
	}
    }
};

any "/auth" => sub {
    my $c = shift;
    $c->delay(
		 sub {
		     my $delay = shift;
		     $c->session('oauth_referrer', $c->req->headers->referrer);
		     $c->oauth2->get_token('google', $delay->begin );
		 },
		 sub {
		     my ($delay, $err, $token) = @_;
		     return $c->render(text => $err) unless $token;
		     $c->session(token => $token);

		     my $ua = Owl::UserAgent::Google->new;
		     my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/oauth2/v1/userinfo?alt=json');
		     
		     $tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
		     $tx = $ua->start($tx);
		     my $user_info = $tx->res->json;

		     for (qw/email given_name name/) { $c->session('google_' . $_, $user_info->{$_}) }
		     $c->redirect_to('/me');
		 },
		);
};

get '/sync';

post '/sync' => sub {
    my $c = shift;
    $c->stash(start => $c->param('start') || DateTime->now->set( hour => 0, minute => 0, second => 0));
    $c->stash(end =>
	      $c->param('date_until')
	      ? DateTime::Format::Strptime->new(pattern => '%d-%m-%Y', locale => 'en_US')->parse_datetime($c->param('date_until'))
	      : $c->stash->{start}->clone->add(weeks => 4));

    my $calendar = $c->param('calendar');

    my $ua = Owl::UserAgent::Google->new;
    my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events', => {Accept => '*/*'} => form => { maxResults => 2499 });
    
    $tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
    $tx = $ua->start($tx);
    
    my $gcal = $tx->res->json;

    $c->session('google_calendar_name', $gcal->{summary});
    $c->session('google_calendar_id', $calendar);
    $c->session('google_calendar_last_updated', DateTime->now);
    
    for my $item (@{$gcal->{items}}) {
    	my $tx = $ua->build_tx('DELETE' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events/' . $item->{id});
    	$tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
	$tx = $ua->start($tx, sub { app->log->info($item->{summary}) });
    }
    
    my $soap = $c->render_to_string('ews/findappointments', format => 'xml');;
    my $ua = Morg::UserAgent::LWP::NTLM->new(user => $c->session('ews_user'),
					    password => $c->session('ews_passwd'),
					    endpoint => $c->session('ews_url'));
    my $response = $ua->post($soap);
    
    if ($response->is_success) {
	$c->session('ews_calendar_last_read', DateTime->now);
	my $xml = $response->decoded_content;
	my $dom = Mojo::DOM->new($xml);
	my @items = map { Calendar::Translator::EWS::Google->translate("$_") } @{$dom->find('CalendarItem')->to_array};

	my $ua = Owl::UserAgent::Google->new;
	for my $item (@items) {
	    my $tx = $ua->build_tx('POST' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events', json => $item);
	    try { 
		$tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
		$tx = $ua->start($tx, sub { app->log->info($item->{summary}) });
	    } catch {
		app->log->info('error');
		app->log->info(dump $tx->res->json);
	    }
	}
	$c->render(json => { params => $c->req->params->to_hash });
    } else {
	$c->render(json => { message => 'something went wrong' });
    }
};


get '/me';

put '/config' => sub {

};

get '/error' => sub {
    
};

get '/calendars' => sub {
    my $c = shift;
    unless ($c->stash('format') =~ /json/i) { return $c->render(template => '/calendars') };

    my $ua = Owl::UserAgent::Google->new({ token => $c->session('token')});
    my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/users/me/calendarList');
    $tx = $ua->start($tx);

    my $cals = $tx->res->json;
    my $default = $c->session('google_calendar_id');
    for (grep { $_->{id} eq $default } @{$cals->{items}}) { $_->{default} = 1 }
    
    app->log->info(dump $cals);
    $c->render(json => $cals);
}; 


app->start;
__DATA__
