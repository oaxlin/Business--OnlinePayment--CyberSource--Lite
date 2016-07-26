package Business::OnlinePayment::CyberSource::Lite;
use strict;
use warnings;

use Business::OnlinePayment;
use Business::OnlinePayment::HTTPS;
use vars qw(@ISA $me $DEBUG $VERSION);
use MIME::Base64;
use HTTP::Tiny;
use XML::Writer;
use XML::Simple;
use Tie::IxHash;
use Business::CreditCard qw(cardtype);
use Data::Dumper;
use IO::String;
use Carp qw(croak);
use Log::Scrubber qw(disable $SCRUBBER scrubber :Carp scrubber_add_scrubber);

@ISA     = qw(Business::OnlinePayment::HTTPS);
$me      = 'Business::OnlinePayment::CyberSource::Lite';
$DEBUG   = 0;
$VERSION = '0.001';

=head1 NAME

Business::OnlinePayment::CyberSource::Lite - Backend for Business::OnlinePayment

=head1 SYNOPSIS

This is a plugin for the Business::OnlinePayment interface.  Please refer to that docuementation for general usage, and here for CyberSource specific usage.

In order to use this module, you will need to have an account set up with CyberSource. L<http://www.cybersource.com/>


  use Business::OnlinePayment;
  my $tx = Business::OnlinePayment->new(
     "CyberSource::Lite",
     default_Origin => 'NEW',
  );

  $tx->content(
      type           => 'CC',
      login          => 'testdrive',
      password       => '123qwe',
      action         => 'Normal Authorization',
      description    => 'FOO*Business::OnlinePayment test',
      amount         => '49.95',
      customer_id    => 'tfb',
            name           => 'Tofu Beast',
                  address        => '123 Anystreet',
                  city           => 'Anywhere',
                  state          => 'UT',
                  zip            => '84058',
                  card_number    => '4007000000027',
                  expiration     => '09/02',
                  cvv2           => '1234', #optional
                  invoice_number => '54123',
              );
  $tx->submit();

=head1 METHODS AND FUNCTIONS

See L<Business::OnlinePayment> for the complete list. The following methods either override the methods in L<Business::OnlinePayment> or provide additional functions.

=head2 result_code

Returns the response error code.

=head2 error_message

Returns the response error description text.

=head2 server_request

Returns the complete request that was sent to the server.  The request has been stripped of card_num, cvv2, and password.  So it should be safe to log.

=cut

sub server_request {
    my ( $self, $val, $tf ) = @_;
    if ($val) {
        $self->{server_request} = scrubber $val;
        $self->server_request_dangerous($val,1) unless $tf;
    }
    return $self->{server_request};
}

=head2 server_request_dangerous

Returns the complete request that was sent to the server.  This could contain data that is NOT SAFE to log.  It should only be used in a test environment, or in a PCI compliant manner.

=cut

sub server_request_dangerous {
    my ( $self, $val, $tf ) = @_;
    if ($val) {
        $self->{server_request_dangerous} = $val;
        $self->server_request($val,1) unless $tf;
    }
    return $self->{server_request_dangerous};
}



1;
