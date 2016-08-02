package Business::OnlinePayment::CyberSource::Lite;
use strict;
use warnings;

use Business::OnlinePayment;
use Business::OnlinePayment::HTTPS;
use vars qw(@ISA $me $DEBUG $VERSION);
use HTTP::Tiny;
use XML::Writer;
use XML::Simple;
use Text::CSV;
use Business::CreditCard qw(cardtype);
use Data::Dumper;
use Log::Scrubber qw(disable $SCRUBBER scrubber :Carp scrubber_add_scrubber);

@ISA     = qw(Business::OnlinePayment);
$me      = 'Business::OnlinePayment::CyberSource::Lite';
$DEBUG   = 0;
$VERSION = '0.901';

=head1 NAME

Business::OnlinePayment::CyberSource::Lite - Backend for Business::OnlinePayment

=head1 SYNOPSIS

This is a plugin for the Business::OnlinePayment interface.  Please refer to that docuementation for general usage, and here for CyberSource specific usage.

In order to use this module, you will need to have an account set up with CyberSource. L<http://www.cybersource.com/>


  use Business::OnlinePayment;
  my $tx = Business::OnlinePayment->new(
     "CyberSource::Lite",
     default_Origin => 'NEW', # or RECURRING
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

=head2 server_response

Returns the complete response from the server.  The response has been stripped of card_num, cvv2, and password.  So it should be safe to log.

=cut

sub server_response {
    my ( $self, $val, $tf ) = @_;
    if ($val) {
        $self->{server_response} = scrubber $val;
        $self->server_response_dangerous($val,1) unless $tf;
    }
    return $self->{server_response};
}

=head2 server_response_dangerous

Returns the complete response from the server.  This could contain data that is NOT SAFE to log.  It should only be used in a test environment, or in a PCI compliant manner.

=cut

sub server_response_dangerous {
    my ( $self, $val, $tf ) = @_;
    if ($val) {
        $self->{server_response_dangerous} = $val;
        $self->server_response($val,1) unless $tf;
    }
    return $self->{server_response_dangerous};
}

=head1 Handling of content(%content) data:

=head2 action

The following actions are valid

  normal authorization
  authorization only
  post authorization
  credit
  void
  auth reversal

=head1 TESTING

In order to run the provided test suite, you will first need to apply and get your account setup with CyberSource.  Then you can use the test account information they give you to run the test suite. The scripts will look for three environment variables to connect: BOP_USERNAME, BOP_PASSWORD, BOP_MERCHANTID

=head1 FUNCTIONS

=head2 _info

Return the introspection hash for BOP 3.x

=cut

sub _info {
    return {
        info_compat       => '0.01',
        gateway_name      => 'CyberSource - SOAP Toolkit API',
        gateway_url       => 'http://www.cybersource.com',
        module_version    => $VERSION,
        supported_types   => ['CC','ECHECK'],
        supported_actions => {
            CC => [
                'Normal Authorization',
                'Post Authorization',
                'Authorization Only',
                'Credit',
                'Void',
                'Auth Reversal',
            ],
        },
    };
}

=head2 set_defaults

Used by BOP to set default values during "new"

=cut

sub set_defaults {
    my $self = shift;
    my %opts = @_;

    $self->build_subs(
        qw( order_number md5 avs_code cvv2_response card_token cavv_response failure_status verify_SSL )
    );

    $self->build_subs( # built only for backwards compatibily with old cybersource moose version
        qw( response_code response_headers response_page login password require_avs )
    );

    $self->test_transaction(0);
    $self->{_scrubber} = \&_default_scrubber;
}

=head2 test_transaction

Get/set the server used for processing transactions.  Possible values are Live, Certification, and Sandbox
Default: Live

  #Live
  $self->test_transaction(0);

  #Test
  $self->test_transaction(1);

  #Read current value
  $val = $self->test_transaction();

=cut

sub test_transaction {
    my $self = shift;
    my $testMode = shift;
    if (! defined $testMode) { $testMode = $self->{'test_transaction'} || 0; }

    $self->require_avs(0);
    $self->verify_SSL(0);
    $self->port('443');
    $self->path('commerce/1.x/transactionProcessor');

    if (lc($testMode) eq 'sandbox' || lc($testMode) eq 'test' || $testMode eq '1') {
        $self->server('ics2wstest.ic3.com');
        $self->SUPER::test_transaction(1);
    } else {
        $self->server('ics2ws.ic3.com');
        $self->SUPER::test_transaction(0);
    }
}

=head2 submit 

Submit your transaction to cybersource

=cut

sub submit {
    my ($self) = @_;

    local $SCRUBBER=1;
    $self->_tx_init;

    my %content = $self->content();

    my $post_data;
    my $writer = new XML::Writer(
        OUTPUT      => \$post_data,
        DATA_MODE   => 1,
        DATA_INDENT => 2,
        ENCODING    => 'UTF-8',
    );

    $writer->xmlDecl();
    $writer->startTag('soap:Envelope',
        'soap:encodingStyle' => "http://schemas.xmlsoap.org/soap/encoding/",
        'xmlns:soap' => "http://schemas.xmlsoap.org/soap/envelope/",
        'xmlns:soapenc' => "http://schemas.xmlsoap.org/soap/encoding/",
        'xmlns:xsd' => "http://www.w3.org/2001/XMLSchema",
        'xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance",
    );
      $writer->startTag('soap:Header');
        $writer->startTag('wsse:Security','xmlns:wsse'=>'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd');
          $writer->startTag('wsse:UsernameToken');
            $writer->dataElement('wsse:Password', $content{'password'});
            $writer->dataElement('wsse:Username', $content{'login'} );
          $writer->endTag('wsse:UsernameToken');
        $writer->endTag('wsse:Security');
      $writer->endTag('soap:Header');
      $writer->startTag('soap:Body');
        $writer->startTag('requestMessage',xmlns=>'urn:schemas-cybersource-com:transaction-data-1.26');
          $writer->dataElement('merchantID', $content{'login'} );
          $writer->dataElement('merchantReferenceCode', $content{'invoice_number'} );
          $writer->dataElement('clientLibrary', 'Perl-bop-cybersource-lite' );
      if ($content{'name'} && ! defined $content{'last_name'}) {
          ($content{'first_name'}, $content{'last_name'}) =  $content{'name'} =~ /^(.*?)\s*(\w+)$/;
      }
          $writer->startTag('billTo');
            $writer->dataElement('firstName', $content{'first_name'} ) if $content{'first_name'};
            $writer->dataElement('lastName', $content{'last_name'} ) if $content{'last_name'};
            $writer->dataElement('street1', $content{'address'}) if $content{'address'};
            $writer->dataElement('city', $content{'city'}) if $content{'city'};
            $writer->dataElement('state', $content{'state'}) if $content{'state'};
            $writer->dataElement('postalCode', $content{'zip'}) if $content{'zip'};
            $writer->dataElement('country', $content{'country'}) if $content{'country'};
            $writer->dataElement('company', $content{'company'}) if $content{'company'};
            $writer->dataElement('phoneNumber', $content{'phone'}) if $content{'phone'};
            $writer->dataElement('email', $content{'email'}) if $content{'email'};
            $writer->dataElement('ipAddress', $content{'ip'}) if $content{'ip'};
            $writer->dataElement('dateOfBirth', $content{'license_dob'}) if $content{'license_dob'}; # TODO format?
            $writer->dataElement('driversLicenseNumber', $content{'license_num'}) if $content{'license_num'};
            $writer->dataElement('driversLicenseState', $content{'license_state'}) if $content{'license_state'};
            $writer->dataElement('ssn', $content{'customer_ssn'}) if $content{'customer_ssn'};
          $writer->endTag('billTo');
     if ($content{'ship_name'} && ! defined $content{'ship_last_name'}) {
         ($content{'ship_first_name'}, $content{'ship_last_name'}) =  $content{'ship_name'} =~ /^(.*?)\s*(\w+)$/;
     }
     if ($content{'ship_last_name'} || $content{'ship_address'}) {
          $writer->startTag('shipTo');
            $writer->dataElement('firstName', $content{'ship_first_name'} ) if $content{'ship_first_name'};
            $writer->dataElement('lastName', $content{'ship_last_name'} ) if $content{'ship_last_name'};
            $writer->dataElement('street1', $content{'ship_address'}) if $content{'ship_address'};
            $writer->dataElement('city', $content{'ship_city'}) if $content{'ship_city'};
            $writer->dataElement('state', $content{'ship_state'}) if $content{'ship_state'};
            $writer->dataElement('postalCode', $content{'ship_zip'}) if $content{'ship_zip'};
            $writer->dataElement('country', $content{'ship_country'}) if $content{'ship_country'};
            $writer->dataElement('company', $content{'ship_company'}) if $content{'ship_company'};
            $writer->dataElement('phoneNumber', $content{'ship_phone'}) if $content{'ship_phone'};
            $writer->dataElement('email', $content{'ship_email'}) if $content{'ship_email'};
          $writer->endTag('shipTo');
    }
    if ($content{'products'}) {
        my $items = $content{'products'};
        foreach my $id ( 0 .. $#$items ) {
          $writer->startTag('item',id=>$id);
            $writer->dataElement('unitPrice', $items->[$id]->{'cost'} ) if defined $items->[$id]->{'cost'};
            $writer->dataElement('quantity', $items->[$id]->{'quantity'} ) if defined $items->[$id]->{'quantity'};
            $writer->dataElement('productName', $items->[$id]->{'description'} ) if defined $items->[$id]->{'description'};
            $writer->dataElement('productSKU', $items->[$id]->{'code'} ) if defined $items->[$id]->{'code'};
            $writer->dataElement('taxAmount', $items->[$id]->{'tax'} ) if defined $items->[$id]->{'tax'};
            $writer->dataElement('totalAmount', $items->[$id]->{'totalwithtax'} ) if defined $items->[$id]->{'totalwithtax'};
            $writer->dataElement('discountAmount', $items->[$id]->{'discount'} ) if defined $items->[$id]->{'discount'};
          $writer->endTag('item');
        }
    }
          $writer->startTag('purchaseTotals');
            $writer->dataElement('currency', $content{'currency'} // 'USD' );
            $writer->dataElement('taxAmount', $content{'tax'} ) if defined $content{'tax'};
            $writer->dataElement('grandTotalAmount', $content{'amount'} );
            #$writer->dataElement('freightAmount', '1' );
          $writer->endTag('purchaseTotals');
    if ( $content{'type'} eq 'CC' ) {
        if ( $content{'card_number'} ) {
          my ($exp_mon,$exp_year) = $content{'expiration'} =~ /^(\d\d)\/(\d\d)$/;

          # attempt to convert to a valid 4 digit year
          my ($dummy,$dummy2,$hour,$mday,$mon,$year,$wday)=localtime();
          my $centuries = 1900 + $year - ($year % 100);
          $year = $year % 100;
          if ($year > 60 && $exp_year + 20 < $year) { $centuries += 100 }
          $exp_year += $centuries;

          $writer->startTag('card');
            $writer->dataElement('fullName', $content{'name'} ) if $content{'name'};
            $writer->dataElement('accountNumber', $content{'card_number'} );
            $writer->dataElement('expirationMonth', $exp_mon );
            $writer->dataElement('expirationYear', $exp_year );
            $writer->dataElement('cvIndicator', 1 ) if defined $content{'cvv2'};
            $writer->dataElement('cvNumber', $content{'cvv2'} ) if defined $content{'cvv2'};
          $writer->endTag('card');
        }
            # commerceIndicator values
            # internet (default)
            # moto
            # recurring
            # recurring_internet
        if ( $content{'action'} eq 'Authorization Only' || $content{'action'} eq 'Normal Authorization' ) {
          #$writer->emptyTag('ccAuthService',run=>'true');
          $writer->startTag('ccAuthService',run=>'true');
            $writer->dataElement('commerceIndicator', $content{recurring_billing} && $content{recurring_billing} eq 'YES' ? 'recurring_internet' : 'internet' );
          $writer->endTag('ccAuthService');
        }
        if ( $content{'action'} eq 'Normal Authorization' ) {
          $writer->emptyTag('ccCaptureService',run=>'true');
        } elsif ( $content{'action'} eq 'Auth Reversal' ) {
          $writer->startTag('ccAuthReversalService',run=>'true');
            $writer->dataElement('authRequestID', $content{order_number} // $self->order_number );
          $writer->endTag('ccAuthReversalService');
        } elsif ( $content{'action'} eq 'Void' ) {
          $writer->startTag('voidService',run=>'true');
            $writer->dataElement('voidRequestID', $content{order_number} // $self->order_number );
        } elsif ( $content{'action'} eq 'Post Authorization' ) {
          $writer->startTag('ccCaptureService',run=>'true');
            $writer->dataElement('authRequestID', $content{order_number} // $self->order_number );
          $writer->endTag('ccCaptureService');
        } elsif ( $content{'action'} eq 'Credit' ) {
          if ( $content{order_number} // $self->order_number ) {
              #linked credit
          $writer->startTag('ccCreditService',run=>'true');
            $writer->dataElement('captureRequestID', $content{order_number} // $self->order_number );
          $writer->endTag('ccCreditService');
          } else {
              #unlinked credit
          $writer->emptyTag('ccCreditService',run=>'true');
          }
        }
        if ( !$self->require_avs ) {
          $writer->startTag('businessRules');
            $writer->dataElement('ignoreAVSResult', 'true' ) if 1;
          $writer->endTag('businessRules');
        }
    } elsif ( $content{'type'} eq 'ECHECK' ) {
        if ( $content{'action'} eq 'Credit' ) {
          $writer->startTag('ecCreditService',run=>'true');
            $writer->dataElement('debitRequestID', $content{order_number} // $self->order_number );
          $writer->endTag('ecCreditService');
        } elsif ( $content{'action'} eq 'Void' ) {
          $writer->startTag('voidService',run=>'true');
            $writer->dataElement('voidRequestID', $content{order_number} // $self->order_number );
          $writer->endTag('voidService');
        } elsif ( $content{'action'} eq 'Normal Authorization' ) {
          my $name =  $content{'account_name'} // $content{'name'};
          $writer->startTag('check');
            $writer->dataElement('fullName', $name ) if $name;
            $writer->dataElement('accountNumber', $content{'account_number'} ) if $content{'account_number'};
            my $typeTrans = {
                #   BOP                CyberSource
                'Personal Checking' => 'C',
                'Personal Savings'  => 'S',
                'Business Checking' => 'X',
                'Business Savings'  => 'X',
            };
            $writer->dataElement('accountType', $typeTrans->{$content{'account_type'}} // 'C' ) if $content{'account_type'};
            $writer->dataElement('bankTransitNumber', $content{'routing_code'} ) if $content{'routing_code'};
            $writer->dataElement('checkNumber', $content{'check_number'} ) if $content{'check_number'};
          $writer->endTag('check');
          $writer->emptyTag('ecDebitService',run=>'true');
        }
    }
        $writer->endTag('requestMessage');
      $writer->endTag('soap:Body');
    $writer->endTag('soap:Envelope');
    $writer->end();

    $self->server_request( $post_data );

    my $url = 'https://ics2wstest.ic3.com/commerce/1.x/transactionProcessor';
    my $verify_ssl = 1;
    my $response = HTTP::Tiny->new( verify_SSL=>$verify_ssl )->request('POST', $url, {
        headers => {
            'Accept' => 'text/xml',
            'Accept' => 'multipart/*',
            'Accept' => 'application/soap',
            'Content-Type' => 'text/xml; charset=utf-8',
            'SOAPAction' => "urn:schemas-cybersource-com:transaction-data-1.26#requestMessage",
        },
        content => $post_data,
    } );
    $self->server_response( $response->{'content'} );
    my $resp = eval { XMLin($response->{'content'})->{'soap:Body'} } || {};

    # backwards compatibility with old moose client
    $self->response_code( $response->{'status'} );
    $self->response_headers ( $response->{'headers'} );
    $self->response_page ( $self->server_response );
    $self->login ( $content{'login'} );
    $self->password ( $content{'password'} );
    # end compatibility values

    if ( $resp->{'c:replyMessage'} ) {
        $self->is_success( $resp->{'c:replyMessage'}->{'c:reasonCode'} eq '100' ? 1 : 0 );
        $self->result_code( $resp->{'c:replyMessage'}->{'c:reasonCode'} || '' );
        $self->order_number( $resp->{'c:replyMessage'}->{'c:requestID'} || '' );

        if ( $resp->{'c:replyMessage'}->{'c:ccAuthReply'} ) {
            $self->authorization( $resp->{'c:replyMessage'}->{'c:ccAuthReply'}->{'c:authorizationCode'} || '' );
            $self->cvv2_response( $resp->{'c:replyMessage'}->{'c:ccAuthReply'}->{'c:cvCode'} || '' );
            $self->cvv2_response( '' ) if ref $resp->{'c:replyMessage'}->{'c:ccAuthReply'}->{'c:cvCode'}; # empty values become hashrefs
            $self->avs_code( $resp->{'c:replyMessage'}->{'c:ccAuthReply'}->{'c:avsCode'} || '' );
        }

        my $fail_codes = $self->reason_code_hash();
        $self->failure_status($fail_codes->{$resp->{'c:replyMessage'}->{'c:reasonCode'}}->{'failure_status'})
            if $fail_codes->{$resp->{'c:replyMessage'}->{'c:reasonCode'}}->{'failure_status'};
        $self->error_message( $fail_codes->{$resp->{'c:replyMessage'}->{'c:reasonCode'}}->{'desc'} // ($resp->{'c:replyMessage'}->{'c:reasonCode'}.' Unknown reason code') );
    } elsif ( $resp->{'soap:Fault'} ) {
        $self->is_success( undef );
        $self->result_code( undef );
        $self->order_number( undef );
        $self->error_message( $resp->{'soap:Fault'}->{'faultstring'} );
        die $self->error_message; # We die so you can tell the difference between "Approve", "Declined" and "Unknown"
    }
    $self->is_success;
}

sub _default_scrubber {
    my $cc = shift;
    my $del = 'DELETED';
    if (length($cc) > 11) {
        $del = substr($cc,0,6).('X'x(length($cc)-10)).substr($cc,-4,4); # show first 6 and last 4
    } elsif (length($cc) > 5) {
        $del = substr($cc,0,2).('X'x(length($cc)-4)).substr($cc,-2,2); # show first 2 and last 2
    } else {
        $del = ('X'x(length($cc)-2)).substr($cc,-2,2); # show last 2
    }
    return $del;
}

sub _scrubber_add_card {
    my ( $self, $cc ) = @_;
    return if ! $cc;
    my $scrubber = $self->{_scrubber};
    scrubber_add_scrubber({quotemeta($cc)=>&{$scrubber}($cc)});
}

sub _tx_init {
    my ( $self, $opts ) = @_;

    # initialize/reset the reporting methods
    $self->is_success(0);
    $self->server_request('');
    $self->server_response('');
    $self->error_message('');

    # some calls are passed via the content method, others are direct arguments... this way we cover both
    my %content = $self->content();
    foreach my $ptr (\%content,$opts) {
        next if ! $ptr;
        scrubber_init({
            quotemeta($ptr->{'password'}||'')=>'DELETED',
            ($ptr->{'cvv2'} ? '(?<=[^\d])'.quotemeta($ptr->{'cvv2'}).'(?=[^\d])' : '')=>'DELETED',
            });
        $self->_scrubber_add_card($ptr->{'card_number'});
        $self->_scrubber_add_card($ptr->{'account_number'});
    }
}

=head2 reason_code_hash

Returns a list of reason codes usable by the submit function

=cut

sub reason_code_hash {
    # If I can positively identify one of the following we can set failure_status, otherwise leave blank
    # "expired", "nsf" (non-sufficient funds), "stolen", "pickup", "blacklisted"
    # and "declined" (card/transaction declines only, not other errors).

    # reason code and description came from this url, I decided what the failure_status should be based on the description given
    # https://support.cybersource.com/cybskb/index?page=content&id=C156#code_table

    # Reason Code, BOP failure_status, Description
    my $csv_raw =<<EOF;
100,,Successful transaction
101,,The request is missing one or more fields
102,,One or more fields in the request contains invalid data
104,,ThemerchantReferenceCodeﾠsent with this authorization request matches the merchantReferenceCode of another authorization request that you sent in the last 15 minutes.
110,,Partial amount was approved
150,,Error - General system failure.
151,,Error - The request was received but there was a server timeout. This error does not include timeouts between the client and the server.
152,,"Error: The request was received, but a service did not finish running in time."
200,declined,The authorization request was approved by the issuing bank but declined by CyberSource because it did not pass the Address Verification Service (AVS) check
201,declined,"The issuing bank has questions about the request. You do not receive an authorization code programmatically, but you might receive one verbally by calling the processor"
202,expired,"Expired card. You might also receive this if the expiration date you provided does not match the date the issuing bank has on file"
203,declined,General decline of the card. No other information provided by the issuing bank.
204,nsf,Insufficient funds in the account.
205,stolen,Stolen or lost card.
207,,Issuing bank unavailable.
208,declined,Inactive card or card not authorized for card-not-present transactions.
209,declined,American Express Card Identification Digits (CID) did not match.
210,nsf,The card has reached the credit limit.
211,declined,Invalid Card Verification Number (CVN).
220,declined,Generic Decline.
221,blacklisted,The customer matched an entry on the processor's negative file.
222,declined,customer's account is frozen
230,,The authorization request was approved by the issuing bank but declined by CyberSource because it did not pass the card verification number (CVN) check.
231,,Invalid account number
232,,The card type is not accepted by the payment processor.
233,declined,General decline by the processor.
234,,There is a problem with your CyberSource merchant configuration.
235,,"The requested amount exceeds the originally authorized amount. Occurs, for example, if you try to capture an amount larger than the original authorization amount."
236,,Processor failure.
237,,The authorization has already been reversed.
238,,The transaction has already been settled.
239,,The requested transaction amount must match the previous transaction amount.
240,,The card type sent is invalid or does not correlate with the credit card number.
241,,The referenced request id is invalid for all follow-on transactions.
242,,"The request ID is invalid.  You requested a capture, but there is no corresponding, unused authorization record. Occurs if there was not a previously successful authorization request or if the previously successful authorization has already been used in another capture request."
243,,The transaction has already been settled or reversed.
246,,"The capture or credit is not voidable because the capture or credit information has already been submitted to your processor. Or, you requested a void for a type of transaction that cannot be voided."
247,,You requested a credit for a capture that was previously voided.
248,,The boleto request was declined by your processor.
250,,"Error - The request was received, but there was a timeout at the payment processor."
251,,The Pinless Debit card's use frequency or maximum amount per use has been exceeded.
254,,Account is prohibited from processing stand-alone refunds.
400,,Fraud score exceeds threshold.
450,,Apartment number missing or not found.
451,,Insufficient address information.
452,,House/Box number not found on street.
453,,Multiple address matches were found.
454,,P.O. Box identifier not found or out of range.
455,,Route service identifier not found or out of range.
456,,Street name not found in Postal code.
457,,Postal code not found in database.
458,,Unable to verify or correct address.
459,,Multiple addres matches were found (international)
460,,Address match not found (no reason given)
461,,Unsupported character set
475,,The cardholder is enrolled in Payer Authentication. Please authenticate the cardholder before continuing with the transaction.
476,,Encountered a Payer Authentication problem. Payer could not be authenticated.
480,,The order is marked for review by Decision Manager
481,,The order has been rejected by Decision Manager
520,,The authorization request was approved by the issuing bank but declined by CyberSource based on your Smart Authorization settings.
700,blacklisted,The customer matched the Denied Parties List
701,,Export bill_country/ship_country match
702,,Export email_country match
703,,Export hostname_country/ip_country match
EOF

    my %codes;
    my $csv = Text::CSV->new;
    open my $fh, "<:encoding(utf8)", \$csv_raw; 
    while ( my $row = $csv->getline( $fh ) ) {
        $codes{$row->[0]}->{'desc'} = $row->[2];
        $codes{$row->[0]}->{'failure_status'} = $row->[1] if $row->[1];
    }
    close $fh;
    \%codes;
}

1;
