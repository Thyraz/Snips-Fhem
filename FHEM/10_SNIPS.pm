##############################################
#
# FHEM snips.ai modul  http://snips.ai)
#
# written 2018 by Tobias Wiedenmann (Thyraz)
# thanks to Matthias Kleine
#
##############################################

use strict;
use warnings;


my %gets = (
    "version" => "",
    "status" => ""
);

my %sets = (
    "say" => "",
    "play" => "",
    "updateModel" => "",
    "textCommand" => ""
);

# MQTT Topics die das Modul automatisch abonniert
my @topics = qw(
    hermes/intent/+
    hermes/nlu/intentParsed
    hermes/hotword/+/detected
    hermes/hotword/toggleOn
);


sub SNIPS_Initialize($) {
    my $hash = shift @_;

    # Attribute snipsName und snipsRoom für andere Devices zur Verfügung abbestellen
    addToAttrList("snipsName");
    addToAttrList("snipsRoom");
    addToAttrList("snipsMapping:textField-long");

    # Consumer
    $hash->{DefFn} = "SNIPS::Define";
    $hash->{UndefFn} = "SNIPS::Undefine";
    $hash->{SetFn} = "SNIPS::Set";
    $hash->{AttrFn} = "SNIPS::Attr";
    $hash->{AttrList} = "IODev defaultRoom snipsIntents:textField-long " . $main::readingFnAttributes;
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
use Encode;
#use Data::Dumper 'Dumper';

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
        round
        toJSON
        AnalyzeCommand
        AnalyzePerlCommand
        parseParams
        looks_like_number
    ))
};


# Device anlegen
sub Define() {
    my ($hash, $def) = @_;
    my @args = split("[ \t]+", $def);

    # Minimale Anzahl der nötigen Argumente vorhanden?
    return "Invalid number of arguments: define <name> SNIPS IODev DefaultRoom" if (int(@args) < 4);

    my ($name, $type, $IODev, $defaultRoom) = @args;
    $hash->{MODULE_VERSION} = "0.2";
    $hash->{helper}{defaultRoom} = $defaultRoom;

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

    # Say Cmd
    if ($command eq "say") {
        my $text = join (" ", @values);
        SNIPS::say($hash, $text);
    }
    # TextCommand Cmd
    elsif ($command eq "textCommand") {
        my $text = join (" ", @values);
        SNIPS::textCommand($hash, $text);
    }
    # Update Model Cmd
    elsif ($command eq "updateModel") {
        SNIPS::updateModel($hash);
    }
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


# Alle Gerätenamen sammeln
sub allSnipsNames() {
    my @devices, my @sorted;
    my %devicesHash;
    my $devspec = "room=Snips";
    my @devs = devspec2array($devspec);

    # Alle SnipsNames sammeln
    foreach (@devs) {
        push @devices, split(',', AttrVal($_,"snipsName",undef));
    }

    # Doubletten rausfiltern
    %devicesHash = map { if (defined($_)) { $_, 1 } else { () } } @devices;
    @devices = keys %devicesHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'lampe' gefunden wird bevor der eigentliche Treffer 'deckenlampe' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @devices;

    return @sorted
}


# Alle Raumbezeichnungen sammeln
sub allSnipsRooms() {
    my @rooms, my @sorted;
    my %roomsHash;
    my $devspec = "room=Snips";
    my @devs = devspec2array($devspec);

    # Alle SnipsNames sammeln
    foreach (@devs) {
        push @rooms, split(',', AttrVal($_,"snipsRoom",undef));
    }

    # Doubletten rausfiltern
    %roomsHash = map { if (defined($_)) { $_, 1 } else { () } } @rooms;
    @rooms = keys %roomsHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'küche' gefunden wird bevor der eigentliche Treffer 'waschküche' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @rooms;

    return @sorted
}


# Raum aus gesprochenem Text oder aus siteId verwenden? (siteId "default" durch Attr defaultRoom ersetzen)
sub roomName ($$) {
    my ($hash, $data) = @_;

    my $room;
    my $defaultRoom = $hash->{helper}{defaultRoom};

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
sub getDeviceByName($$$) {
    my ($hash, $room, $name) = @_;
    my $device;
    my $devspec = "room=Snips";
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return undef if (@devices == 1 && $devices[0] eq $devspec);

    foreach (@devices) {
        # 2 Arrays bilden mit Namen und Räumen des Devices
        my @names = split(',', AttrVal($_,"snipsName",undef));
        my @rooms = split(',', AttrVal($_,"snipsRoom",undef));

        # Case Insensitive schauen ob der gesuchte Name (oder besser Name und Raum) in den Arrays vorhanden ist
        if (grep( /^$name$/i, @names)) {
            if (!defined($device) || grep( /^$room$/i, @rooms)) {
                $device = $_;
            }
        }
    }
    return $device;
}


# Gerät über Raum, Intent und Type suchen
sub getDeviceByType($$$$) {
    my ($hash, $room, $intent, $type) = @_;
    my $device;
    my $devspec = "room=Snips";
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return undef if (@devices == 1 && $devices[0] eq $devspec);

    foreach (@devices) {
        # Array bilden mit Räumen des Devices
        my @rooms = split(',', AttrVal($_,"snipsRoom",undef));
        my $mapping = SNIPS::getMapping($hash, $_, $intent, $type, 1);
        my $mappingType = $mapping->{'type'};

        # Schauen ob der Type aus dem Mapping der gesuchte ist und der Raum stimmt
        if (defined($mappingType) && $mappingType eq $type) {
            if (grep( /^$room$/i, @rooms)) {
                Log3($hash->{NAME}, 5, "Device mit passendem mappingType: $_");
                $device = $_;
            }
        }
    }
    return $device;
}


# snipsMapping parsen und gefundene Settings zurückliefern
sub getMapping($$$$;$) {
    my ($hash, $device, $intent, $type, $disableLog) = @_;
    my @mappings, my $mapping;
    my $mappingsString = AttrVal($device,"snipsMapping",undef);

    # String in einzelne Mappings teilen
    @mappings = split(/\n/, $mappingsString);

    foreach (@mappings) {
        # Nur Mappings vom gesuchten Typ verwenden
        next unless $_ =~ qr/^$intent/;

        $_ =~ s/$intent://;
        my %options = split(/(?<!\\),|=/, $_);

        if (!defined($mapping) || (defined($type) && $mapping->{'type'} ne $type && $options{'type'} eq $type)) {
            $mapping = \%options;

            Log3($hash->{NAME}, 5, "snipsMapping selected: $_") if (!defined($disableLog) || (defined($disableLog) && $disableLog != 1));
        }
    }

    return $mapping;
}


# JSON parsen
sub parseJSON($$) {
    my ($hash, $json) = @_;
    my $data;

    # JSON Decode und Fehlerüberprüfung
    my $decoded = eval { decode_json(encode_utf8($json)) };
    if ($@) {
          return undef;
    }

    # Standard-Keys auslesen
    ($data->{'intent'} = $decoded->{'intent'}{'intentName'}) =~ s/^.*.://;;
    $data->{'probability'} = $decoded->{'intent'}{'probability'};
    $data->{'sessionId'} = $decoded->{'sessionId'};
    $data->{'siteId'} = $decoded->{'siteId'};
    $data->{'input'} = $decoded->{'input'};

    # Überprüfen ob Slot Array existiert
    if (exists($decoded->{'slots'})) {
        my @slots = @{$decoded->{'slots'}};

        # Key -> Value Paare aus dem Slot Array ziehen
        foreach my $slot (@slots) {
            my $slotName = $slot->{'slotName'};
            my $slotValue = $slot->{'value'}{'value'};

            $data->{$slotName} = $slotValue;
        }
    }

    # Falls Info Dict angehängt ist, handelt es sich um einen mit Standardwerten über NLU umgeleiteten Request. -> Originalwerte wiederherstellen
    if (exists($decoded->{'id'})) {
        my $info = decode_json(encode_utf8($decoded->{'id'}));

        $data->{'input'} = $info->{'input'} if defined($info->{'input'});
        $data->{'sessionId'} = $info->{'sessionId'} if defined($info->{'sessionId'});
        $data->{'siteId'} = $info->{'siteId'} if defined($info->{'siteId'});
        $data->{'Device'} = $info->{'Device'} if defined($info->{'Device'});
        $data->{'Room'} = $info->{'Room'} if defined($info->{'Room'});
    }

    foreach (keys %{ $data }) {
        my $value = $data->{$_};
        Log3($hash->{NAME}, 5, "Parsed value: $value for key: $_");
    }

    return $data;
}


# Daten vom MQTT Modul empfangen -> Device und Room ersetzen, dann erneut an NLU übergeben
sub onmessage($$$) {
    my ($hash, $topic, $message) = @_;

    # Hotword Erkennung
    if ($topic =~ m/^hermes\/hotword/) {
        my $data = SNIPS::parseJSON($hash, $message);
        my $room = roomName($hash, $data);

        if (defined($room)) {
            my %umlauts = ("ä" => "ae", "Ä" => "Ae", "ü" => "ue", "Ü" => "Ue", "ö" => "oe", "Ö" => "Oe", "ß" => "ss" );
            my $keys = join ("|", keys(%umlauts));

            $room =~ s/($keys)/$umlauts{$1}/g;

            if ($topic =~ m/detected/) {
                readingsSingleUpdate($hash, "listening_" . lc($room), 1, 1);
            } elsif ($topic =~ m/toggleOn/) {
                readingsSingleUpdate($hash, "listening_" . lc($room), 0, 1);
            }
        }
    }

    # Sprachintent von Snips empfangen -> Geräte- und Raumnamen ersetzen und Request erneut an NLU senden
    elsif ($topic =~ qr/^hermes\/intent\/.*:/) {
        my $info, my $sendData;
        my $device, my $room;
        my @devices = allSnipsNames();
        my @rooms = allSnipsRooms();
        my $json, my $infoJson;
        my $sessionId;

        my $data = SNIPS::parseJSON($hash, $message);
        my $command = $data->{'input'};

        # Geräte- und Raumbezeichnungen im Kommando gegen die Defaultbezeichnung aus dem Snips-Slot tauschen, damit NLU uns versteht
        foreach (@devices) {
            if ($command =~ qr/$_/i) {
                $device = lc($_);
                $command =~ s/$_/'standardgerät'/i;
                last;
            }
        }
        foreach (@rooms) {
            if ($command =~ qr/$_/i) {
                $room = lc($_);
                $command =~ s/$_/'standardraum'/i;
                last;
            }
        }

        # Info Hash wird mit an NLU übergeben um die Rückmeldung später dem Request zuordnen zu können
        $info = {
            input       => $data->{'input'},
            sessionId   => $data->{'sessionId'},
            siteId      => $data->{'siteId'},
            Device      => $device,
            Room        => $room
        };
        $infoJson = toJSON($info);

        # Message an NLU Senden
        $sessionId = ($topic eq "hermes/intent/FHEM:TextCommand") ? "fhem.textCommand" :"fhem.voiceCommand";
        $sendData =  {
            sessionId => $sessionId,
            input => $command,
            id => $infoJson
        };

        $json = toJSON($sendData);
        MQTT::send_publish($hash->{IODev}, topic => 'hermes/nlu/query', message => $json, qos => 0, retain => "0");

        Log3($hash->{NAME}, 5, "sending message to NLU: " . $json);
    }

    # Intent von NLU empfangen
    elsif ($topic eq "hermes/nlu/intentParsed" && ($message =~ m/fhem.voiceCommand/ || $message =~ m/fhem.textCommand/)) {
        my $intent;
        my $type;
        my $data;

        # JSON parsen
        $type = ($message =~ m/fhem.voiceCommand/) ? "voice" : "text";
        $data = SNIPS::parseJSON($hash, $message);
        $data->{'type'} = $type;

        $intent = $data->{'intent'};

        # Readings updaten
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "lastIntentTopic", $topic);
        readingsBulkUpdate($hash, "lastIntentPayload", toJSON($data));
        readingsEndUpdate($hash, 1);

        # Passenden Intent-Handler aufrufen
        if ($intent eq 'SetOnOff') {
            SNIPS::handleIntentSetOnOff($hash, $data);
        } elsif ($intent eq 'GetOnOff') {
            SNIPS::handleIntentGetOnOff($hash, $data);
        } elsif ($intent eq 'SetNumeric') {
            SNIPS::handleIntentSetNumeric($hash, $data);
        } elsif ($intent eq 'GetNumeric') {
            SNIPS::handleIntentGetNumeric($hash, $data);
        } elsif ($intent eq 'Status') {
            SNIPS::handleIntentStatus($hash, $data);
        } else {
            SNIPS::handleCustomIntent($hash, $intent, $data);
        }
    }
}


# Antwort ausgeben
sub respond($$$$) {
    my ($hash, $type, $sessionId, $response) = @_;
    my $json;

    if ($type eq "voice") {
        my $sendData =  {
            sessionId => $sessionId,
            text => $response
        };

        $json = toJSON($sendData);
        MQTT::send_publish($hash->{IODev}, topic => 'hermes/dialogueManager/endSession', message => $json, qos => 0, retain => "0");
        readingsSingleUpdate($hash, "voiceResponse", $response, 1);
    }
    elsif ($type eq "text") {
        readingsSingleUpdate($hash, "textResponse", $response, 1);
    }
}


# Text Kommando an SNIPS
sub textCommand($$) {
    my ($hash, $text) = @_;

    my $data = { input => $text };
    my $message = toJSON($data);

    # Send fake command, so it's forwarded to NLU
    my $topic = "hermes/intent/FHEM:TextCommand";
    onmessage($hash, $topic, $message);
}


# Sprachausgabe / TTS über SNIPS
sub say($$) {
    my ($hash, $text) = @_;
    my $sendData, my $json;

    $sendData =  {
        siteId => "default",
        text => $text,
        lang => "de",
        id => "0",
        sessionId => "0"
    };

    $json = toJSON($sendData);
    MQTT::send_publish($hash->{IODev}, topic => 'hermes/tts/say', message => $json, qos => 0, retain => "0");
}


# Update vom Sips Model / ASR Injection
sub updateModel($) {
    my ($hash) = @_;
    my @devices = allSnipsNames();
    my @rooms = allSnipsRooms();

    # JSON Struktur erstellen
    if (@devices > 0 || @rooms > 0) {
      my $json;
      my $injectData, my $deviceData, my $roomData;
      my @operations, my @deviceOperation, my @roomOperation;

      $deviceData->{'de.fhem.Device'} = \@devices;
      @deviceOperation = ('add', $deviceData);

      $roomData->{'de.fhem.Room'} = \@rooms;
      @roomOperation = ('add', $roomData);

      push(@operations, \@deviceOperation) if @devices > 0;
      push(@operations, \@roomOperation) if @rooms > 0;

      $injectData->{'operations'} = \@operations;
      $json = eval { toJSON($injectData) };

      Log3($hash->{NAME}, 5, "Injecting data to ASR: $json");

      # ASR Inject über MQTT senden
      MQTT::send_publish($hash->{IODev}, topic => 'hermes/asr/inject', message => $json, qos => 0, retain => "0");
    }
}


# Eingehender Custom-Intent
sub handleCustomIntent($$$) {
    my ($hash, $intentName, $data) = @_;
    my @intents, my $intent;
    my $intentsString = AttrVal($hash->{NAME},"snipsIntents",undef);
    my $sendData, my $json;
    my $response;
    my $error;

    Log3($hash->{NAME}, 5, "handleCustomIntent called");

    # Suchen ob ein passender Custom Intent existiert
    @intents = split(/\n/, $intentsString);
    foreach (@intents) {
        next unless $_ =~ qr/^$intentName/;

        $intent = $_;
        Log3($hash->{NAME}, 5, "snipsIntent selected: $_");
    }

    # Custom Intent Definition Parsen
    if ($intent =~ qr/^$intentName=.*\(.*\)/) {
        my @tokens = split(/=|\(|\)/, $intent);
        my $subName =  "main::" . $tokens[1] if (@tokens > 0);
        my @paramNames = split(/,/, $tokens[2]) if (@tokens > 1);

        if (defined($subName)) {
            my @params = map { $data->{$_} } @paramNames;

            # Sub aus dem Custom Intent aufrufen
            eval {
                Log3($hash->{NAME}, 5, "Calling sub: $subName");

                no strict 'refs';
                $response = $subName->(@params);
            };

            if ($@) {
                Log3($hash->{NAME}, 5, $@);
            }
        }
    }
    $response = "Da ist etwas schief gegangen." if (!defined($response));

    # Antwort senden
    respond ($hash, $data->{'type'}, $data->{sessionId}, $response);
}


# Eingehende "SetOnOff" Intents bearbeiten
sub handleIntentSetOnOff($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room;
    my $mapping;
    my $sendData, my $json;
    my $response = "Da ist etwas schief gegangen.";

    Log3($hash->{NAME}, 5, "handleIntentSetOnOff called");

    # Mindestens Gerät und Wert müssen übergeben worden sein
    if (exists($data->{'Device'}) && exists($data->{'Value'})) {
        $room = roomName($hash, $data);
        $value = $data->{'Value'};
        $device = getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = getMapping($hash, $device, "SetOnOff", undef);

        # Mapping gefunden?
        if (defined($device) && defined($mapping)) {
            my $error;
            my $cmdOn  = (defined($mapping->{'cmdOn'}))  ? $mapping->{'cmdOn'}  :  "on";
            my $cmdOff = (defined($mapping->{'cmdOff'})) ? $mapping->{'cmdOff'} : "off";
            $value = ($value eq 'an') ? $cmdOn : $cmdOff;

            $response = "Ok";
            # Gerät schalten
            $error = AnalyzeCommand($hash, "set $device $value");
            Log3($hash->{NAME}, 1, $error) if (defined($error));
        }
    }
    # Antwort senden
    respond ($hash, $data->{'type'}, $data->{sessionId}, $response);
}


# Eingehende "GetOnOff" Intents bearbeiten
sub handleIntentGetOnOff($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $status;
    my $mapping;
    my $sendData, my $json;
    my $response = "Da ist etwas schief gegangen.";

    Log3($hash->{NAME}, 5, "handleIntentGetOnOff called");

    # Mindestens Gerät und Status-Art wurden übergeben
    if (exists($data->{'Device'}) && exists($data->{'Status'})) {
        $room = roomName($hash, $data);
        $device = getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = getMapping($hash, $device, "GetOnOff", undef);
        $status = $data->{'Status'};

        # Mapping gefunden?
        if (defined($mapping)) {
            my $reading = $mapping->{'currentVal'};
            my $valueOn   = (defined($mapping->{'valueOn'}))  ? $mapping->{'valueOn'}  : undef;
            my $valueOff  = (defined($mapping->{'valueOff'})) ? $mapping->{'valueOff'} : undef;
            my $value = ReadingsVal($device, $reading, undef);

            # Entscheiden ob $value 0 oder 1 ist
            if (defined($valueOff)) {
                $value = (lc($value) eq lc($valueOff)) ? 0 : 1;
            } elsif (defined($valueOn)) {
                $value = (lc($value) eq lc($valueOn)) ? 1 : 0;
            } else {
                # valueOn und valueOff sind nicht angegeben worden, alles außer "off" wird als eine 1 gewertet
                $value = (lc($value) eq "off") ? 0 : 1;
            }

            # Antwort erstellen
            if    ($status =~ m/^(an|aus)$/ && $value == 1) { $response = $data->{'Device'} . " ist eingeschaltet"; }
            elsif ($status =~ m/^(an|aus)$/ && $value == 0) { $response = $data->{'Device'} . " ist ausgeschaltet"; }
            elsif ($status =~ m/^(auf|zu)$/ && $value == 1) { $response = $data->{'Device'} . " ist geöffnet"; }
            elsif ($status =~ m/^(auf|zu)$/ && $value == 0) { $response = $data->{'Device'} . " ist geschlossen"; }
            elsif ($status =~ m/^(läuft|fertig)$/ && $value == 1) { $response = $data->{'Device'} . " läuft noch"; }
            elsif ($status =~ m/^(läuft|fertig)$/ && $value == 0) { $response = $data->{'Device'} . " ist fertig"; }
        }
    }
    # Antwort senden
    respond ($hash, $data->{'type'}, $data->{sessionId}, $response);
}


# Eingehende "SetNumeric" Intents bearbeiten
sub handleIntentSetNumeric($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $change, my $type, my $unit;
    my $mapping;
    my $sendData, my $json;
    my $validData = 0;
    my $response = "Da ist etwas schief gegangen.";

    Log3($hash->{NAME}, 5, "handleIntentSetNumeric called");

    # Mindestens Device und Value angegeben -> Valid (z.B. Deckenlampe auf 20%)
    $validData = 1 if (exists($data->{'Device'}) && exists($data->{'Value'}));
    # Mindestens Device und Change angegeben -> Valid (z.B. Radio lauter)
    $validData = 1 if (exists($data->{'Device'}) && exists($data->{'Change'}));
    # Nur Change für Lautstärke angegeben -> Valid (z.B. lauter)
    $validData = 1 if (!exists($data->{'Device'}) && $data->{'Change'} =~ m/^(lauter|leiser)$/i);
    # Nur Type = Lautstärke und Value angegeben -> Valid (z.B. Lautstärke auf 10)
    $validData = 1 if (!exists($data->{'Device'}) && $data->{'Type'} =~ m/^Lautstärke$/i && exists($data->{'Value'}));

    if ($validData == 1) {
        $unit = $data->{'Unit'};
        $type = $data->{'Type'};
        $value = $data->{'Value'};
        $change = $data->{'Change'};
        $room = roomName($hash, $data);

        # Type nicht belegt -> versuchen Type über change Value zu bestimmen
        if (!defined($type) && defined($change)) {
            if    ($change =~ m/^(kälter|wärmer)$/)  { $type = "Temperatur"; }
            elsif ($change =~ m/^(dunkler|heller)$/) { $type = "Helligkeit"; }
            elsif ($change =~ m/^(lauter|leiser)$/)  { $type = "Lautstärke"; }
        }

        # Gerät über Name oder Type suchen
        if (exists($data->{'Device'})) {
            $device = getDeviceByName($hash, $room, $data->{'Device'});
        } elsif (defined($type)) {
            $device = getDeviceByType($hash, $room, "SetNumeric", $type);
        }

        if (defined($device)) {
            $mapping = getMapping($hash, $device, "SetNumeric", $type);

            # Mapping und Gerät gefunden -> Befehl ausführen
            if (defined($mapping) && defined($mapping->{'cmd'})) {
                my $error;
                my $cmd     = $mapping->{'cmd'};
                my $reading = $mapping->{'currentVal'};
                my $part = $mapping->{'part'};
                my $minVal  = (defined($mapping->{'minVal'})) ? $mapping->{'minVal'} : 0; # Snips kann keine negativen Nummern bisher, daher erzwungener minVal
                my $maxVal  = $mapping->{'maxVal'};
                my $diff    = (defined($value)) ? $value : ((defined($mapping->{'step'})) ? $mapping->{'step'} : 10);
                my $up      = (defined($change) && ($change =~ m/^(rauf|heller|lauter|wärmer)$/)) ? 1 : 0;
                my $forcePercent = (defined($mapping->{'map'}) && lc($mapping->{'map'}) eq "percent") ? 1 : 0;

                # Alten Wert bestimmen
                my $oldVal  = ReadingsVal($device, $reading, 0);
                if (defined($part)) {
                  my @tokens = split(/ /, $oldVal);
                  $oldVal = $tokens[$part] if (@tokens >= $part);
                }

                # Neuen Wert bestimmen
                my $newVal;
                # Direkter Stellwert ("Stelle Lampe auf 50")
                if ($unit ne "Prozent" && defined($value) && !defined($change) && !$forcePercent) {
                    $newVal = $value;
                    # Begrenzung auf evtl. gesetzte min/max Werte
                    $newVal = $minVal if (defined($minVal) && $newVal < $minVal);
                    $newVal = $maxVal if (defined($maxVal) && $newVal > $maxVal);
                    $response = "Ok";
                }
                # Direkter Stellwert als Prozent ("Stelle Lampe auf 50 Prozent", oder "Stelle Lampe auf 50" bei forcePercent)
                elsif (defined($value) && ($unit eq "Prozent" || $forcePercent) && !defined($change) && defined($minVal) && defined($maxVal)) {
                    # Wert von Prozent in Raw-Wert umrechnen
                    $newVal = $value;
                    $newVal =   0 if ($newVal <   0);
                    $newVal = 100 if ($newVal > 100);
                    $newVal = main::round((($newVal * (($maxVal - $minVal) / 100)) + $minVal), 0);
                    $response = "Ok";
                }
                # Stellwert um Wert x ändern ("Mache Lampe um 20 heller" oder "Mache Lampe heller")
                elsif ($unit ne "Prozent" && defined($change) && !$forcePercent) {
                    $newVal = ($up) ? $oldVal + $diff : $oldVal - $diff;
                    $newVal = $minVal if (defined($minVal) && $newVal < $minVal);
                    $newVal = $maxVal if (defined($maxVal) && $newVal > $maxVal);
                    $response = "Ok";
                }
                # Stellwert um Prozent x ändern ("Mache Lampe um 20 Prozent heller" oder "Mache Lampe um 20 heller" bei forcePercent oder "Mache Lampe heller" bei forcePercent)
                elsif (($unit eq "Prozent" || $forcePercent) && defined($change)  && defined($minVal) && defined($maxVal)) {
                    my $diffRaw = main::round((($diff * (($maxVal - $minVal) / 100)) + $minVal), 0);
                    $newVal = ($up) ? $oldVal + $diffRaw : $oldVal - $diffRaw;
                    $newVal = $minVal if ($newVal < $minVal);
                    $newVal = $maxVal if ($newVal > $maxVal);
                    $response = "Ok";
                }

                # Stellwert senden
                $error = AnalyzeCommand($hash, "set $device $cmd $newVal") if defined($newVal);
                Log3($hash->{NAME}, 1, $error) if (defined($error));
            }
        }
    }
    # Antwort senden
    respond ($hash, $data->{'type'}, $data->{sessionId}, $response);
}


# Eingehende "GetNumeric" Intents bearbeiten
sub handleIntentGetNumeric($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $type;
    my $mapping;
    my $sendData, my $json;
    my $response = "Da ist etwas schief gegangen.";

    Log3($hash->{NAME}, 5, "handleIntentGetNumeric called");

    # Mindestens Type muss existieren
    if (exists($data->{'Type'})) {
        $type = $data->{'Type'};
        $room = roomName($hash, $data);

        # Passendes Gerät suchen
        if (exists($data->{'Device'})) {
            $device = getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = getDeviceByType($hash, $room, "GetNumeric", $type);
        }

        $mapping = getMapping($hash, $device, "GetNumeric", $type) if (defined($device));

        # Mapping gefunden
        if (defined($mapping)) {
            my $reading = $mapping->{'currentVal'};
            my $part = $mapping->{'part'};
            my $minVal  = $mapping->{'minVal'};
            my $maxVal  = $mapping->{'maxVal'};
            my $mappingType = $mapping->{'type'};
            my $forcePercent = (defined($mapping->{'map'}) && lc($mapping->{'map'}) eq "percent" && defined($minVal) && defined($maxVal)) ? 1 : 0;

            # Zurückzuliefernden Wert bestimmen
            $value = ReadingsVal($device, $reading, undef);
            if (defined($part)) {
              my @tokens = split(/ /, $value);
              $value = $tokens[$part] if (@tokens >= $part);
            }
            $value =  main::round((($value * (($maxVal - $minVal) / 100)) + $minVal), 0) if ($forcePercent);

            # Punkt durch Komma ersetzen in Dezimalzahlen
            $value =~ s/\./\,/g;

            # Antwort falls mappingType matched
            if    ($mappingType =~ m/^(Helligkeit|Lautstärke|Sollwert)$/) { $response = $data->{'Device'} . " ist auf $value gestellt."; }
            elsif ($mappingType eq "Temperatur") { $response = "Die Temperatur von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value Grad."; }
            elsif ($mappingType eq "Luftfeuchtigkeit") { $response = "Die Luftfeuchtigkeit von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value Prozent."; }
            elsif ($mappingType eq "Batterie") { $response = "Der Batteriestand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . (main::looks_like_number($value) ?  " beträgt $value Prozent" : " ist $value"); }

            # Andernfalls Antwort falls type aus Intent matched
            elsif ($type =~ m/^(Helligkeit|Lautstärke|Sollwert)$/) { $response = $data->{'Device'} . " ist auf $value gestellt."; }
            elsif ($type eq "Temperatur") { $response = "Die Temperatur von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value Grad."; }
            elsif ($type eq "Luftfeuchtigkeit") { $response = "Die Luftfeuchtigkeit von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value Prozent."; }
            elsif ($type eq "Batterie") { $response = "Der Batteriestand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . (main::looks_like_number($value) ?  " beträgt $value Prozent" : " ist $value"); }
        }
    }
    # Antwort senden
    respond ($hash, $data->{'type'}, $data->{sessionId}, $response);
}


# Eingehende "Status" Intents bearbeiten
sub handleIntentStatus($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room;
    my $mapping;
    my $sendData, my $json;
    my $response = "Da ist etwas schief gegangen.";

    Log3($hash->{NAME}, 5, "handleIntentStatus called");

    # Mindestens Device muss existieren
    if (exists($data->{'Device'})) {
        $room = roomName($hash, $data);
        $device = getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = getMapping($hash, $device, "Status", undef);

        # Werte aus Readings nach dem Schema [Device:Reading] im String ersetzen
        $response = ReplaceReadingsVal($hash, $mapping->{'response'});
        # Escapte Kommas wieder durch normale ersetzen
        $response =~ s/\\,/,/;
    }
    # Antwort senden
    respond ($hash, $data->{'type'}, $data->{sessionId}, $response);
}


# Abgespeckte Kopie von ReplaceSetMagic aus fhem.pl
sub	ReplaceReadingsVal($@) {
    my $hash = shift;
    my $a = join(" ", @_);

    sub readingsVal($$$$$) {
        my ($all, $t, $d, $n, $s, $val) = @_;
        my $hash = $defs{$d};
        return $all if(!$hash);

        if(!$t || $t eq "r:") {
            my $r = $hash->{READINGS};
            if($s && ($s eq ":t" || $s eq ":sec")) {
                return $all if (!$r || !$r->{$n});
                $val = $r->{$n}{TIME};
                $val = int(gettimeofday()) - time_str2num($val) if($s eq ":sec");
                return $val;
            }
            $val = $r->{$n}{VAL} if($r && $r->{$n});
        }
        $val = $hash->{$n}   if(!defined($val) && (!$t || $t eq "i:"));
        $val = $main::attr{$d}{$n} if(!defined($val) && (!$t || $t eq "a:") && $main::attr{$d});
        return $all if(!defined($val));

        if($s && $s =~ /:d|:r|:i/ && $val =~ /(-?\d+(\.\d+)?)/) {
            $val = $1;
            $val = int($val) if ( $s eq ":i" );
            $val = round($val, defined($1) ? $1 : 1) if($s =~ /^:r(\d)?/);
        }
        return $val;
    }

    $a =~s/(\[([ari]:)?([a-zA-Z\d._]+):([a-zA-Z\d._\/-]+)(:(t|sec|i|d|r|r\d))?\])/readingsVal($1,$2,$3,$4,$5)/eg;
    return $a;
}

1;
