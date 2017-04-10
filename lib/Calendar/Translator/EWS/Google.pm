package Calendar::Translator::EWS::Google;

use strict;

use Calendar::Translator::EWS::Timezones;
use XML::Hash::XS;

sub translate {
    my $self = shift;
    my $ews = shift;
    unless (ref $ews) { $ews = xml2hash($ews) }
    $ews = cleanup($ews);

    my $gcal = {};
    $gcal->{summary} = $ews->{subject};
    $gcal->{location} = $ews->{location};
    for (qw/start end/) { $gcal->{$_}->{dateTime} = $ews->{$_} }
    if (my $tz = ews_tz_to_iana($ews->{time_zone})) {
	for (qw/start end/) { $gcal->{$_}->{timeZone} = $tz } }
    $gcal->{extendedProperties}->{private}->{id} = $ews->{item_id}->{id};
    unless ($ews->{legacy_free_busy_status} eq 'Free') { $gcal->{transparency} = 'opaque' } else { $gcal->{transparency} = 'transparent' }
    
    return $gcal;
}

sub cleanup {
    my ($hash) = @_;
    my @keys = keys %$hash;
    for my $key (@keys) {
	my $new_key = $key;
	for ($new_key) {
	    s/^\w+://;
	    $_ = decamelize($_)
	};
	my $value = delete $hash->{$key};
	$hash->{$new_key} = $value;
        if ('HASH' eq ref $value) {
            cleanup ($value);
        } else {
	    $value =~ s/^\s+|\s+$//gs;
	    $value =~ s/\s*\n\s*/ /gs;
	    $hash->{$new_key} = $value;
	}
    }
    return $hash;
}

sub decamelize {
	my $s = shift;
	$s =~ s{([^a-zA-Z]?)([A-Z]*)([A-Z])([a-z]?)}{
		my $fc = pos($s)==0;
		my ($p0,$p1,$p2,$p3) = ($1,lc$2,lc$3,$4);
		my $t = $p0 || $fc ? $p0 : '_';
		$t .= $p3 ? $p1 ? "${p1}_$p2$p3" : "$p2$p3" : "$p1$p2";
		$t;
	}ge;
	$s;
}

1;
