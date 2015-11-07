package Google::Calendar::Cleanup;

use Moose;

use DateTime;
use DateTime::Format::ICal;
use DateTime::Format::ISO8601;
use Try::Tiny;
use Clone 'clone';
use Data::Dump qw/dump/;
use Set::Scalar;

has data => (is => 'ro');
has dtstart => (is => 'ro');
has dtend => (is => 'ro');

my %WinToOlson =
    (
     'Afghanistan'                     => 'Asia/Kabul',
     'Afghanistan Standard Time'       => 'Asia/Kabul',
     'Alaskan'                         => 'America/Anchorage',
     'Alaskan Standard Time'           => 'America/Anchorage',
     'Arab'                            => 'Asia/Riyadh',
     'Arab Standard Time'              => 'Asia/Riyadh',
     'Arabian'                         => 'Asia/Muscat',
     'Arabian Standard Time'           => 'Asia/Muscat',
     'Arabic Standard Time'            => 'Asia/Baghdad',
     'Argentina Standard Time'         => 'America/Argentina/Buenos_Aires',
     'Armenian Standard Time'          => 'Asia/Yerevan',
     'Atlantic'                        => 'America/Halifax',
     'Atlantic Standard Time'          => 'America/Halifax',
     'AUS Central'                     => 'Australia/Darwin',
     'AUS Central Standard Time'       => 'Australia/Darwin',
     'AUS Eastern'                     => 'Australia/Sydney',
     'AUS Eastern Standard Time'       => 'Australia/Sydney',
     'Azerbaijan Standard Time'        => 'Asia/Baku',
     'Azores'                          => 'Atlantic/Azores',
     'Azores Standard Time'            => 'Atlantic/Azores',
     'Bahia Standard Time'             => 'America/Bahia',
     'Bangkok'                         => 'Asia/Bangkok',
     'Bangkok Standard Time'           => 'Asia/Bangkok',
     'Bangladesh Standard Time'        => 'Asia/Dhaka',
     'Beijing'                         => 'Asia/Shanghai',
     'Belarus Standard Time'           => 'Europe/Minsk',
     'Canada Central'                  => 'America/Regina',
     'Canada Central Standard Time'    => 'America/Regina',
     'Cape Verde Standard Time'        => 'Atlantic/Cape_Verde',
     'Caucasus'                        => 'Asia/Yerevan',
     'Caucasus Standard Time'          => 'Asia/Yerevan',
     'Cen. Australia'                  => 'Australia/Adelaide',
     'Cen. Australia Standard Time'    => 'Australia/Adelaide',
     'Central'                         => 'America/Chicago',
     'Central America Standard Time'   => 'America/Regina',
     'Central Asia'                    => 'Asia/Almaty',
     'Central Asia Standard Time'      => 'Asia/Almaty',
     'Central Brazilian Standard Time' => 'America/Cuiaba',
     'Central Europe'                  => 'Europe/Prague',
     'Central Europe Standard Time'    => 'Europe/Prague',
     'Central European'                => 'Europe/Belgrade',
     'Central European Standard Time'  => 'Europe/Belgrade',
     'Central Pacific'                 => 'Pacific/Guadalcanal',
     'Central Pacific Standard Time'   => 'Pacific/Guadalcanal',
        'Central Standard Time'           => 'America/Chicago',
        'Central Standard Time (Mexico)'  => 'America/Mexico_City',
        'China'                           => 'Asia/Shanghai',
        'China Standard Time'             => 'Asia/Shanghai',
        'Dateline'                        => '-1200',
        'Dateline Standard Time'          => '-1200',
        'E. Africa'                       => 'Africa/Nairobi',
        'E. Africa Standard Time'         => 'Africa/Nairobi',
        'E. Australia'                    => 'Australia/Brisbane',
        'E. Australia Standard Time'      => 'Australia/Brisbane',
        'E. Europe'                       => 'Europe/Helsinki',
        'E. Europe Standard Time'         => 'Europe/Helsinki',
        'E. South America'                => 'America/Sao_Paulo',
        'E. South America Standard Time'  => 'America/Sao_Paulo',
        'Eastern'                         => 'America/New_York',
        'Eastern Standard Time'           => 'America/New_York',
        'Egypt'                           => 'Africa/Cairo',
        'Egypt Standard Time'             => 'Africa/Cairo',
        'Ekaterinburg'                    => 'Asia/Yekaterinburg',
        'Ekaterinburg Standard Time'      => 'Asia/Yekaterinburg',
        'Fiji'                            => 'Pacific/Fiji',
        'Fiji Standard Time'              => 'Pacific/Fiji',
        'FLE'                             => 'Europe/Helsinki',
        'FLE Standard Time'               => 'Europe/Helsinki',
        'Georgian Standard Time'          => 'Asia/Tbilisi',
        'GFT'                             => 'Europe/Athens',
        'GFT Standard Time'               => 'Europe/Athens',
        'GMT'                             => 'Europe/London',
        'GMT Standard Time'               => 'Europe/London',
        'Greenland Standard Time'         => 'America/Godthab',
        'Greenwich'                       => 'GMT',
        'Greenwich Standard Time'         => 'GMT',
        'GTB'                             => 'Europe/Athens',
        'GTB Standard Time'               => 'Europe/Athens',
        'Hawaiian'                        => 'Pacific/Honolulu',
        'Hawaiian Standard Time'          => 'Pacific/Honolulu',
        'India'                           => 'Asia/Calcutta',
        'India Standard Time'             => 'Asia/Calcutta',
        'Iran'                            => 'Asia/Tehran',
        'Iran Standard Time'              => 'Asia/Tehran',
        'Israel'                          => 'Asia/Jerusalem',
        'Israel Standard Time'            => 'Asia/Jerusalem',
        'Jordan Standard Time'            => 'Asia/Amman',
        'Kaliningrad Standard Time'       => 'Europe/Kaliningrad',
        'Kamchatka Standard Time'         => 'Asia/Kamchatka',
        'Korea'                           => 'Asia/Seoul',
        'Korea Standard Time'             => 'Asia/Seoul',
        'Libya Standard Time'             => 'Africa/Tripoli',
        'Line Islands Standard Time'      => 'Pacific/Kiritimati',
        'Magadan Standard Time'           => 'Asia/Magadan',
        'Mauritius Standard Time'         => 'Indian/Mauritius',
        'Mexico'                          => 'America/Mexico_City',
        'Mexico Standard Time'            => 'America/Mexico_City',
        'Mexico Standard Time 2'          => 'America/Chihuahua',
        'Mid-Atlantic'                    => 'Atlantic/South_Georgia',
        'Mid-Atlantic Standard Time'      => 'Atlantic/South_Georgia',
        'Middle East Standard Time'       => 'Asia/Beirut',
        'Montevideo Standard Time'        => 'America/Montevideo',
        'Morocco Standard Time'           => 'Africa/Casablanca',
        'Mountain'                        => 'America/Denver',
        'Mountain Standard Time'          => 'America/Denver',
        'Mountain Standard Time (Mexico)' => 'America/Chihuahua',
        'Myanmar Standard Time'           => 'Asia/Rangoon',
        'N. Central Asia Standard Time'   => 'Asia/Novosibirsk',
        'Namibia Standard Time'           => 'Africa/Windhoek',
        'Nepal Standard Time'             => 'Asia/Katmandu',
        'New Zealand'                     => 'Pacific/Auckland',
        'New Zealand Standard Time'       => 'Pacific/Auckland',
        'Newfoundland'                    => 'America/St_Johns',
        'Newfoundland Standard Time'      => 'America/St_Johns',
        'North Asia East Standard Time'   => 'Asia/Irkutsk',
        'North Asia Standard Time'        => 'Asia/Krasnoyarsk',
        'Pacific'                         => 'America/Los_Angeles',
        'Pacific SA'                      => 'America/Santiago',
        'Pacific SA Standard Time'        => 'America/Santiago',
        'Pacific Standard Time'           => 'America/Los_Angeles',
        'Pacific Standard Time (Mexico)'  => 'America/Tijuana',
        'Pakistan Standard Time'          => 'Asia/Karachi',
        'Paraguay Standard Time'          => 'America/Asuncion',
        'Prague Bratislava'               => 'Europe/Prague',
        'Romance'                         => 'Europe/Paris',
        'Romance Standard Time'           => 'Europe/Paris',
        'Russia Time Zone 10'             => 'Asia/Srednekolymsk',
        'Russia Time Zone 11'             => 'Asia/Anadyr',
        'Russia Time Zone 3'              => 'Europe/Samara',
        'Russian'                         => 'Europe/Moscow',
        'Russian Standard Time'           => 'Europe/Moscow',
        'SA Eastern'                      => 'America/Cayenne',
        'SA Eastern Standard Time'        => 'America/Cayenne',
        'SA Pacific'                      => 'America/Bogota',
        'SA Pacific Standard Time'        => 'America/Bogota',
        'SA Western'                      => 'America/Guyana',
        'SA Western Standard Time'        => 'America/Guyana',
        'Samoa'                           => 'Pacific/Apia',
        'Samoa Standard Time'             => 'Pacific/Apia',
        'Saudi Arabia'                    => 'Asia/Riyadh',
        'Saudi Arabia Standard Time'      => 'Asia/Riyadh',
        'SE Asia'                         => 'Asia/Bangkok',
        'SE Asia Standard Time'           => 'Asia/Bangkok',
        'Singapore'                       => 'Asia/Singapore',
        'Singapore Standard Time'         => 'Asia/Singapore',
        'South Africa'                    => 'Africa/Harare',
        'South Africa Standard Time'      => 'Africa/Harare',
        'Sri Lanka'                       => 'Asia/Colombo',
        'Sri Lanka Standard Time'         => 'Asia/Colombo',
        'Syria Standard Time'             => 'Asia/Damascus',
        'Sydney Standard Time'            => 'Australia/Sydney',
        'Taipei'                          => 'Asia/Taipei',
        'Taipei Standard Time'            => 'Asia/Taipei',
        'Tasmania'                        => 'Australia/Hobart',
        'Tasmania Standard Time'          => 'Australia/Hobart',
        'Tokyo'                           => 'Asia/Tokyo',
        'Tokyo Standard Time'             => 'Asia/Tokyo',
        'Tonga Standard Time'             => 'Pacific/Tongatapu',
        'Turkey Standard Time'            => 'Europe/Istanbul',
        'Ulaanbaatar Standard Time'       => 'Asia/Ulaanbaatar',
        'US Eastern'                      => 'America/Indianapolis',
        'US Eastern Standard Time'        => 'America/Indianapolis',
        'US Mountain'                     => 'America/Phoenix',
        'US Mountain Standard Time'       => 'America/Phoenix',
        'UTC'                             => 'UTC',
        'UTC+12'                          => '+1200',
        'UTC-02'                          => '-0200',
        'UTC-11'                          => '-1100',
        'Venezuela Standard Time'         => 'America/Caracas',
        'Vladivostok'                     => 'Asia/Vladivostok',
        'Vladivostok Standard Time'       => 'Asia/Vladivostok',
        'W. Australia'                    => 'Australia/Perth',
        'W. Australia Standard Time'      => 'Australia/Perth',
        'W. Central Africa Standard Time' => 'Africa/Luanda',
        'W. Europe'                       => 'Europe/Berlin',
        'W. Europe Standard Time'         => 'Europe/Berlin',
        'Warsaw'                          => 'Europe/Warsaw',
        'West Asia'                       => 'Asia/Karachi',
        'West Asia Standard Time'         => 'Asia/Karachi',
        'West Pacific'                    => 'Pacific/Guam',
        'West Pacific Standard Time'      => 'Pacific/Guam',
        'Western Brazilian Standard Time' => 'America/Rio_Branco',
        'Yakutsk'                         => 'Asia/Yakutsk',
        'Yakutsk Standard Time'           => 'Asia/Yakutsk',
    );

sub set_duration {
    my $self = shift;
    for (@{$self->data->{items}}) {
	try {
	    my $start = DateTime::Format::ISO8601->parse_datetime($_->{start}->{dateTime});
	    my $end   = DateTime::Format::ISO8601->parse_datetime($_->{end}->{dateTime});
	    $_->{duration} = $end->subtract_datetime($start)->in_units('minutes');
	} catch {
	    # dump $_; 
	}
    }
    return $self;
}

sub flatten_recurrences {
    my $self = shift;
    my ($start, $end) = @_;
    my @recs;
    for my $i (grep {$_->{recurrence}} @{$self->data->{items}}) {
	my $r;
	$r = [ @{$i->{recurrence}} ];
	for (0..$#{$i->{recurrence}}) {
	    try {
		$i->{recurrence}->[$_] = [ DateTime::Format::ICal->parse_recurrence(recurrence => $i->{recurrence}->[$_], dtstart => $start, dtend => $end )->as_list ];
		for (@{$i->{recurrence}->[$_]}) {
		    my $n = clone($i);
		    $n->{start}->{dateTime} = $_;
		    my $end = $_->clone->add_duration(DateTime::Duration->new(minutes => $i->{duration}));
		    $n->{end}->{dateTime} = "$end";
		    delete $n->{recurrence};
		    push @recs, $n; 
		}
		1;
	    } catch {
		print STDERR $i->{recurrence}->[$_];
	    }
	}
    }
    $self->data->{items} = [grep {!$_->{recurrence}} @{$self->data->{items}}, @recs];
    return $self;
}

sub sync_actions {
    my $self = shift;
    my $gcal = $self->data->{items};
    my $ecal = shift->{items};

    my $i;
    # my $ecal_idx = { map { $_->{u_i_d} => $i++ } @{$ecal}};
    my $gcal_idx = { map { $_->{extendedProperties}->{private}->{ews_id} => $_->{id} } grep { eval { $_->{extendedProperties}->{private}->{ews_id} } } @{$gcal} };

    # sets are all EWS id's 
    my $ecal_set = Set::Scalar->new(map { $_->{u_i_d} } @{$ecal});
    my $gcal_set = Set::Scalar->new(grep { $_ } map { eval { $_->{extendedProperties}->{private}->{ews_id} } } @{$gcal});

    return {
	    delete_items => [ @{$gcal_idx}{@{$gcal_set->difference($ecal_set)}} ],   # ids of google items to be deleted
	    update_items => { map { $_ => $gcal_idx->{$_} } @{$gcal_set->intersection($ecal_set)} }, # hash of items to update indexed by google id
	    add_items    => [ @{$ecal_set->difference($gcal_set)} ],                 # list of items to be added by ews id
	   }
}

use DateTime;
use DateTime::Format::Strptime;

sub from_ews {
    my $class = shift;
    my $e = clone(shift);

    $e->{time_zone} = $WinToOlson{$e->{time_zone}} if $WinToOlson{$e->{time_zone}};
    $e->{time_zone} ||= 'UTC'; $e->{time_zone} = ref $e->{time_zone} ? 'UTC' : $e->{time_zone};
    my $g = {
	     'summary' =>  $e->{subject},
	     'start' =>  { 'dateTime' =>  $e->{start}, 'timeZone' => $e->{time_zone} },
	     'end'   =>  { 'dateTime' =>  $e->{end}, 'timeZone' => $e->{time_zone}},
	     'extendedProperties' => {
				      private => { 
						  ews_change_key =>  $e->{item_id}->{ChangeKey},
						  ews_id => $e->{u_i_d}
						 },
				     }
	    };
    $g->{transparency} = "transparent" if $e->{legacy_free_busy_status} =~ /free/i;
    if ($e->{is_all_day_event} =~ /true/i) {
	my $strp = DateTime::Format::Strptime->new( pattern => '%FT%T%Z', locale => 'en_US');
	$g->{start}->{date} = $strp->parse_datetime(delete $g->{start}->{dateTime});
	dump $e->{time_zone}; 
	$g->{start}->{date}->set_time_zone($e->{time_zone});
	$g->{start}->{date} = $g->{start}->{date}->strftime('%F');

	$g->{end}->{date} = $strp->parse_datetime(delete $g->{end}->{dateTime});
	$g->{end}->{date}->set_time_zone($e->{time_zone});
	$g->{end}->{date} = $g->{end}->{date}->strftime('%F');
    }
    return $g;
}


1;
