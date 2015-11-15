package Owl::Babel::EWS;

use Mojo::Util qw(decamelize);

use Moose;

use XML::LibXML;
use XML::Simple; $XML::Simple::PREFERRED_PARSER = "XML::Parser";

use Data::Dump qw/dump/;

# has data => (is => 'rw');
has xpc  => (is => 'rw', default => sub { XML::LibXML::XPathContext->new });
has xml  => (is => 'rw');

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    if ( !ref $_[0] ) {
	my $parser = XML::LibXML->new();
	my $xml = $parser->parse_string($_[0]);
	my $self = $class->$orig( xml => $xml );
	return $self;
    } else {
	return $class->$orig(@_);
    }
};

sub BUILD {
    my $self = shift;
    
    my $xpath = '//namespace::*';
    my $ns = { map { $_->getLocalName(), $_->getValue() } $self->xpc->findnodes($xpath, $self->xml) };
    $self->xpc->registerNs($_, $ns->{$_}) for (keys %$ns);
    return $self;
}

sub findnodes {
    my $self = shift;
    my $xpath = shift;
    my $struct = [ map {
	my $x = $_;
	for (ref $x) {
	    /XML::LibXML::Attr/ && do { $x = $x->getValue; last };
	    /XML::LibXML::Element/ && do { $x = XMLin($x->toString, NormaliseSpace => 2); last };
	    $x = XMLin($x->toString, NormaliseSpace => 2);
	};
	$x
    } $self->xpc->findnodes($xpath, $self->xml) ];
    return $struct;
}

sub data {
    my $self = shift;
    my $xpath = shift;

    my $struct;
    if ($xpath) { $struct = $self->findnodes($xpath);
    } else { $struct = XMLin($self->xml->toString, NormaliseSpace => 2) }
    _recurse($struct);
    return $struct;
}

use DateTime;

sub freebusy {
    my $self = shift;
    my ($start, $end, $interval) = @_;
    my $f = $self->data('//*/a:fbdata');
    my $names = $self->data('//*/a:displayname');
    $f = [ map { [ split '', $_ ] } @$f ];

    my @people = (1..$#{$f});
    for my $h (0..$#{$f->[0]}) {
	$f->[0]->[$h] = ((scalar grep { $_ == 0 } map { $f->[$_]->[$h] } @people) / scalar @people);
    }
    my @slots = map { $start->clone->add(minutes => $interval * $_) } (0..$#{$f->[0]});
    
    my $o = {};
    shift @$names;
    $o->{availability} = shift @$f;
    $o->{slots} = \@slots; #} = @{shift @$f};
    @{$o->{freebusy}}{@$names} = @$f;
    return $o;
}

sub _recurse {
    my $s = shift;
    for (ref $s) {
	/HASH/ && do {
	    my @keys = keys %$s;
	    for my $k (@keys) {
		_recurse($s->{$k});
		local $_ = $k; s/^.+?://g; $_ = decamelize($_);
		$s->{$_} = delete $s->{$k};
	    };
	    last;
	};
	/ARRAY/ && do {
	    _recurse($_) for (@$s);
	    last;
	};
    }
}

__PACKAGE__->meta->make_immutable;

1;

__DATA__
