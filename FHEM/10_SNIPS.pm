
use strict;
use warnings;

my %gets = (
    "version" => "",
    "status" => ""
);

my %sets = (
    "say" => "",
    "play" => "",
    "startSession" => ""
);

my @topics = qw(
    hermes/intent/+
);

sub SNIPS_Initialize($) {
    my $hash = shift @_;

    # Consumer
    $hash->{DefFn} = "SNIPS::Define";
    $hash->{UndefFn} = "SNIPS::Undefine";
    $hash->{SetFn} = "SNIPS::Set";
    $hash->{AttrFn} = "SNIPS::Attr";
    $hash->{AttrList} = "IODev " . $main::readingFnAttributes;
    $hash->{OnMessageFn} = "SNIPS::onmessage";

    main::LoadModule("MQTT");
    main::LoadModule("MQTT_DEVICE");
}

package SNIPS;

use strict;
use warnings;
use POSIX;
use GPUtils qw(:all);
use JSON;
use Net::MQTT::Constants;

BEGIN {
    MQTT->import(qw(:all));

    GP_Import(qw(
        CommandDeleteReading
        CommandAttr
        readingsSingleUpdate
        readingsBulkUpdate
        readingsBeginUpdate
        readingsEndUpdate
        Log3
        fhem
        defs
        AttrVal
        ReadingsVal
    ))
};

sub Define() {
    my ($hash, $def) = @_;
    my @args = split("[ \t]+", $def);

    return "Invalid number of arguments: define <name> SNIPS" if (int(@args) < 0);

    my ($name, $type) = @args;

    $hash->{MODULE_VERSION} = "0.1";
    $hash->{READY} = 0;

    return MQTT::Client_Define($hash, $def);
};

sub Undefine($$) {
    my ($hash, $name) = @_;

    foreach (@topics) {
        client_unsubscribe_topic($hash, $_);

        Log3($hash->{NAME}, 5, "Topic unsubscribed: " . $_);
    }

    return MQTT::Client_Undefine($hash);
}

sub Set($$$@) {
    my ($hash, $name, $command, @values) = @_;

    Log3($hash->{NAME}, 5, "set " . $command . " - value: " . join (" ", @values));

    if (defined($sets{$command})) {
        # my $msgid;
        # my $retain = $hash->{".retain"}->{'*'};
        # my $qos = $hash->{".qos"}->{'*'};
        #
        # if ($command eq "say") {
        #     my $topic = "hermes/patho/to/tts";
        #     my $value = join (" ", @values);
        #
        #     $msgid = send_publish($hash->{IODev}, topic => $topic, message => $value, qos => $qos, retain => $retain);
        #
        #     Log3($hash->{NAME}, 5, "sent (tts) '" . $value . "' to " . $topic);
        # }
        #
        # $hash->{message_ids}->{$msgid}++ if defined $msgid;

    } else {
        return MQTT::DEVICE::Set($hash, $name, $command, @values);
    }
}

sub Attr($$$$) {
    my ($command, $name, $attribute, $value) = @_;
    my $hash = $defs{$name};

    my $result = MQTT::DEVICE::Attr($command, $name, $attribute, $value);

    if ($attribute eq "IODev") {
        # Subscribe Readings
        foreach (@topics) {
            my ($mqos, $mretain, $mtopic, $mvalue, $mcmd) = MQTT::parsePublishCmdStr($_);
            MQTT::client_subscribe_topic($hash,$mtopic,$mqos,$mretain);

            Log3($hash->{NAME}, 5, "Topic subscribed: " . $_);
        }

        $hash->{READY} = 1;
    }

    return $result;
}

sub onmessage($$$) {
    my ($hash, $topic, $message) = @_;

    Log3($hash->{NAME}, 5, "received message '" . $message . "' for topic: " . $topic);
    my $prefix = "Thyraz";

    # Update readings
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastIntentTopic", $topic);
    readingsBulkUpdate($hash, "lastIntentPayload", $message);
    readingsEndUpdate($hash, 1);

    # hermes/intent published
    if ($topic =~ qr/^hermes\/intent\/$prefix:/) {
        (my $intent = $topic) =~ s/^hermes\/intent\/$prefix://;

        if ($intent = "SwitchOnOff") {

        }
    }

    # if ($topic =~ qr/.*\/?(stat|tele)\/([a-zA-Z1-9]+).*/ip) {
    #     my $type = lc($1);
    #     my $command = lc($2);
    #     my $isJSON = 1;
    #
    #     if ($message !~ m/^\s*{.*}\s*$/s) {
    #         Log3($hash->{NAME}, 5, "no valid JSON, set reading as plain text: " . $message);
    #         $isJSON = 0;
    #     }
    #
    #     Log3($hash->{NAME}, 5, "matched known type '" . $type . "' with command: " . $command);
    #
    #     if ($type eq "stat" && $command eq "power") {
    #         Log3($hash->{NAME}, 4, "updating state to: '" . lc($message) . "'");
    #
    #         readingsSingleUpdate($hash, "state", lc($message), 1);
    #     } elsif ($isJSON) {
    #         Log3($hash->{NAME}, 4, "json in message detected: '" . $message . "'");
    #
    #         TASMOTA::DEVICE::Decode($hash, $command, $message);
    #     } else {
    #         Log3($hash->{NAME}, 4, "fallback to plain reading: '" . $message . "'");
    #
    #         readingsSingleUpdate($hash, $command, $message, 1);
    #     }
    # } else {
    #     # Forward to "normal" logic
    #     MQTT::DEVICE::onmessage($hash, $topic, $message);
    # }
}

sub Expand($$$$) {
    # my ($hash, $ref, $prefix, $suffix) = @_;
    #
    # $prefix = "" if (!$prefix);
    # $suffix = "" if (!$suffix);
    # $suffix = "-$suffix" if ($suffix);
    #
    # if (ref($ref) eq "ARRAY") {
    #     while (my ($key, $value) = each @{$ref}) {
    #         TASMOTA::DEVICE::Expand($hash, $value, $prefix . sprintf("%02i", $key + 1) . "-", "");
    #     }
    # } elsif (ref($ref) eq "HASH") {
    #     while (my ($key, $value) = each %{$ref}) {
    #         if (ref($value)) {
    #             TASMOTA::DEVICE::Expand($hash, $value, $prefix . $key . $suffix . "-", "");
    #         } else {
    #             # replace illegal characters in reading names
    #             (my $reading = $prefix . $key . $suffix) =~ s/[^A-Za-z\d_\.\-\/]/_/g;
    #             readingsBulkUpdate($hash, lc($reading), $value);
    #         }
    #     }
    # }
}

sub Decode($$$) {
    # my ($hash, $reading, $value) = @_;
    # my $h;
    #
    # eval {
    #     $h = decode_json($value);
    #     1;
    # };
    #
    # if ($@) {
    #     Log3($hash->{NAME}, 2, "bad JSON: $reading: $value - $@");
    #     return undef;
    # }
    #
    # readingsBeginUpdate($hash);
    # TASMOTA::DEVICE::Expand($hash, $h, $reading . "-", "");
    # readingsEndUpdate($hash, 1);

    return undef;
}

1;
