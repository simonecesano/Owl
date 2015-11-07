#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/./lib";
use Try::Tiny;

use Mojolicious::Lite;
use Mojolicious::Plugin::OAuth2;
use Mojo::IOLoop;

use Data::Dump qw/dump/;
use DateTime;
use DateTime::Format::ICal;
use DateTime::Format::Strptime;

use Net::Google::Calendar;
use XML::Simple; # qw(:strict);
use CHI;
use Path::Tiny;
use Morg::UserAgent::LWP::NTLM;


# Documentation browser under "/perldoc"
plugin 'PODRenderer';
plugin "bootstrap3";
plugin 'BootstrapHelpers';
plugin 'Morg::Helpers::XPath';
# plugin 'Morg::Helpers::XMLtoJSON';
    
my $ua = Mojo::UserAgent->new;

my $cal;

app->secrets(['Oploo rocks']);
push @{app->routes->namespaces}, 'Blogs';

helper cache => sub {
    state $cache = CHI->new(
			    driver => 'File',
			    root_dir   => Path::Tiny->cwd->child('cache')->stringify,
			    cache_size => '2000k',
			    expires_in => 360,
			    on_set_error => sub { print join "\n", @_ }
			   );
    return $cache
};

get '/' => sub {
  my $c = shift;
  $c->render(template => 'landing');
};

my $config = plugin 'Config';

$config->{google}->{key} ||= $ENV{GOOGLE_KEY};
$config->{google}->{secret} ||= $ENV{GOOGLE_SECRET};

plugin 'o_auth2', google => $config->{google};

app->hook(before_dispatch => sub {
	      my $c = shift;
	      app->log->info(dump $c->req->url)
	  });

any '/e/login' => sub {
    my $c = shift;
    unless ($c->param('passwd')) { 
	$c->render(template => 'e/login');
    } else {
	$c->session(expiration => 60 * 60 * 24 * 2);
	app->log->info($_) for (qw/passwd domain euser url/);
	$c->session($_ => $c->param($_)) for grep { $c->param($_) || 1} (qw/passwd domain euser url/);
	$c->redirect_to('/e/calendar');
    }
};

any "/g/auth" => sub {
    my $c = shift;
    app->log->info($c->req->params);
    app->log->info(ref $c);
    $c->delay(
		 sub {
		     my $delay = shift;
		     $c->oauth2->get_token('google', $delay->begin );
		 },
		 sub {
		     my ($delay, $err, $token) = @_;
		     return $c->render(text => $err) unless $token;
		     $c->session(token => $token);
		     app->log->info("Token: " . dump $token);
		     $c->redirect_to('/g/calendars');
		 },
		);
};

get '/g/calendars' => sub {
    my $c = shift;
    unless ($c->stash('format') =~ /json/i) { return $c->render(template => '/g/calendars') };

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/users/me/calendarList');
    $tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
    $tx = $ua->start($tx);
    $c->res->headers->content_type('application/json');
    $c->render(text => $tx->res->body);
}; 

use Google::Calendar::Cleanup;

get '/g/calendars/#calendar' => sub {
    my $c = shift;

    $c->stash(start => DateTime->now->set( day => 1, minute => 0, second => 0));
    $c->stash(end => $c->stash->{start}->clone->add(months => 2)->set( day => 1, minute => 0, second => 0));

    
    if ($c->param('calendar') =~ /\.json$/) {
	my $calendar = $c->param('calendar') =~ s/\.json$//r;
	my $ua = Mojo::UserAgent->new;
	my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events');
	$tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
	$tx = $ua->start($tx);
	
	my $json = $tx->res->json;
	$json = Google::Calendar::Cleanup->new({ data => $json })->set_duration->flatten_recurrences($c->stash('start'), $c->stash('end'))->data;
	$c->render(json => $json);
    } else {
	return $c->render(template => '/g/calendar');
    }
}; 

get '/g/calendars/#calendar/e/#event' => sub {
    my $c = shift;

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/calendars/' . $c->param('calendar') . '/events/' . $c->param('event'));
    $tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
    $tx = $ua->start($tx);

    my $json = $tx->res->json;
    $c->render(json => $json);
}; 


any '/g/calendars/#calendar/clear' => sub {
    my $c = shift; 
    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/calendars/' . $c->param('calendar') . '/events');
    $tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
    $tx = $ua->start($tx);
    app->log->info($tx->res->code);
    app->log->info($tx->res->body);
    my @items = @{$tx->res->json->{items}};
    app->log->info(scalar @items);
    my @res;
    for (map { $_ } @items) {
	my $tx = $ua->build_tx('DELETE' => 'https://www.googleapis.com/calendar/v3/calendars/' . $c->param('calendar') . '/events/' . $_->{id});
	$tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
	my $res = $ua->start($tx)->res;
	push @res, { body => $res->body, code => $res->code, summary => $_->{summary} };
    }
    $c->render(json => \@res);
};

get '/e/freebusy' => sub {
    my $c = shift;
    my $url = Mojo::URL->new($c->session('url') . '/public/?Cmd=freebusy&start=2015-08-26T00:00:00Z&end=2015-11-24T00:00:00Z&interval=30&u=simone.cesano@adidas.com');

    $url->userinfo(sprintf('%s\%s:%s', map { $c->session($_) } (qw/domain euser passwd/)));
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->get($url)->res;
    $c->render(json => XMLin($res->content->asset->slurp, ForceArray => 1, KeyAttr => ''))
};

get '/e/calendar' => sub {
    my $c = shift;
    unless ($c->stash('format') =~ /json/i) { return $c->render(template => '/e/calendar') };

    $c->stash(start => $c->param('start') || DateTime->now->set( hour => 0, minute => 0, second => 0));
    $c->stash(end => $c->param('end') || $c->stash->{start}->clone->add(weeks => 4));

    my $soap = $c->render_to_string('ews/findappointments', format => 'xml');;
    my $url = Mojo::URL->new($c->session('url') . '/ews/exchange.asmx');
    my $ua = Morg::UserAgent::LWP::NTLM->new(user => $c->session('euser'),
					    password => $c->session('passwd'),
					    endpoint => 'https://deher.webmail.adidas-group.com/ews/exchange.asmx');
    
    my $response = $ua->post($soap);
    if ($response->is_success) {
	# $c->res->headers->content_type('text/xml');
	$c->res->headers->content_type('application/json');
	my $cal = {};
	my $content = $response->decoded_content; 
	if ($c->param('raw')) {
	    $cal = app->parse_xml($content);
	    $c->render(json => $cal);
	} elsif ($c->param('xml')) {
	    $c->res->headers->content_type('text/xml');
	    $c->render(text => $response->decoded_content); 
	} else {
	    $cal->{items}        = [ map { app->parse_xml($_) } app->xpath($content, '//*/t:CalendarItem') ];
	    $cal->{last}         = ([ map { $_->getValue() } app->xpath($content, '//*/@IncludesLastItemInRange') ] || [])->[0] ;
	    $cal->{total_items}  = ([ map { $_->getValue() } app->xpath($content, '//*/@TotalItemsInView') ] || [])->[0];

	    $c->render(json => $cal)
	}
    } else {
	$c->render(json => app->parse_xml($response->decoded_content));
    }
};

get '/e/sync' => sub {
    my $c = shift;
    unless ($c->stash('format') =~ /json/i) { return $c->render(template => '/e/sync') };
};

post '/e/sync' => sub {
    my $c = shift;
    $c->stash(start => $c->param('start') || DateTime->now->set( hour => 0, minute => 0, second => 0));
    $c->stash(end =>
	      $c->param('date_until')
	      ? DateTime::Format::Strptime->new(pattern => '%d-%m-%Y', locale => 'en_US')->parse_datetime($c->param('date_until'))
	      : $c->stash->{start}->clone->add(weeks => 6));

    my $soap = $c->render_to_string('ews/findappointments', format => 'xml');;
    app->log->info($soap);
    my $url = Mojo::URL->new($c->session('url') . '/ews/exchange.asmx');
    my $ua = Morg::UserAgent::LWP::NTLM->new(user => $c->session('euser'),
					    password => $c->session('passwd'),
					    endpoint => 'https://deher.webmail.adidas-group.com/ews/exchange.asmx');
    my $response = $ua->post($soap);
    if ($response->is_success) {
	my $content = $response->decoded_content; 
	my $ecal = {};
	$ecal->{items}        = [ map { app->parse_xml($_) } app->xpath($content, '//*/t:CalendarItem') ];
	$ecal->{last}         = ([ map { $_->getValue() } app->xpath($content, '//*/@IncludesLastItemInRange') ] || [])->[0] ;
	$ecal->{total_items}  = ([ map { $_->getValue() } app->xpath($content, '//*/@TotalItemsInView') ] || [])->[0];

	app->log->info("Included items: " . scalar @{$ecal->{items}});
	app->log->info("Total items: " . $ecal->{total_items});
	my $calendar = $c->param('calendar');
	my $ua = Mojo::UserAgent->new;
	my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events');
	$tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
	$tx = $ua->start($tx);
	my $gcal = $tx->res->json;
	
	my $actions = Google::Calendar::Cleanup->new({ data => $gcal })->sync_actions($ecal);

	for(@{$actions->{delete_items}}) {
	    my $tx = $ua->build_tx('DELETE' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events/' . $_);
	    $tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
	    my $res = $ua->start($tx)->res;
	}
	for(@{$actions->{add_items}}) {
	    my $e = [ map { app->parse_xml($_) } app->xpath($content, '//*/t:CalendarItem[t:UID=\'' . $_ . '\']') ]->[0];
	    app->log->info(dump $e);
	    my $g = Google::Calendar::Cleanup->from_ews($e);
	    my $ua = Mojo::UserAgent->new;
	    my $tx = $ua->build_tx('POST' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events', json => $g);
	    $tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
	    $tx = $ua->start($tx);
	    app->log->info(dump $tx->res->json);
	}
	for(keys %{$actions->{update_items}}) {
	    my $e = [ map { app->parse_xml($_) } app->xpath($content, '//*/t:CalendarItem[t:UID=\'' . $_ . '\']') ]->[0];
	    my $g = [ grep {
		eval { $_->{extendedProperties}->{private}->{ews_id} }
		    && $_->{extendedProperties}->{private}->{ews_id} eq $e->{u_i_d}
		    && $e->{last_modified_time} gt $_->{updated}
		} @{$gcal->{items}} ];
	    if (scalar @$g) {
		my $id = $g->[0]->{id};
		app->log->info(dump $e);
		my $g = Google::Calendar::Cleanup->from_ews($e);
		my $ua = Mojo::UserAgent->new;
		my $tx = $ua->build_tx('PUT' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events/' . $id, json => $g);
		$tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
		$tx = $ua->start($tx);
		app->log->info(dump $tx->res->json);
	    }
	}

	
	$c->render(json => {
			    params  => $c->req->params->to_hash,
			    actions => $actions,
			   });
    } else {
    }
};

get '/g/recur' => sub {
    my $c = shift;
    unless ($c->stash('format') =~ /json/i) { return $c->render(template => '/g/recur') };
};
use Morg::Calendar::Parser;

post '/g/recur' => sub {
    my $c = shift;
    my $p = $c->req->params->to_hash;
    $p->{schedule} = Morg::Calendar::Parser->new(data => $p->{schedule})->parse({ days_first_row => 1})->data;
    $c->render(json => { params  => $p });
};

get '/g/quickinput' => sub {
    my $c = shift;
    unless ($c->stash('format') =~ /json/i) { return $c->render(template => '/g/quickinput') };
};

post '/g/quickinput' => sub {
    my $c = shift;
    my $p = $c->req->params->to_hash;
    my $calendar = $c->param('calendar');
    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->build_tx('POST' => 'https://www.googleapis.com/calendar/v3/calendars/' . $calendar . '/events/quickAdd', form => { text => $c->param('schedule') });
    $tx->req->headers->authorization('Bearer ' . $c->session('token')->{access_token});
    $tx = $ua->start($tx);
    my $gcal = $tx->res->json;

    $c->render(json => { params  => $p, response => $gcal });
};


app->start;

__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
Welcome to the Mojolicious real-time web framework!

@@ contact.html.ep
% layout 'default';
% title 'Welcome';
Done!
    
@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
