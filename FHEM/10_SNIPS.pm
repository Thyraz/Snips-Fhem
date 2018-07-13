
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

# MQTT Topics die das Modul automatisch abonniert
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
    $hash->{AttrList} = "IODev prefix defaultRoom " . $main::readingFnAttributes;
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
        devspec2array
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


# Device anlegen
sub Define() {
    my ($hash, $def) = @_;
    my @args = split("[ \t]+", $def);

    # Minimale Anzahl der nötigen Argumente vorhanden?
    return "Invalid number of arguments: define <name> SNIPS" if (int(@args) < 0);

    my ($name, $type) = @args;

    $hash->{MODULE_VERSION} = "0.1";
    $hash->{READY} = 0;

    # Weitere Schritte an das MQTT Modul übergeben, damit man dort als Client registriert wird
    return MQTT::Client_Define($hash, $def);
};


# Device löschen
sub Undefine($$) {
    my ($hash, $name) = @_;

    # MQTT Abonnements löschen
    foreach (@topics) {
        client_unsubscribe_topic($hash, $_);
        Log3($hash->{NAME}, 5, "Topic unsubscribed: " . $_);
    }

    # Weitere Schritte an das MQTT Modul übergeben, damit man dort als Client ausgetragen wird
    return MQTT::Client_Undefine($hash);
}


# Set Befehl aufgerufen
sub Set($$$@) {
    my ($hash, $name, $command, @values) = @_;

    Log3($hash->{NAME}, 5, "set " . $command . " - value: " . join (" ", @values));

    if (defined($sets{$command})) {
        my $msgid;
        my $retain = $hash->{".retain"}->{'*'};
        my $qos = $hash->{".qos"}->{'*'};

        # Say Befehl
        if ($command eq "say") {
            my $topic = "hermes/path/to/tts";
            my $value = join (" ", @values);

            $msgid = send_publish($hash->{IODev}, topic => $topic, message => $value, qos => $qos, retain => $retain);
            Log3($hash->{NAME}, 5, "sent (tts) '" . $value . "' to " . $topic);
        }

        $hash->{message_ids}->{$msgid}++ if defined $msgid;
    }
}

# Attribute setzen / löschen
sub Attr($$$$) {
    my ($command, $name, $attribute, $value) = @_;
    my $hash = $defs{$name};

    # IODev Attribut gesetzt
    if ($attribute eq "IODev") {
        # Topics abonnieren
        foreach (@topics) {
            my ($mqos, $mretain, $mtopic, $mvalue, $mcmd) = MQTT::parsePublishCmdStr($_);
            MQTT::client_subscribe_topic($hash,$mtopic,$mqos,$mretain);

            Log3($hash->{NAME}, 5, "Topic subscribed: " . $_);
        }
        $hash->{READY} = 1;
        return undef;
    }

    return undef;
}


# Empfangene Daten vom MQTT Modul
sub onmessage($$$) {
    my ($hash, $topic, $message) = @_;
    my $prefix = AttrVal($hash->{NAME},"prefix",undef);

    Log3($hash->{NAME}, 5, "received message '" . $message . "' for topic: " . $topic);

    # Readings updaten
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastIntentTopic", $topic);
    readingsBulkUpdate($hash, "lastIntentPayload", $message);
    readingsEndUpdate($hash, 1);

    # hermes/intent published
    if ($topic =~ qr/^hermes\/intent\/$prefix:/) {
        # MQTT Pfad und Prefix vom Topic entfernen
        (my $intent = $topic) =~ s/^hermes\/intent\/$prefix://;
        Log3($hash->{NAME}, 1, "Intent: $intent");

        # JSON parsen
        my $data = SNIPS::parse($hash, $intent, $message);

        if ($intent eq 'SwitchOnOff') {
            SNIPS::handleIntentOn($hash, $data);
        }
    }
}


# JSON parsen
sub parse($$$) {
    my ($hash, $intent, $json) = @_;
    my $data;

    # JSON Decode und Fehlerüberprüfung
    my $decoded = eval { decode_json($json) };
    if ($@) {
          return undef;
    }

    # Standard-Keys auslesen
    $data->{'probability'} = $decoded->{'intent'}{'probability'};
    $data->{'sessionId'} = $decoded->{'sessionId'};
    $data->{'siteId'} = $decoded->{'siteId'};

    # Überprüfen ob Slot Array existiert
    if (ref($decoded->{'slots'}) eq 'ARRAY') {
        my @slots = @{$decoded->{'slots'}};

        # Key -> Value Paare aus dem Slot Array ziehen
        foreach my $slot (@slots) {
            my $slotName = $slot->{'slotName'};
            my $slotValue = $slot->{'value'}{'value'};

            $data->{$slotName} = $slotValue;
        }
    }
    return $data;
}


# Eingehende "On" Intents bearbeiten
sub handleIntentOn ($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $deviceName;

    if (exists($data->{'Device'}) && exists($data->{'Value'})) {
        my $room = roomName($hash, $data);
        Log3($hash->{NAME}, 5, "On-Intent: " . $room . " " . $data->{'Device'} . " " . $data->{'Value'});

        $value = ($data->{'Value'} eq 'ein') ? "on" : "off";

        $device = getDevice($hash, $room, $data->{'Device'});
        $deviceName = $device->{NAME};
        Log3($hash->{NAME}, 5, "Devicename: " . $deviceName);

        fhem("set $deviceName $value");
    }
}


# Raum aus gesprochenem Text oder aus siteId verwenden? (siteId "default" durch Attr defaultRoom ersetzen)
sub roomName ($$) {
  my ($hash, $data) = @_;

  my $room;
  my $defaultRoom = AttrVal($hash->{NAME},"defaultRoom","default");

  if (exists($data->{'Room'})) {
      $room = $data->{'Room'};
  } else {
      $room = $data->{'siteId'};
      $room = $defaultRoom if ($room eq 'default' || !(length $room));
  }

  return $room;
}


# Gerät über Raum und Namen suchen
sub getDevice($$$) {
    my ($hash, $room, $name) = @_;
    my $device;
    my $devspec = "room=Snips";
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return undef if (@devices == 1 && $devices[0] eq $devspec);

    foreach (@devices) {
        my $currentName = AttrVal($_,"snipsName",undef);
        my $currentRoom = AttrVal($_,"snipsRoom",undef);

        if ((lc($currentName) eq lc($name)) && (lc($currentRoom) eq lc($room))) {
           $device = $defs{$_};
        }
    }
    return $device;
}

1;
