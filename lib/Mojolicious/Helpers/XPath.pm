package Morg::Helpers::XPath;
use base 'Mojolicious::Plugin';

use XML::LibXML;

sub register {
    my ($self, $app) = @_;
    $app->helper(xpath => sub { return xpath(@_) });
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

1
