
use strict;
use warnings;

my %gets = (
    "version" => "",
    "status" => ""
);

my %sets = (
    "say" => "",
    "play" => ""
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
        my $msgid;
        my $retain = $hash->{".retain"}->{'*'};
        my $qos = $hash->{".qos"}->{'*'};
        
        if ($command eq "say") {
            my $topic = "hermes/path/to/tts";
            my $value = join (" ", @values);
        
            $msgid = send_publish($hash->{IODev}, topic => $topic, message => $value, qos => $qos, retain => $retain);
        
            Log3($hash->{NAME}, 5, "sent (tts) '" . $value . "' to " . $topic);
        }
        
        $hash->{message_ids}->{$msgid}++ if defined $msgid;
    }
}

sub Attr($$$$) {
    my ($command, $name, $attribute, $value) = @_;
    my $hash = $defs{$name};

    if ($attribute eq "IODev") {
        # Subscribe Readings
        foreach (@topics) {
            my ($mqos, $mretain, $mtopic, $mvalue, $mcmd) = MQTT::parsePublishCmdStr($_);
            MQTT::client_subscribe_topic($hash,$mtopic,$mqos,$mretain);

            Log3($hash->{NAME}, 5, "Topic subscribed: " . $_);
        }
        $hash->{READY} = 1;
        return undef;
    }

    return "Error: Unhandled attribute";
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
            # Parse JSON from payload
        }
    }
}

sub parse($$) {
    # my ($hash, $value) = @_;

    return undef;
}

1;
