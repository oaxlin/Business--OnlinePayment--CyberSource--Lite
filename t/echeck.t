#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;

use Test::More;
use Module::Runtime qw( use_module );

my $username = $ENV{PERL_BUSINESS_CYBERSOURCE_USERNAME};
my $password = $ENV{PERL_BUSINESS_CYBERSOURCE_PASSWORD};

plan skip_all => 'No credentials set in the environment.'
  . ' Set PERL_BUSINESS_CYBERSOURCE_USERNAME and '
  . 'PERL_BUSINESS_CYBERSOURCE_PASSWORD to run this test.'
  unless ( $username && $password );

my $client = new_ok( use_module('Business::OnlinePayment'), ['CyberSource::Lite'] );

my $data = {
 login          => $username,
 password       => $password,
 invoice_number => 44544,
 type           => 'ECHECK',
 action         => 'Authorization Only',
 description    => 'Business::OnlinePayment echeck test',
 amount         => '100',
 first_name     => 'John',
 last_name      => 'Doe',
 address        => '900 Metro Center Blvd.',
 city           => 'Poster City',
 state          => 'CA',
 zip            => '94494',
 country        => 'US',
 email          => 'tofu@beast.org',
 account_number => '4100',
 routing_code   => '071923284',
 #check_number   => '123',
 account_type   => 'Personal Checking',
 bank_city      => 'Orem',
 bank_state     => 'UT',
};

$client->content(%$data);
$client->test_transaction(1);    # test, dont really charge

my $success = $client->submit();

is $client->is_success(), $success, 'Success matches';
like $client->order_number(),  qr/^\w+$/, 'Order number is a string';
ok !defined( $client->card_token() ),           'Card token is not defined';
ok !defined( $client->fraud_score() ),          'Fraud score is not defined';
ok !defined( $client->fraud_transaction_id() ), 'Fraud transaction id is not defined';
like $client->response_code(), qr/^\w+$/x, 'Response code is 200'
  or diag $client->response_code();
is ref( $client->response_headers() ), 'HASH', 'Response headers is a hashref';
like $client->response_page(), qr/^.+$/sm, 'Response page is a string';
like $client->result_code(),   qr/^\w+$/,  'Result code is a string';
is $client->transaction_type(), $data->{type}, 'Type matches';
is $client->login(),    $username, 'Login matches';
is $client->password(), $password, 'Password matches';
is $client->test_transaction(), 1,                                   'Test transaction matches';
is $client->require_avs(),      0,                                   'Require AVS matches';
is $client->server(),           'ics2wstest.ic3.com',                'Server matches';
is $client->port(),             443,                                 'Port matches';
is $client->path(),             'commerce/1.x/transactionProcessor', 'Path matches';

$TODO = 'result_code:150, is ach enabled on this test account?' if $client->result_code eq '150';
ok $client->is_success(), 'echeck transaction successful'
  or diag $client->error_message();

$data->{'action'} = 'Credit';
$data->{'amount'} = 50;
$data->{'order_number'} = $client->order_number;
$client->content(%$data);
$success = $client->submit();
ok $client->is_success(), 'credit echeck transaction successful'
  or diag $client->error_message();

done_testing;
