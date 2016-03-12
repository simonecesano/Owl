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
plugin 'Morg::Helpers::XPath';
    
my $ua = Mojo::UserAgent->new;

my $cal;

plugin Mount => {'/g' => './gcal/g.pl'};
plugin Mount => {'/e' => './ews/e.pl'};

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

app->start;
