package Mock::Response;

use Moo;
use Encode;
use Types::Standard ':all';

has content => (
    is => 'ro',
    isa => Str,
    default => '[]',
    coerce => sub { encode_utf8($_[0]) }
);

has code => (
    is => 'ro',
    isa => Str,
    default => '200',
);

has message => (
    is => 'ro',
    isa => Str,
    default => 'OK',
);

has is_success => (
    is => 'ro',
    isa => Bool,
    default => 1
);

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';

use Path::Tiny;
use Open311::Endpoint;
use Data::Dumper;
use JSON::MaybeXS;

BEGIN { $ENV{TEST_MODE} = 1; }
use Open311::Endpoint::Integration::UK;
use Integrations::WDM;

my $endpoint = Open311::Endpoint::Integration::UK->new;

my %responses = (
    'SOAP UpdateWdmEnquiry' => '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <UpdateWdmEnquiryResponse xmlns="http://www.wdm.co.uk/remedy/">
              <UpdateWdmEnquiryResult>OK</UpdateWdmEnquiryResult>
            </UpdateWdmEnquiryResponse>
          </soap:Body>
        </soap:Envelope>
    ',
    'SOAP CreateInstruction' => '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <CreateInstructionResponse xmlns="http://www.wdm.co.uk/remedy/">
              <CreateInstructionResult>OK</CreateInstructionResult>
            </CreateInstructionResponse>
          </soap:Body>
        </soap:Envelope>
    ',
    'SOAP CreateEnquiry' => '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <CreateEnquiryResponse xmlns="http://www.wdm.co.uk/remedy/">
              <CreateEnquiryResult>OK</CreateEnquiryResult>
            </CreateEnquiryResponse>
          </soap:Body>
        </soap:Envelope>
    ',
    'SOAP GetWdmUpdates' => '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
             <GetWdmUpdatesResponse xmlns="http://www.wdm.co.uk/remedy/">
                 <GetWdmUpdatesResult>
                 <NewDataSet>
                 <wdmupdate>
                        <UpdateID>101</UpdateID>
                        <ENQUIRY_UID>123</ENQUIRY_UID>
                        <ENQUIRY_REFERENCE>ENQ123</ENQUIRY_REFERENCE>
                        <UPDATE_TIME>2018-07-05T16:03:13+01:00</UPDATE_TIME>
                        <EXTERNAL_SYSTEM_REFERENCE>1234</EXTERNAL_SYSTEM_REFERENCE>
                        <STATUS>fixed</STATUS>
                        <COMMENTS>Pothole has been filled</COMMENTS>
                 </wdmupdate>
                 <wdmupdate>
                        <UpdateID>102</UpdateID>
                        <ENQUIRY_UID>456</ENQUIRY_UID>
                        <ENQUIRY_REFERENCE>ENQ456</ENQUIRY_REFERENCE>
                        <UPDATE_TIME>2018-07-05T16:03:13+01:00</UPDATE_TIME>
                        <EXTERNAL_SYSTEM_REFERENCE>1456</EXTERNAL_SYSTEM_REFERENCE>
                        <STATUS>Fixed</STATUS>
                        <COMMENTS>Pothole has been filled</COMMENTS>
                 </wdmupdate>
                 </NewDataSet>
                 </GetWdmUpdatesResult>
            </GetWdmUpdatesResponse>
          </soap:Body>
        </soap:Envelope>
    ',
);

my @sent;

my $integration = Test::MockModule->new('Integrations::WDM');

$integration->mock('_soap_call', sub {
    my ($self, $url, $method, $data) = @_;

    my $x = SOAP::Serializer->new();
    my ($content, $name) = ( $data, 'data' );
    if ( ref($data) eq 'SOAP::Data' ) {
        $content = ${$data->value}->value;
        $name = $data->name;
    } elsif ( ref($data) eq 'ARRAY' ) {
        $content = $x->envelope( method => $method, @$data );
    }
    push @sent, { method => $method, name => $name, content => $content };
    #warn $responses{"SOAP $method"};
    my $som = SOAP::Deserializer->deserialize($responses{"SOAP $method"});
    return $som;
});

my $ox_integration = Test::MockModule->new('Integrations::WDM');
$ox_integration->mock('_build_config_file', sub {
    path(__FILE__)->sibling('oxfordshire.yml');
});

my %defaults = (
    fms_id => 1,
    firstname => 'Bob',
    lastname => 'Mould',
    address_string => '22 Acacia Avenue',
    email => 'test@example.com',
    description => 'description',
    latitude => 50,
    longitude => 0.1,
    easting => 99,
    northing => 101,
    usrn => 48405113,
    category => 'POT',
    category_code => '',
    category_detail => 'POT',
    category_type => '',
);

for my $test (
    {
        test_desc => 'create basic problem',
    },
    {
        test_desc => 'create problem with no usrn',
        usrn => undef,
    },
    {
        test_desc => 'create problem with feature_id',
        feature_id => 100,
    },
) {
    subtest $test->{test_desc} => sub {
        set_fixed_time('2014-01-01T12:00:00Z');
        my $args = {
            %defaults,
            %$test,
        };
        my %post_args = (
            jurisdiction_id => 'oxfordshire',
            api_key => 'test',
            service_code => $args->{category},
            address_string => $args->{address_string},
            first_name => $args->{firstname},
            last_name => $args->{lastname},
            email => $args->{email},
            description => $args->{description},
            lat => $args->{latitude},
            long => $args->{longitude},
            'attribute[description]' => $args->{description},
            'attribute[external_id]' => $args->{fms_id},
            'attribute[easting]' => $args->{easting},
            'attribute[northing]' => $args->{northing},
        );

        $post_args{ 'attribute[usrn]' } = $args->{usrn} if $args->{usrn};
        $post_args{ 'attribute[feature_id]' } = $args->{feature_id} if $args->{feature_id};
        my $res = $endpoint->run_test_request( POST => '/requests.json', %post_args );

        my $sent = pop @sent;
        ok $res->is_success, 'valid request'
            or diag $res->content;


        is $sent->{content}, _generate_request_xml($args), 'correct xml sent';

        is_deeply decode_json($res->content),
            [ {
                "service_request_id" => $args->{fms_id}
            } ], 'correct json returned';

    };
}

subtest "check time uses London time" => sub {
    set_fixed_time('2018-08-01T12:00:00Z');
    my $args = {
        %defaults,
    };
    my %post_args = (
        jurisdiction_id => 'oxfordshire',
        api_key => 'test',
        service_code => $args->{category},
        address_string => $args->{address_string},
        first_name => $args->{firstname},
        last_name => $args->{lastname},
        email => $args->{email},
        description => $args->{description},
        lat => $args->{latitude},
        long => $args->{longitude},
        'attribute[description]' => $args->{description},
        'attribute[external_id]' => $args->{fms_id},
        'attribute[easting]' => $args->{easting},
        'attribute[northing]' => $args->{northing},
        'attribute[usrn]' => $args->{usrn},
    );

    my $res = $endpoint->run_test_request( POST => '/requests.json', %post_args );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    $args->{time} = '2018-08-01 13:00:00';
    is $sent->{content}, _generate_request_xml($args), 'correct xml sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => $args->{fms_id}
        } ], 'correct json returned';

};

for my $category (
    (
        'BR',
        'Row',
        'DR',
        'VG',
        'SP',
        'OT',
        'F D',
        'PT',
        'CD',
        'SN',
        'TLT',
        'TR',
    )
) {
    subtest "check posting with category $category" => sub {
        set_fixed_time('2014-01-01T12:00:00Z');
        my $args = {
            %defaults,
            (
                category => $category,
                category_detail => $category,
            )
        };
        my %post_args = (
            jurisdiction_id => 'oxfordshire',
            api_key => 'test',
            service_code => $category,
            address_string => $args->{address_string},
            first_name => $args->{firstname},
            last_name => $args->{lastname},
            email => $args->{email},
            description => $args->{description},
            lat => $args->{latitude},
            long => $args->{longitude},
            'attribute[description]' => $args->{description},
            'attribute[external_id]' => $args->{fms_id},
            'attribute[easting]' => $args->{easting},
            'attribute[northing]' => $args->{northing},
            'attribute[usrn]' => $args->{usrn},
        );

        my $res = $endpoint->run_test_request( POST => '/requests.json', %post_args );

        my $sent = pop @sent;
        ok $res->is_success, 'valid request'
            or diag $res->content;

        is $sent->{content}, _generate_request_xml($args), 'correct xml sent';
    }
}

subtest "create problem with multiple photos" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'oxfordshire',
        api_key => 'test',
        service_code => 'POT',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[external_id]' => '1',
        'attribute[easting]' => '99',
        'attribute[northing]' => '101',
        'attribute[usrn]' => '48405113',
        media_url => 'http://photo1.com',
        media_url => 'http://photo2.com',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is $sent->{content},
    '<wdmenquiry>
  <comments>description</comments>
  <customer_details>
    <email>test@example.com</email>
    <name>
      <firstname>Bob</firstname>
      <lastname>Mould</lastname>
    </name>
    <telephone_number></telephone_number>
  </customer_details>
  <documents>
    <URL>http://photo1.com</URL>
    <URL>http://photo2.com</URL>
  </documents>
  <easting>99</easting>
  <enquiry_category_code></enquiry_category_code>
  <enquiry_detail_code>POT</enquiry_detail_code>
  <enquiry_reference></enquiry_reference>
  <enquiry_source>FixMyStreet</enquiry_source>
  <enquiry_time>2014-01-01 12:00:00</enquiry_time>
  <enquiry_type_code></enquiry_type_code>
  <external_system_reference>1</external_system_reference>
  <location>
    <item_uid></item_uid>
    <placename>22 Acacia Avenue</placename>
  </location>
  <northing>101</northing>
  <usrn>48405113</usrn>
</wdmenquiry>
',
    'correct xml sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1
        } ], 'correct json returned';
};

subtest "fetch blank updates" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $current_reponse = $responses{'SOAP GetWdmUpdates'};
    $responses{'SOAP GetWdmUpdates'} = '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
             <GetWdmUpdatesResponse xmlns="http://www.wdm.co.uk/remedy/">
                 <GetWdmUpdatesResult><NewDataSet><wdmupdate></wdmupdate></NewDataSet></GetWdmUpdatesResult>
            </GetWdmUpdatesResponse>
          </soap:Body>
        </soap:Envelope>
    ';

    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=oxfordshire&start_date=2018-02-01T12:00:00Z&end_date=2018-02-02T12:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is $sent->{content},
    '<?xml version="1.0" encoding="UTF-8"?><soap:Envelope soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soap:Body><GetWdmUpdates><startDate xsi:type="xsd:string">2018-02-01 12:00:00</startDate><endDate xsi:type="xsd:string">2018-02-02 12:00:00</endDate></GetWdmUpdates></soap:Body></soap:Envelope>';

    is_deeply decode_json($res->content), [], 'correct json returned';

    $responses{'SOAP GetWdmUpdates'} = $current_reponse;
};

subtest "fetch single update" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $current_reponse = $responses{'SOAP GetWdmUpdates'};
    $responses{'SOAP GetWdmUpdates'} = '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
             <GetWdmUpdatesResponse xmlns="http://www.wdm.co.uk/remedy/">
             <GetWdmUpdatesResult>
             <NewDataSet>
             <wdmupdate>
                <UpdateID>101</UpdateID>
                <ENQUIRY_UID>123</ENQUIRY_UID>
                <ENQUIRY_REFERENCE>ENQ123</ENQUIRY_REFERENCE>
                <UPDATE_TIME>2018-07-05T16:03:13.334+01:00</UPDATE_TIME>
                <EXTERNAL_SYSTEM_REFERENCE>1234</EXTERNAL_SYSTEM_REFERENCE>
                <STATUS>fixed</STATUS>
                <COMMENTS>Pothole has been filled</COMMENTS>
            </wdmupdate>
            </NewDataSet>
            </GetWdmUpdatesResult>
            </GetWdmUpdatesResponse>
          </soap:Body>
        </soap:Envelope>
        ';

    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=oxfordshire&start_date=2018-02-01T12:00:00Z&end_date=2018-02-02T12:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'fixed',
        service_request_id => '1234',
        description => 'Pothole has been filled',
        updated_datetime => '2018-07-05T16:03:13+01:00',
        update_id => '101',
        customer_reference => 'ENQ123',
        media_url => '',
    } ], 'correct json returned';

    $responses{'SOAP GetWdmUpdates'} = $current_reponse;
};

subtest "fetch mapped status update" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $current_reponse = $responses{'SOAP GetWdmUpdates'};
    $responses{'SOAP GetWdmUpdates'} = '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
             <GetWdmUpdatesResponse xmlns="http://www.wdm.co.uk/remedy/">
             <GetWdmUpdatesResult>
             <NewDataSet>
             <wdmupdate>
                <UpdateID>101</UpdateID>
                <ENQUIRY_UID>123</ENQUIRY_UID>
                <ENQUIRY_REFERENCE>ENQ123</ENQUIRY_REFERENCE>
                <UPDATE_TIME>2018-07-05T16:03:13.334+01:00</UPDATE_TIME>
                <EXTERNAL_SYSTEM_REFERENCE>1234</EXTERNAL_SYSTEM_REFERENCE>
                <STATUS>mapped_status</STATUS>
                <COMMENTS>Pothole has been filled</COMMENTS>
            </wdmupdate>
            </NewDataSet>
            </GetWdmUpdatesResult>
            </GetWdmUpdatesResponse>
          </soap:Body>
        </soap:Envelope>
        ';

    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=oxfordshire&start_date=2018-02-01T12:00:00Z&end_date=2018-02-02T12:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'in_progress',
        service_request_id => '1234',
        description => 'Pothole has been filled',
        updated_datetime => '2018-07-05T16:03:13+01:00',
        update_id => '101',
        customer_reference => 'ENQ123',
        media_url => '',
    } ], 'correct json returned';

    $responses{'SOAP GetWdmUpdates'} = $current_reponse;
};

subtest "fetch single update with no further action" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $current_reponse = $responses{'SOAP GetWdmUpdates'};
    $responses{'SOAP GetWdmUpdates'} = '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
             <GetWdmUpdatesResponse xmlns="http://www.wdm.co.uk/remedy/">
             <GetWdmUpdatesResult>
             <NewDataSet>
             <wdmupdate>
                <UpdateID>101</UpdateID>
                <ENQUIRY_UID>123</ENQUIRY_UID>
                <ENQUIRY_REFERENCE>ENQ123</ENQUIRY_REFERENCE>
                <UPDATE_TIME>2018-07-05T16:03:13.334+01:00</UPDATE_TIME>
                <EXTERNAL_SYSTEM_REFERENCE>1234</EXTERNAL_SYSTEM_REFERENCE>
                <STATUS>No Further Action</STATUS>
                <COMMENTS>Pothole has been filled</COMMENTS>
            </wdmupdate>
            </NewDataSet>
            </GetWdmUpdatesResult>
            </GetWdmUpdatesResponse>
          </soap:Body>
        </soap:Envelope>
        ';

    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=oxfordshire&start_date=2018-02-01T12:00:00Z&end_date=2018-02-02T12:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'no_further_action',
        service_request_id => '1234',
        description => 'Pothole has been filled',
        updated_datetime => '2018-07-05T16:03:13+01:00',
        update_id => '101',
        customer_reference => 'ENQ123',
        media_url => '',
    } ], 'correct json returned';

    $responses{'SOAP GetWdmUpdates'} = $current_reponse;
};

subtest "fetch multiple updates" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=oxfordshire&start_date=2018-02-01T12:00:00Z&end_date=2018-02-02T12:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'fixed',
        service_request_id => '1234',
        customer_reference => 'ENQ123',
        description => 'Pothole has been filled',
        updated_datetime => '2018-07-05T16:03:13+01:00',
        update_id => '101',
        media_url => '',
    },
    {
        status => 'fixed',
        service_request_id => '1456',
        customer_reference => 'ENQ456',
        description => 'Pothole has been filled',
        updated_datetime => '2018-07-05T16:03:13+01:00',
        update_id => '102',
        media_url => '',
    }
    ], 'correct json returned';
};

subtest "fetch non ENQ update" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $current_reponse = $responses{'SOAP GetWdmUpdates'};
    $responses{'SOAP GetWdmUpdates'} = '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
             <GetWdmUpdatesResponse xmlns="http://www.wdm.co.uk/remedy/">
             <GetWdmUpdatesResult>
             <NewDataSet>
             <wdmupdate>
                <UpdateID>101</UpdateID>
                <ENQUIRY_UID>123</ENQUIRY_UID>
                <ENQUIRY_REFERENCE>123567</ENQUIRY_REFERENCE>
                <UPDATE_TIME>2018-07-05T16:03:13.334+01:00</UPDATE_TIME>
                <EXTERNAL_SYSTEM_REFERENCE>1234</EXTERNAL_SYSTEM_REFERENCE>
                <STATUS>fixed</STATUS>
                <COMMENTS>Pothole has been filled</COMMENTS>
            </wdmupdate>
            </NewDataSet>
            </GetWdmUpdatesResult>
            </GetWdmUpdatesResponse>
          </soap:Body>
        </soap:Envelope>
        ';

    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=oxfordshire&start_date=2018-02-01T12:00:00Z&end_date=2018-02-02T12:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'fixed',
        service_request_id => '123567',
        description => 'Pothole has been filled',
        updated_datetime => '2018-07-05T16:03:13+01:00',
        update_id => '101',
        media_url => '',
    } ], 'correct json returned';

    $responses{'SOAP GetWdmUpdates'} = $current_reponse;
};

subtest "post update" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');

    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        jurisdiction_id => 'oxfordshire',
        api_key => 'test',
        service_request_id => "wdm1234",
        updated_datetime => "2014-01-01T12:00:00Z",
        update_id => 1234,
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'This is an update',
        status => 'INVESTIGATING',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is $sent->{content},
    '<wdmupdateenquiry>
  <comments>This is an update</comments>
  <customer_details>
    <name>
      <email>test@example.com</email>
      <firstname>Bob</firstname>
      <lastname>Mould</lastname>
      <telephone_number></telephone_number>
    </name>
  </customer_details>
  <enquiry_reference>wdm1234</enquiry_reference>
  <enquiry_time>2014-01-01 12:00:00</enquiry_time>
</wdmupdateenquiry>
',
    'correct xml sent';

    is_deeply decode_json($res->content),
    [ {
        update_id => '1234',
    } ], 'correct json returned';
};

subtest "post update that is a defect" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');

    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        jurisdiction_id => 'oxfordshire',
        api_key => 'test',
        service_request_id => "wdm2345",
        updated_datetime => "2014-01-01T12:00:00Z",
        update_id => 2345,
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'This is an update',
        status => 'INVESTIGATING',
        'attribute[raise_defect]' => 1,
        'attribute[easting]' => 400,
        'attribute[northing]' => 300,
        'attribute[usrn]' => 40066632,
        'attribute[town_name]' => 'Witney',
        'attribute[street_descriptor]' => '40066632 - Street Name, Witney',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is $sent->{content}, '<wdm_defect_instruction>
  <comments>This is an update</comments>
  <easting>400</easting>
  <external_system_reference>wdm2345</external_system_reference>
  <instruction_time>01/01/2014 12:00</instruction_time>
  <item_category_uid></item_category_uid>
  <item_detail_uid></item_detail_uid>
  <item_type_uid></item_type_uid>
  <location_description></location_description>
  <northing>300</northing>
  <response_time_uid>73</response_time_uid>
  <street_descriptor>40066632 - Street Name, Witney</street_descriptor>
  <town_name>Witney</town_name>
  <usrn>40066632</usrn>
</wdm_defect_instruction>
',
    'correct xml sent';

    is_deeply decode_json($res->content),
    [ {
        update_id => '2345',
    } ], 'correct json returned';
};

sub _generate_request_xml {
    my $args = shift;

    $args->{usrn} //= 0;
    $args->{phone} //= '';
    $args->{time} //= '2014-01-01 12:00:00';

    return "<wdmenquiry>
  <comments>$args->{description}</comments>
  <customer_details>
    <email>$args->{email}</email>
    <name>
      <firstname>$args->{firstname}</firstname>
      <lastname>$args->{lastname}</lastname>
    </name>
    <telephone_number>$args->{phone}</telephone_number>
  </customer_details>
  <easting>$args->{easting}</easting>
  <enquiry_category_code>$args->{category_code}</enquiry_category_code>
  <enquiry_detail_code>$args->{category_detail}</enquiry_detail_code>
  <enquiry_reference></enquiry_reference>
  <enquiry_source>FixMyStreet</enquiry_source>
  <enquiry_time>$args->{time}</enquiry_time>
  <enquiry_type_code>$args->{category_type}</enquiry_type_code>
  <external_system_reference>$args->{fms_id}</external_system_reference>
  <location>
    <item_uid></item_uid>
    <placename>$args->{address_string}</placename>
  </location>
  <northing>$args->{northing}</northing>
  <usrn>$args->{usrn}</usrn>
</wdmenquiry>
";
}

restore_time();
done_testing;
