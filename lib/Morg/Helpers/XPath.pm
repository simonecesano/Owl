package Morg::Helpers::XPath;
use base 'Mojolicious::Plugin';

use XML::LibXML;
use XML::Simple; $XML::Simple::PREFERRED_PARSER = "XML::Parser";
use Mojo::Util qw(decamelize);

sub register {
    my ($self, $app) = @_;
    $app->helper(xpath => sub { return xpath(@_) });
    $app->helper(parse_xml => sub { return to_struct(@_) });
};

sub xpath {
    my ($c, $xml, $xpath) = @_;

    my $parser = XML::LibXML->new();
    $xml = $parser->parse_string($xml);

    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs('t', 'http://schemas.microsoft.com/exchange/services/2006/types');
    $xpc->registerNs('m', 'http://schemas.microsoft.com/exchange/services/2006/messages');

    
    return $xpc->findnodes($xpath, $xml);
}

sub to_struct {
    my ($c, $xml, $sub) = @_;
    $sub ||= sub {
	my $h = shift;
	for (keys %$h) {
	    my $o = $_;
	    s/.+?://; $_ = decamelize($_);
	    $h->{$_} = delete $h->{$o};
	}
	return $h;
    };
    return $sub->(XMLin(ref $xml ? $xml->toString : $xml, 'ForceArray' => 0));
}

1
