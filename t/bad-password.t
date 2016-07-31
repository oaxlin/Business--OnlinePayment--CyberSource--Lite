#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;

use Test::More;
use Module::Runtime qw( use_module );

my $username = 'fred_badpassword';
my $password = 'badpassword';

my $client = new_ok( use_module('Business::OnlinePayment'), ['CyberSource::Lite'] );

my $data = {
 login          => $username,
 password       => $password,
 invoice_number => 44544,
 type           => 'CC',
 action         => 'Authorization Only',
 description    => 'Business::OnlinePayment visa test',
 amount         => '9000',
 first_name     => 'Tofu',
 last_name      => 'Beast',
 address        => '123 Anystreet',
 city           => 'Anywhere',
 state          => 'UT',
 zip            => '84058',
 country        => 'US',
 email          => 'tofu@beast.org',
 card_number    => '4111111111111111',
 expiration     => '12/25',
 cvv2           => 1111, };

$client->content(%$data);
$client->test_transaction(1);    # test, dont really charge

my $success = eval {$client->submit()};

ok !$client->is_success(), 'transaction unsuccessful'
  or diag $client->error_message();

is $client->is_success(), $success, 'Success matches';
like $client->response_code(), qr/^\w+$/x, 'Response code is 200'
  or diag $client->response_code();

like $client->error_message(), qr/authentication failed/, 'Verify auth failed';
is $client->result_code(), undef, 'Verify no result_code exits';
is $client->order_number(), undef, 'Verify no order_number exits';
done_testing;
