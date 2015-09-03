#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojolicious::Plugin::OAuth2;

use Data::Dump qw/dump/;
use Net::Google::Calendar;
use XML::Simple qw(:strict);
use CHI;
use Path::Tiny;


# Documentation browser under "/perldoc"
plugin 'PODRenderer';
plugin "bootstrap3";
plugin 'BootstrapHelpers';

my $ua = Mojo::UserAgent->new;

my $cal;

app->secrets(['Mojolicious rocks']);
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
  $c->render(template => 'index');
};

get '/contact' => sub {
  my $c = shift;
  $c->render(template => 'contact');
};

my $config = plugin 'Config';

plugin 'o_auth2', google => $config->{google};


plugin 'foobar', foo => { bar => 'baz' };

any '/login' => sub {
    my $c = shift;
    unless ($c->param('passwd')) { 
	$c->render(template => 'index');
    } else {
	$c->session(expiration => 60 * 60 * 24 * 2);
	$c->session($_ => $c->param($_)) for grep { $c->param($_) || 1} (qw/passwd domain euser url/);
	# app->log->info($c->param($_)) for grep { $c->param($_) || 1 } (qw/passwd domain euser/);
	$c->redirect_to('/auth');
    }
};

any "/auth" => sub {
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
		     $c->session(guser => 'simone.cesano@gmail.com');
		     $c->redirect_to('g/calendars/simone.cesano@gmail.com');
		 },
		);
};

get '/g/calendars/#user' => sub {
    my $c = shift;
    # app->log->info($c->session('token'));
    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/users/me/calendarList');
    $tx->req->headers->authorization('Bearer ' . $c->session('token'));
    $tx = $ua->start($tx);
    $c->res->headers->content_type('application/json');
    $c->render(text => $tx->res->body);
}; 

get '/g/calendars/#user/#calendar' => sub {
    my $c = shift;
    # app->log->info($c->session('token'));
    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->build_tx('GET' => 'https://www.googleapis.com/calendar/v3/calendars/' . $c->param('calendar') . '/events');
    $tx->req->headers->authorization('Bearer ' . $c->session('token'));
    $tx = $ua->start($tx);
    $c->res->headers->content_type('application/json');
    $c->render(text => $tx->res->body);
}; 

get '/g/calendars/#user/#calendar/create' => sub {
    my $c = shift;
    my $event = {
		 'summary' =>  'Test event Google I/O 2015',
		 'location' =>  '800 Howard St., San Francisco, CA 94103',
		 'description' =>  'A chance to hear more about Google\'s developer products.',
		 'start' =>  {
			      'dateTime' =>  '2015-08-31T09:00:00',
			      'timeZone' =>  'Europe/Berlin',
			     },
		 'end' =>  {
			    'dateTime' =>  '2015-08-31T17:00:00',
			    'timeZone' =>  'America/Los_Angeles',
			   },
		 # 'recurrence' =>  [
		 # 		   'RRULE:FREQ=DAILY;COUNT=2'
		 # 		  ],
		 'attendees' => [
				 { email => 'simone.cesano@adidas.com' }
				],
		 'reminders' =>  {
				  'useDefault' =>  'False',
				  'overrides' =>  [
						   {'method' =>  'email', 'minutes' =>  24 * 60},
						   {'method' =>  'popup', 'minutes' =>  10},
						  ],
				 },
		 sendNotifications => 'True'
		};
	
    
    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->build_tx('POST' => 'https://www.googleapis.com/calendar/v3/calendars/' . $c->param('calendar') . '/events?sendNotifications=true', json => $event);
    $tx->req->headers->authorization('Bearer ' . $c->session('token'));
    
    $tx = $ua->start($tx);
    $c->res->headers->content_type('application/json');
    $c->render(text => $tx->res->body);

};

get '/delete/:calendar/:id' => sub {
    shift->render(text => 'delete id');
};

get '/delete/:calendar/:from/:to' => sub {
    shift->render(text => 'delete from to');
};



get '/e/freebusy' => sub {
    my $c = shift;
    my $url = Mojo::URL->new($c->session('url') . '/public/?Cmd=freebusy&start=2015-08-26T00:00:00Z&end=2015-11-24T00:00:00Z&interval=30&u=simone.cesano@adidas.com');

    $url->userinfo(sprintf('%s\%s:%s', map { $c->session($_) } (qw/domain euser passwd/)));
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->get($url)->res;
    $c->render(json => XMLin($res->content->asset->slurp, ForceArray => 1, KeyAttr => ''))
};

get '/e/folders' => sub {
    my $c = shift;
    my $soap = $c->render_to_string('ews/getfolder', format => 'xml');;

    app->log->info($c->session($_)) for (qw/passwd domain euser url/);
    
    my $ua = Mojo::UserAgent->new;
    my $url = Mojo::URL->new($c->session('url') . '/ews/exchange.asmx');
    $url->userinfo(sprintf('%s\%s:%s', map { $c->session($_) } (qw/domain euser passwd/)));
    my $tx = $ua->build_tx(POST => $url, {'Content-Type' => 'text/xml'}, $soap );
    app->log->info($url);
    $tx->req->headers->content_type('text/xml');
    $tx = $ua->start($tx);
    my $res = $tx->res;

    $c->render(json => XMLin($res->content->asset->slurp, ForceArray => 1, KeyAttr => ''))
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
