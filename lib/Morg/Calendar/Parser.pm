package Morg::Calendar::Parser;

use Moose;
use List::MoreUtils qw/pairwise/;
use Hash::Merge qw/merge/;
use Data::Dump qw/dump/;
has data => (is => 'rw');

sub parse {
    my $self = shift;
    my $data = $self->data;
    my $opts = shift || {};
    my $data = [ map { [ map { s/\s$//; $_ } split /\t/ ] } split /\n/, $data ];
    my @days;
    my @times;
    
    if ($opts->{days_first_row}) { @days = @{shift @{$data}}; shift @days };

    if (1) {
	for my $t (@$data) {
	    my $start_end = {};
	    @{$start_end}{qw/start end/} = split /[^0-9:]+/, shift @$t;
	    push @times, $start_end
	};
    } else {

    }

    if ($opts->{days_first_row}) {
	for my $s (@$data) {
	    $s = [ pairwise { return { summary => $a, day => $b } } @{$s}, @days ];
	}
    }
    for (@$data) {
	my $t = shift @times;
	for (@$_) {
	    $_ = merge $_, $t;
	}
    }
    $data = [ grep { $_->{summary} } map { @$_ } @$data ];
    $self->data($data);
    return $self;
}

1;
