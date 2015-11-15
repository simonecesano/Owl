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

use Owl::UserAgent::Google;

use Net::Google::Calendar;
use XML::Simple; $XML::Simple::PREFERRED_PARSER = "XML::Parser";
use CHI;
use Path::Tiny;
use Morg::UserAgent::LWP::NTLM;
use Morg::Calendar::Parser;


# Documentation browser under "/perldoc"
plugin 'PODRenderer';
plugin "bootstrap3";
plugin 'BootstrapHelpers';
# plugin 'Renderer::XML';
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
	      # app->log->info(dump $c->req->url)
	  });

any '/e/login' => sub {
    my $c = shift;
    unless ($c->param('passwd')) { 
	$c->render(template => 'e/login');
    } else {
	$c->session(expiration => 60 * 60 * 24 * 2);
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
		     $c->session('oauth_referrer', $c->req->headers->referrer);
		     $c->oauth2->get_token('google', $delay->begin );
		 },
		 sub {
		     my ($delay, $err, $token) = @_;
		     return $c->render(text => $err) unless $token;
		     $c->session(token => $token);
		     $c->redirect_to($c->req->headers->referrer || '/g/calendars');
		 },
		);
};

get '/g/calendars' => sub {
    my $c = shift;
    unless ($c->stash('format') =~ /json/i) { return $c->render(template => '/g/calendars') };

    my $ua = Owl::UserAgent::Google->new({ token => $c->session('token')});
    my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/users/me/calendarList');
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

get '/e/me' => sub {
    my $c = shift;
    $c->stash(text => $c->session('euser'));
    my $soap = $c->render_to_string('ews/names', format => 'xml');;
    my $url = Mojo::URL->new($c->session('url') . '/ews/exchange.asmx');
    my $ua = Morg::UserAgent::LWP::NTLM->new(user => $c->session('euser'),
					    password => $c->session('passwd'),
					    endpoint => 'https://deher.webmail.adidas-group.com/ews/exchange.asmx');
    
    my $response = $ua->post($soap);
    if ($response->is_success) {
	$c->res->headers->content_type('text/xml');
	$c->render(text => $response->decoded_content);
    } else {
	$c->render(text => $response->decoded_content);
    }
};

use Mojo::Util qw(b64_encode url_escape url_unescape);
use Owl::Babel::EWS;

use List::MoreUtils qw/mesh natatime/;

any '/e/meet' => sub {
    my $c = shift;

    unless ($c->stash('format') =~ /json/i) {
	if ($c->req->params->to_string) {
	    return $c->render(template => '/e/meet')
	} else {
	    return $c->render(template => '/e/meet_form')
	}
    };

    app->log->info(dump $c->session('params'));
    app->log->info($c->session);

    my @people = map { s/^\s+|\s+$//g; $_ } grep { /\w/ } split /\n|\r|\f/, $c->param('people');
    return $c->render(json => {
			       error => 'no people selected',
			       people => $c->param('people')
			      } ) unless scalar @people;
    
    my $start = DateTime->now(time_zone  => 'CET')->set( minute => 0, second => 0);
    my $end = $start->clone->add( days => ($c->param('interval') || 15) );
    
    my $url = Mojo::URL->new('https://deher.webmail.adidas-group.com/public/');
    my $par = Mojo::Parameters->new;
    $par->append(Cmd => 'freebusy', start => "$start", end => "$end", interval => 30);

    my @people = map { s/^\s+|\s+$//g; $_ } grep { /\w/ } split /\n|\r|\f/, $c->param('people');
    for (@people) { $par->append( u => $_ ) };

    $url->query( url_unescape "$par" );
    $url->userinfo(sprintf('%s\%s:%s', ('emea', $c->session('euser'), $c->session('passwd'))));
    app->log->info($url);
    
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->get($url)->res;
    my $data = Owl::Babel::EWS->new($res->content->asset->slurp);
    $c->render(json => $data->freebusy($start, $end, 30));
};


get '/e/organize' => sub {
    my $c = shift;
    $c->render(json => $c->req->params->to_hash());
};

get '/g/recur' => sub {
    my $c = shift;
    unless ($c->stash('format') =~ /json/i) { return $c->render(template => '/g/recur') };
};


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

get '/g/geocode' => sub {
    my $c = shift;
    my $ua = Mojo::UserAgent->new;
    # https://maps.googleapis.com/maps/api/timezone/json?location=Portland&key='
    my $tx = $ua->build_tx('GET' => 'https://maps.googleapis.com/maps/api/geocode/json?address=Portland OR' .
			   'AIzaSyAw_6PO5Il8f4ULbJvc53K1SFlxZvx5fW8');
    $tx = $ua->start($tx);
    app->log->info(dump $tx->res);
    
    $c->render(json => { response => $tx->res->json });
};

get '/x/xml' => sub {
    my $c = shift;
    app->log->info(ref $c);
    app->log->info(dump $c->app->renderer->handlers);
    $c->render( wee => 'bar' );
};

get '/x/dump' => sub {
    my $c = shift;
    $c->res->headers->content_type('text/plain');
    
    $c->render(text => dump app->renderer);

};

get '/x/types' => sub {
    my $c = shift;
    $c->res->headers->content_type('text/plain');
    
    $c->render(text => app->types->type('xml'));

};

get '/e/resolve/#name' => sub {
    my $c = shift;
    $c->stash('name', $c->param('name'));
    my $soap = $c->render_to_string('ews/resolvenames', format => 'xml');;
    my $url = Mojo::URL->new($c->session('url') . '/ews/exchange.asmx');

    my $ua = Morg::UserAgent::LWP::NTLM->new(user => $c->session('euser'),
					    password => $c->session('passwd'),
					    endpoint => 'https://deher.webmail.adidas-group.com/ews/exchange.asmx');
    
    my $res = $ua->post($soap);
    if ($res->is_success) {
	my $data = Owl::Babel::EWS->new($res->decoded_content);
	$c->render(json => $data->data('//*/t:EmailAddress'));
    } else {
	$c->render(text => $res->decoded_content);
    }
    
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
