
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

    # Attribute snipsName und snipsRoom für andere Devices zur Verfügung abbestellen
    addToAttrList("snipsName");
    addToAttrList("snipsRoom");
    addToAttrList("snipsMapping");

    # Consumer
    $hash->{DefFn} = "SNIPS::Define";
    $hash->{UndefFn} = "SNIPS::Undefine";
    $hash->{SetFn} = "SNIPS::Set";
    $hash->{AttrFn} = "SNIPS::Attr";
    $hash->{AttrList} = "IODev defaultRoom " . $main::readingFnAttributes;
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
    return "Invalid number of arguments: define <name> SNIPS IODev Prefix" if (int(@args) < 4);

    my ($name, $type, $IODev, $prefix) = @args;
    $hash->{MODULE_VERSION} = "0.1";
    $hash->{helper}{prefix} = $prefix;

    # IODev setzen und als MQTT Client registrieren
    $main::attr{$name}{IODev} = $IODev;
    MQTT::Client_Define($hash, $def);

    # Benötigte MQTT Topics abonnieren
    subscribeTopics($hash);

    return undef;
};


# Device löschen
sub Undefine($$) {
    my ($hash, $name) = @_;

    # MQTT Abonnements löschen
    unsubscribeTopics($hash);

    # Weitere Schritte an das MQTT Modul übergeben, damit man dort als Client ausgetragen wird
    return MQTT::Client_Undefine($hash);
}


# Set Befehl aufgerufen
sub Set($$$@) {
    my ($hash, $name, $command, @values) = @_;
    return "Unknown argument $command, choose one of " . join(" ", sort keys %sets) if(!defined($sets{$command}));

    Log3($hash->{NAME}, 5, "set " . $command . " - value: " . join (" ", @values));

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

# Attribute setzen / löschen
sub Attr($$$$) {
    my ($command, $name, $attribute, $value) = @_;
    my $hash = $defs{$name};

    # IODev Attribut gesetzt
    if ($attribute eq "IODev") {

        return undef;
    }

    return undef;
}


# Topics abonnieren
sub subscribeTopics($) {
    my ($hash) = @_;

    foreach (@topics) {
        my ($mqos, $mretain, $mtopic, $mvalue, $mcmd) = MQTT::parsePublishCmdStr($_);
        MQTT::client_subscribe_topic($hash,$mtopic,$mqos,$mretain);

        Log3($hash->{NAME}, 5, "Topic subscribed: " . $_);
    }
}

# Topics abbestellen
sub unsubscribeTopics($) {
    my ($hash) = @_;

    foreach (@topics) {
        my ($mqos, $mretain, $mtopic, $mvalue, $mcmd) = MQTT::parsePublishCmdStr($_);
        MQTT::client_unsubscribe_topic($hash,$mtopic);

        Log3($hash->{NAME}, 5, "Topic unsubscribed: " . $_);
    }
}


# Empfangene Daten vom MQTT Modul
sub onmessage($$$) {
    my ($hash, $topic, $message) = @_;
    my $prefix = $hash->{helper}{prefix};

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
        Log3($hash->{NAME}, 5, "Intent: $intent");

        # JSON parsen
        my $data = SNIPS::parseJSON($hash, $intent, $message);

        if ($intent eq 'On') {
            SNIPS::handleIntentOn($hash, $data);
        } elsif ($intent eq 'Percent') {
            SNIPS::handleIntentPercent($hash, $data);
        }
    }
}


# Raum aus gesprochenem Text oder aus siteId verwenden? (siteId "default" durch Attr defaultRoom ersetzen)
sub roomName ($$) {
  my ($hash, $data) = @_;

  my $room;
  my $defaultRoom = AttrVal($hash->{NAME},"defaultRoom","default");

  # Slot "Room" im JSON vorhanden? Sonst Raum des angesprochenen Satelites verwenden
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
        # 2 Arrays bilden mit Namen und Räumen des Devices
        my @names = ($_, AttrVal($_,"alias",undef), AttrVal($_,"snipsName",undef));
        my @rooms = split(',', AttrVal($_,"room",undef));
        push (@rooms, AttrVal($_,"snipsRoom",undef));

        # Case Insensitive schauen ob der gesuchte Name und Raum in den Arrays vorhanden ist
        if (grep( /^$name$/i, @names) && grep( /^$room$/i, @rooms)) {
           $device = $defs{$_};
        }
    }
    return $device;
}


# JSON parsen
sub parseJSON($$$) {
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


# HashRef zu JSON ecnoden
sub encodeJSON($) {
    my ($hashRef) = @_;
    my $json;

    # JSON Encode und Fehlerüberprüfung
    my $json = eval { encode_json($hashRef) };
    if ($@) {
          return undef;
    }

    return $json;
}


# Eingehende "On" Intents bearbeiten
sub handleIntentOn ($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room;
    my $deviceName;
    my $sendData, my $json;

    if (exists($data->{'Device'}) && exists($data->{'Value'})) {
        $room = roomName($hash, $data);
        $value = ($data->{'Value'} eq 'ein') ? "on" : "off";
        $device = getDevice($hash, $room, $data->{'Device'});
        $deviceName = $device->{NAME} if (defined($device));

        Log3($hash->{NAME}, 5, "On-Intent: " . $room . " " . $deviceName . " " . $value);

        if (defined($device)) {
            # Antwort erstellen und Senden
            $sendData =  {
                sessionId => $data->{sessionId},
                text => "ok"
            };

            $json = SNIPS::encodeJSON($sendData);
            MQTT::send_publish($hash->{IODev}, topic => 'hermes/dialogueManager/endSession', message => $json, qos => 0, retain => "0");
            fhem("set $deviceName $value");

            Log3($hash->{NAME}, 5, "SendData: " . $json);
        }
    }
}

# Eingehende "Percent" Intents bearbeiten
sub handleIntentPercent ($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $change;
    my $deviceName;
    my $sendData, my $json;
    my $validData = 0;

    Log3($hash->{NAME}, 5, "Device: " . $data->{'Device'} . " Value: " . $data->{'Value'});

    # Mindestens Device und Value angegeben -> Valid (z.B. Deckenlampe auf 20%)
    $validData = 1 if (exists($data->{'Device'}) && exists($data->{'Value'}));
    # Mindestens Device und Change angegeben -> Valid (z.B. Radio lauter)
    $validData = 1 if (exists($data->{'Device'}) && exists($data->{'Change'}));

    if ($validData == 1) {

        $room = roomName($hash, $data);
        $value = $data->{'Value'};
        $value = $data->{'Change'};
        $device = getDevice($hash, $room, $data->{'Device'});

        Log3($hash->{NAME}, 5, "Precent-Intent: " . $room . " " . $device . " " . $value . " " . $change);
    }
}

1;
