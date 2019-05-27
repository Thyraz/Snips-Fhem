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
    "textCommand" => "",
    "volume" => ""
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
    $hash->{AttrList} = "IODev defaultRoom snipsIntents:textField-long shortcuts:textField-long response:textField-long " . $main::readingFnAttributes;
    $hash->{OnMessageFn} = "SNIPS::onmessage";

    main::LoadModule("MQTT");
}

# Cmd in main:: ausführen damit User den Prefix nicht vor alle Perl-Aufrufe schreiben muss
sub SNIPS_execute($$$$$) {
    my ($hash, $device, $cmd, $value, $siteId) = @_;
    my $returnVal;

    # Nutervariablen setzen
    my $DEVICE = $device;
    my $VALUE = $value;
    my $ROOM = (defined($siteId) && $siteId eq "default") ? $hash->{helper}{defaultRoom} : $siteId;

    # CMD ausführen
    $returnVal = eval $cmd;
    Log3($hash->{NAME}, 1, $@) if ($@);

    return $returnVal;
}


package SNIPS;

use strict;
use warnings;
use POSIX;
use GPUtils qw(:all);
use JSON;
use Net::MQTT::Constants;
use Encode;
# use Data::Dumper 'Dumper';

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
        AnalyzeCommandChain
        AnalyzePerlCommand
        parseParams
        looks_like_number
        EvalSpecials
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
    # Volume Cmd
    elsif ($command eq "volume") {
        my $params = join (" ", @values);
        SNIPS::setVolume($hash, $params);
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


# Alle Sender sammeln
sub allSnipsChannels() {
    my @channels, my @sorted;
    my %channelsHash;
    my $devspec = "room=Snips";
    my @devs = devspec2array($devspec);

    # Alle SnipsNames sammeln
    foreach (@devs) {
        my @rows = split(/\n/, AttrVal($_,"snipsChannels",undef));
        foreach (@rows) {
            my @tokens = split('=', $_);
            my $channel = shift(@tokens);
            push @channels, $channel;
        }
    }

    # Doubletten rausfiltern
    %channelsHash = map { if (defined($_)) { $_, 1 } else { () } } @channels;
    @channels = keys %channelsHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'S.W.R.' gefunden wird bevor der eigentliche Treffer 'S.W.R.3' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @channels;

    return @sorted
}


# Alle NumericTypes sammeln
sub allSnipsTypes() {
    my @types, my @sorted;
    my %typesHash;
    my $devspec = "room=Snips";
    my @devs = devspec2array($devspec);

    # Alle SnipsNames sammeln
    foreach (@devs) {
        my @mappings = split(/\n/, AttrVal($_,"snipsMapping",undef));
        foreach (@mappings) {
            # Nur GetNumeric und SetNumeric verwenden
            next unless $_ =~ m/^(SetNumeric|GetNumeric)/;
            $_ =~ s/(SetNumeric|GetNumeric)://;
            my %mapping = splitMappingString($_);

            push @types, $mapping{'type'} if (defined($mapping{'type'}));
        }
    }

    # Doubletten rausfiltern
    %typesHash = map { if (defined($_)) { $_, 1 } else { () } } @types;
    @types = keys %typesHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'S.W.R.' gefunden wird bevor der eigentliche Treffer 'S.W.R.3' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @types;

    return @sorted
}


# Alle Farben sammeln
sub allSnipsColors() {
    my @colors, my @sorted;
    my %colorHash;
    my $devspec = "room=Snips";
    my @devs = devspec2array($devspec);

    # Alle SnipsNames sammeln
    foreach (@devs) {
        my @rows = split(/\n/, AttrVal($_,"snipsColors",undef));
        foreach (@rows) {
            my @tokens = split('=', $_);
            my $color = shift(@tokens);
            push @colors, $color;
        }
    }

    # Doubletten rausfiltern
    %colorHash = map { if (defined($_)) { $_, 1 } else { () } } @colors;
    @colors = keys %colorHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'S.W.R.' gefunden wird bevor der eigentliche Treffer 'S.W.R.3' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @colors;

    return @sorted
}


# Alle Shortcuts sammeln
sub allSnipsShortcuts($) {
    my ($hash) = @_;
    my @shortcuts, my @sorted;

    my @rows = split(/\n/, AttrVal($hash->{NAME},"shortcuts",undef));
    foreach (@rows) {
        my @tokens = split('=', $_);
        my $shortcut = shift(@tokens);
        push @shortcuts, $shortcut;
    }

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'S.W.R.' gefunden wird bevor der eigentliche Treffer 'S.W.R.3' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @shortcuts;

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


# Gerät über Raum und Namen suchen.
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

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Sammelt Geräte über Raum, Intent und optional Type
sub getDevicesByIntentAndType($$$$) {
    my ($hash, $room, $intent, $type) = @_;
    my @matchesInRoom, my @matchesOutsideRoom;
    my $devspec = "room=Snips";
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return undef if (@devices == 1 && $devices[0] eq $devspec);

    foreach (@devices) {
        # Array bilden mit Räumen des Devices
        my @rooms = split(',', AttrVal($_,"snipsRoom",undef));
        # Mapping mit passendem Intent vorhanden?
        my $mapping = SNIPS::getMapping($hash, $_, $intent, $type, 1);
        next unless defined($mapping);

        my $mappingType = $mapping->{'type'} if (defined($mapping->{'type'}));

        # Geräte sammeln
        if (!defined($type) && !(grep(/^$room$/i, @rooms))) {
            push @matchesOutsideRoom, $_;
        }
        elsif (!defined($type) && grep(/^$room$/i, @rooms)) {
            push @matchesInRoom, $_;
        }
        elsif (defined($type) && $type =~ m/^$mappingType$/i && !(grep(/^$room$/i, @rooms))) {
            push @matchesOutsideRoom, $_;
        }
        elsif (defined($type) && $type =~ m/^$mappingType$/i && grep(/^$room$/i, @rooms)) {
            push @matchesInRoom, $_;
        }
    }

    return (\@matchesInRoom, \@matchesOutsideRoom);
}


# Geräte über Raum, Intent und ggf. Type suchen.
sub getDeviceByIntentAndType($$$$) {
    my ($hash, $room, $intent, $type) = @_;
    my $device;

    # Devices sammeln
    my ($matchesInRoom, $matchesOutsideRoom) = getDevicesByIntentAndType($hash, $room, $intent, $type);

    # Erstes Device im passenden Raum zurückliefern falls vorhanden, sonst erstes Device außerhalb
    $device = (@{$matchesInRoom} > 0) ? shift @{$matchesInRoom} : shift @{$matchesOutsideRoom};

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Eingeschaltetes Gerät mit bestimmten Intent und optional Type suchen
sub getActiveDeviceForIntentAndType($$$$) {
    my ($hash, $room, $intent, $type) = @_;
    my $device;
    my ($matchesInRoom, $matchesOutsideRoom) = getDevicesByIntentAndType($hash, $room, $intent, $type);

    # Anonyme Funktion zum finden des aktiven Geräts
    my $activeDevice = sub ($$) {
        my ($hash, $devices) = @_;
        my $match;

        foreach (@{$devices}) {
            my $mapping = getMapping($hash, $_, "GetOnOff", undef, 1);
            if (defined($mapping)) {
                # Gerät ein- oder ausgeschaltet?
                my $value = getOnOffState($hash, $_, $mapping);
                if ($value == 1) {
                    $match = $_;
                    last;
                }
            }
        }
        return $match;
    };

    # Gerät finden, erst im aktuellen Raum, sonst in den restlichen
    $device = $activeDevice->($hash, $matchesInRoom);
    $device = $activeDevice->($hash, $matchesOutsideRoom) if (!defined($device));

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Gerät mit bestimmtem Sender suchen
sub getDeviceByMediaChannel($$$) {
    my ($hash, $room, $channel) = @_;
    my $device;
    my $devspec = "room=Snips";
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return undef if (@devices == 1 && $devices[0] eq $devspec);

    foreach (@devices) {
        # Array bilden mit Räumen des Devices
        my @rooms = split(',', AttrVal($_,"snipsRoom",undef));
        # Cmd mit passendem Intent vorhanden?
        my $cmd = getCmd($hash, $_, "snipsChannels", $channel, 1);
        next unless defined($cmd);

        # Erster Treffer wälen, überschreiben falls besserer Treffer (Raum matched auch) kommt
        if (!defined($device) || grep(/^$room$/i, @rooms)) {
            $device = $_;
        }
    }

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Mappings in Key/Value Paare aufteilen
sub splitMappingString($) {
    my ($mapping) = @_;
    my @tokens, my $token = '';
    my $char, my $lastChar = '';
    my $bracketLevel = 0;
    my %parsedMapping;

    # String in Kommagetrennte Tokens teilen
    foreach $char (split(//, $mapping)) {
        if ($char eq '{' && $lastChar ne '\\') {
            $bracketLevel += 1;
            $token .= $char;
        }
        elsif ($char eq '}' && $lastChar ne '\\') {
            $bracketLevel -= 1;
            $token .= $char;
        }
        elsif ($char eq ',' && $lastChar ne '\\' && $bracketLevel == 0) {
            push(@tokens, $token);
            $token = '';
        }
        else {
            $token .= $char;
        }

        $lastChar = $char;
    }
    push(@tokens, $token) if (length($token) > 0);

    # Tokens in Keys/Values trennen
    %parsedMapping = map {split /=/, $_, 2} @tokens;

    return %parsedMapping;
}


# snipsMapping parsen und gefundene Settings zurückliefern
sub getMapping($$$$;$) {
    my ($hash, $device, $intent, $type, $disableLog) = @_;
    my @mappings, my $matchedMapping;
    my $mappingsString = AttrVal($device, "snipsMapping", undef);

    if (defined($mappingsString)) {
        # String in einzelne Mappings teilen
        @mappings = split(/\n/, $mappingsString);

        foreach (@mappings) {
            # Nur Mappings vom gesuchten Typ verwenden
            next unless $_ =~ qr/^$intent/;
            $_ =~ s/$intent://;
            my %currentMapping = splitMappingString($_);

            # Erstes Mapping vom passenden Intent wählen (unabhängig vom Type), dann ggf. weitersuchen ob noch ein besserer Treffer mit passendem Type kommt
            if (!defined($matchedMapping) || (defined($type) && lc($matchedMapping->{'type'}) ne lc($type) && lc($currentMapping{'type'}) eq lc($type))) {
                $matchedMapping = \%currentMapping;

                Log3($hash->{NAME}, 5, "snipsMapping selected: $_") if (!defined($disableLog) || (defined($disableLog) && $disableLog != 1));
            }
        }
    }
    return $matchedMapping;
}


# Cmd von Attribut mit dem Format value=cmd pro Zeile lesen
sub getCmd($$$$;$) {
    my ($hash, $device, $reading, $key, $disableLog) = @_;
    my @rows, my $cmd;
    my $attrString = AttrVal($device, $reading, undef);

    # String in einzelne Mappings teilen
    @rows = split(/\n/, $attrString);

    foreach (@rows) {
        # Nur Zeilen mit gesuchten Identifier verwenden
        next unless $_ =~ qr/^$key=/i;
        $_ =~ s/$key=//i;
        $cmd = $_;

        Log3($hash->{NAME}, 5, "cmd selected: $_") if (!defined($disableLog) || (defined($disableLog) && $disableLog != 1));
        last;
    }

    return $cmd;
}


# Cmd String im Format 'cmd', 'device:cmd', 'fhemcmd1; fhemcmd2' oder '{<perlcode}' ausführen
sub runCmd($$$;$$) {
    my ($hash, $device, $cmd, $val, $siteId) = @_;
    my $error;
    my $returnVal;

    # Perl Command
    if ($cmd =~ m/^\s*{.*}\s*$/) {
        # CMD ausführen
        $returnVal = main::SNIPS_execute($hash, $device, $cmd, $val,$siteId);
    }
    # String in Anführungszeichen (mit ReplaceSetMagic)
    elsif ($cmd =~ m/^\s*".*"\s*$/) {
        my $DEVICE = $device;
        my $ROOM = $siteId;
        my $VALUE = $val;

        # Anführungszeichen entfernen
        $cmd =~ s/^\s*"//;
        $cmd =~ s/"\s*$//;

        # Variablen ersetzen?
        eval { $cmd =~ s/(\$\w+)/$1/eeg; };

        # [DEVICE:READING] Einträge erstzen
        $returnVal = ReplaceReadingsVal($hash, $cmd);
        # Escapte Kommas wieder durch normale ersetzen
        $returnVal =~ s/\\,/,/;
    }
    # FHEM Command oder CommandChain
    elsif (defined($main::cmds{ (split " ", $cmd)[0] })) {
        $error = AnalyzeCommandChain($hash, $cmd);
    }
    # Soll Command auf anderes Device umgelenkt werden?
    elsif ($cmd =~ m/:/) {
        $cmd =~ s/:/ /;
        $cmd = $cmd . ' ' . $val if (defined($val));
        $error = AnalyzeCommand($hash, "set $cmd");
    }
    # Nur normales Cmd angegeben
    else {
        $cmd = "$device $cmd";
        $cmd = $cmd . ' ' . $val if (defined($val));
        $error = AnalyzeCommand($hash, "set $cmd");
    }
    Log3($hash->{NAME}, 1, $_) if (defined($error));

    return $returnVal;
}


# Wert über Format 'reading', 'device:reading' oder '{<perlcode}' lesen
sub getValue($$$;$$) {
    my ($hash, $device, $getString, $val, $siteId) = @_;
    my $value;

    # Perl Command? -> Umleiten zu runCmd
    if ($getString =~ m/^\s*{.*}\s*$/) {
        # Wert lesen
        $value = runCmd($hash, $device, $getString, $val, $siteId);
    }
    # String in Anführungszeichen -> Umleiten zu runCmd
    elsif ($getString =~ m/^\s*".*"\s*$/) {
        # Wert lesen
        $value = runCmd($hash, $device, $getString, $val, $siteId);
    }
    # Reading oder Device:Reading
    else {
      # Soll Reading von einem anderen Device gelesen werden?
      my $readingsDev = ($getString =~ m/:/) ? (split(/:/, $getString))[0] : $device;
      my $reading = ($getString =~ m/:/) ? (split(/:/, $getString))[1] : $getString;

      $value = ReadingsVal($readingsDev, $reading, 0);
    }

    return $value;
}


# Zustand eines Gerätes über GetOnOff Mapping abfragen
sub getOnOffState ($$$) {
    my ($hash, $device, $mapping) = @_;
    my $valueOn   = (defined($mapping->{'valueOn'}))  ? $mapping->{'valueOn'}  : undef;
    my $valueOff  = (defined($mapping->{'valueOff'})) ? $mapping->{'valueOff'} : undef;
    my $value = getValue($hash, $device, $mapping->{'currentVal'});

    # Entscheiden ob $value 0 oder 1 ist
    if (defined($valueOff)) {
        $value = (lc($value) eq lc($valueOff)) ? 0 : 1;
    } elsif (defined($valueOn)) {
        $value = (lc($value) eq lc($valueOn)) ? 1 : 0;
    } else {
        # valueOn und valueOff sind nicht angegeben worden, alles außer "off" wird als eine 1 gewertet
        $value = (lc($value) eq "off") ? 0 : 1;
    }

    return $value;
}


# JSON parsen
sub parseJSON($$) {
    my ($hash, $json) = @_;
    my $data;

    # JSON Decode und Fehlerüberprüfung
    my $decoded = eval { decode_json(encode_utf8($json)) };
    if ($@) {
          Log3($hash->{NAME}, 1, "JSON decoding error: " . $@);
          return undef;
    }

    # Standard-Keys auslesen
    ($data->{'intent'} = $decoded->{'intent'}{'intentName'}) =~ s/^.*.://;
    $data->{'probability'} = $decoded->{'intent'}{'confidenceScore'};
    $data->{'sessionId'} = $decoded->{'sessionId'};
    $data->{'siteId'} = $decoded->{'siteId'};
    $data->{'input'} = $decoded->{'input'};

    # Überprüfen ob Slot Array existiert
    if (exists($decoded->{'slots'})) {
        my @slots = @{$decoded->{'slots'}};

        # Key -> Value Paare aus dem Slot Array ziehen
        foreach my $slot (@slots) {
            my $slotName = $slot->{'slotName'};
            my $slotValue;

            $slotValue = $slot->{'value'}{'value'} if (exists($slot->{'value'}{'value'}));
            $slotValue = $slot->{'value'} if (exists($slot->{'entity'}) && $slot->{'entity'} eq "snips/duration");

            $data->{$slotName} = $slotValue;
        }
    }

    # Falls Info Dict angehängt ist, handelt es sich um einen mit Standardwerten über NLU umgeleiteten Request. -> Originalwerte wiederherstellen
    if (exists($decoded->{'id'})) {
        my $info = eval { decode_json(encode_utf8($decoded->{'id'})) };
        if ($@) {
            $info = undef;
        }

        $data->{'input'} = $info->{'input'} if defined($info->{'input'});
        $data->{'sessionId'} = $info->{'sessionId'} if defined($info->{'sessionId'});
        $data->{'siteId'} = $info->{'siteId'} if defined($info->{'siteId'});
        $data->{'Device'} = $info->{'Device'} if defined($info->{'Device'});
        $data->{'Room'} = $info->{'Room'} if defined($info->{'Room'});
        $data->{'Channel'} = $info->{'Channel'} if defined($info->{'Channel'});
        $data->{'Color'} = $info->{'Color'} if defined($info->{'Color'});
        $data->{'Type'} = $info->{'Type'} if defined($info->{'Type'});
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
    my $data = SNIPS::parseJSON($hash, $message);
    my $input = $data->{'input'} if defined($data->{'input'});

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

    # Shortcut empfangen -> Code direkt ausführen
    elsif ($topic =~ qr/^hermes\/intent\/.*:/ && defined($input) && grep( /^$input$/i, allSnipsShortcuts($hash))) {
      my $error;
      my $response = getResponse($hash, "DefaultError");
      my $type      = ($topic eq "hermes/intent/FHEM:TextCommand") ? "text" : "voice";
      my $sessionId = ($topic eq "hermes/intent/FHEM:TextCommand") ? ""     : $data->{'sessionId'};
      my $cmd = getCmd($hash, $hash->{NAME}, "shortcuts", $input);

      if (defined($cmd)) {
          # Cmd ausführen
          my $returnVal = runCmd($hash, undef, $cmd, undef, $data->{'siteId'});

          $response = (defined($returnVal)) ? $returnVal : getResponse($hash, "DefaultConfirmation");
      }

      # Antwort senden
      respond($hash, $type, $sessionId, $response);
    }

    # Sprachintent von Snips empfangen -> Geräte- und Raumnamen ersetzen und Request erneut an NLU senden
    elsif ($topic =~ qr/^hermes\/intent\/.*:/) {
        my $info, my $sendData;
        my $device, my $room, my $channel, my $color, my $type;
        my @devices = allSnipsNames();
        my @rooms = allSnipsRooms();
        my @channels = allSnipsChannels();
        my @colors = allSnipsColors();
        my @types = allSnipsTypes();
        my $json, my $infoJson;
        my $sessionId;
        my $command = $data->{'input'};

        # Geräte- und Raumbezeichnungen im Kommando gegen die Defaultbezeichnung aus dem Snips-Slot tauschen, damit NLU uns versteht
        # Alle Werte in ein Array und der Länge nach sortieren, damit z.B. "Jazz Radio" nicht fehlerhafterweise als "Radio" erkannt wird
        my @keys = (@devices, @rooms, @channels, @colors, @types);
        my @sortedKeys = sort { length($b) <=> length($a) } @keys;

        foreach my $key (@sortedKeys) {
            if ($command =~ qr/$key/i) {
                if (grep( /^$key$/, @devices)) {
                    $device = lc($key);
                    $command =~ s/$key/standardgerät/i;
                }
                elsif ( grep( /^$key$/, @rooms ) ) {
                    $room = lc($key);
                    $command =~ s/$key/standardraum/i;
                }
                elsif ( grep( /^$key$/, @channels ) ) {
                    $channel = lc($key);
                    $command =~ s/$key/standardsender/i;
                }
                elsif ( grep( /^$key$/, @colors ) ) {
                    $color = lc($key);
                    $command =~ s/$key/standardfarbe/i;
                }
                elsif ( grep( /^$key$/, @types ) ) {
                    $type = lc($key);
                    $command =~ s/$key/standardtyp/i;
                }
            }
        }

        # Info Hash wird mit an NLU übergeben um die Rückmeldung später dem Request zuordnen zu können
        $info = {
            input       => $data->{'input'},
            sessionId   => $data->{'sessionId'},
            siteId      => $data->{'siteId'},
            Device      => $device,
            Room        => $room,
            Channel     => $channel,
            Color       => $color,
            Type        => $type
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
        my $type = ($message =~ m/fhem.voiceCommand/) ? "voice" : "text";

        $data->{'requestType'} = $type;
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
        } elsif ($intent eq 'MediaControls') {
            SNIPS::handleIntentMediaControls($hash, $data);
        } elsif ($intent eq 'MediaChannels') {
            SNIPS::handleIntentMediaChannels($hash, $data);
        } elsif ($intent eq 'SetColor') {
              SNIPS::handleIntentSetColor($hash, $data);
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
        Log3($hash->{NAME}, 5, "Response: $response");
        readingsSingleUpdate($hash, "textResponse", $response, 1);
    }
}


# Antworttexte festlegen
sub getResponse($$) {
    my ($hash, $identifier) = @_;
    my $response;

    my %messages = (
        DefaultError => "Da ist etwas schief gegangen.",
        NoActiveMediaDevice => "Kein Wiedergabegerät aktiv.",
        DefaultConfirmation => "Ok."
    );

    $response = getCmd($hash, $hash->{NAME}, "response", $identifier);
    $response = $messages{$identifier} if (!defined($response));

    return $response;
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
    my ($hash, $cmd) = @_;
    my $sendData, my $json;
    my $siteId = "default";
    my $text = $cmd;
    my($unnamedParams, $namedParams) = parseParams($cmd);

    if (defined($namedParams->{'siteId'}) && defined($namedParams->{'text'})) {
        $siteId = $namedParams->{'siteId'};
        $text = $namedParams->{'text'};
    }

    $sendData =  {
        siteId => $siteId,
        text => $text,
        lang => "de",
        id => "0",
        sessionId => "0"
    };

    $json = toJSON($sendData);
    MQTT::send_publish($hash->{IODev}, topic => 'hermes/tts/say', message => $json, qos => 0, retain => "0");
}


# Sprachausgabe / TTS über SNIPS
sub setVolume($$) {
    my ($hash, $params) = @_;
    my $sendData, my $json;
    my $siteId, my $volume;
    my($unnamedParams, $namedParams) = parseParams($params);

    Log3($hash->{NAME}, 5, "Params: $params");

    if (defined($namedParams->{'siteId'}) && defined($namedParams->{'volume'})) {
        $siteId = $namedParams->{'siteId'};
        $volume = $namedParams->{'volume'};

        $sendData =  {
            siteId => $siteId,
            volume => $volume
        };

        $json = toJSON($sendData);
        MQTT::send_publish($hash->{IODev}, topic => 'hermes/sound/setvolume', message => $json, qos => 0, retain => "0");
    }
}


# Update vom Sips Model / ASR Injection
sub updateModel($) {
    my ($hash) = @_;
    my @devices = allSnipsNames();
    my @rooms = allSnipsRooms();
    my @channels = allSnipsChannels();
    my @colors = allSnipsColors();
    my @types = allSnipsTypes();
    my @shortcuts = allSnipsShortcuts($hash);

    # JSON Struktur erstellen
    if (@devices > 0 || @rooms > 0 || @channels > 0 || @types > 0 || @shortcuts > 0) {
      my $json;
      my $injectData, my $deviceData, my $roomData, my $channelData, my $colorData, my $typeData, my $shortcutData;
      my @operations, my @deviceOperation, my @roomOperation, my @channelOperation, my @ccolorOperation, my @typeOperation, my @shortcutOperation;

      $deviceData->{'de.fhem.Device'} = \@devices;
      @deviceOperation = ('add', $deviceData);

      $roomData->{'de.fhem.Room'} = \@rooms;
      @roomOperation = ('add', $roomData);

      $channelData->{'de.fhem.MediaChannels'} = \@channels;
      @channelOperation = ('add', $channelData);

      $colorData->{'de.fhem.Color'} = \@colors;
      @ccolorOperation = ('add', $colorData);

      $typeData->{'de.fhem.NumericType'} = \@types;
      @typeOperation = ('add', $typeData);

      $shortcutData->{'de.fhem.Shortcuts'} = \@shortcuts;
      @shortcutOperation = ('add', $shortcutData);

      push(@operations, \@deviceOperation) if @devices > 0;
      push(@operations, \@roomOperation) if @rooms > 0;
      push(@operations, \@channelOperation) if @channels > 0;
      push(@operations, \@ccolorOperation) if @colors > 0;
      push(@operations, \@typeOperation) if @types > 0;
      push(@operations, \@shortcutOperation) if @shortcuts > 0;

      $injectData->{'operations'} = \@operations;
      $json = eval { toJSON($injectData) };

      Log3($hash->{NAME}, 5, "Injecting data to ASR: $json");

      # ASR Inject über MQTT senden
      MQTT::send_publish($hash->{IODev}, topic => 'hermes/injection/perform', message => $json, qos => 0, retain => "0");
    }
}


# Eingehender Custom-Intent
sub handleCustomIntent($$$) {
    my ($hash, $intentName, $data) = @_;
    my @intents, my $intent;
    my $intentsString = AttrVal($hash->{NAME},"snipsIntents",undef);
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

    # Gerät setzen falls Slot Device vorhanden
    if (exists($data->{'Device'})) {
      my $room = roomName($hash, $data);
      my $device = getDeviceByName($hash, $room, $data->{'Device'});
      $data->{'Device'} = $device;
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
        $response = getResponse($hash, "DefaultError") if (!defined($response));

        # Antwort senden
        respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
    }
}


# Eingehende "SetOnOff" Intents bearbeiten
sub handleIntentSetOnOff($$) {
    my ($hash, $data) = @_;
    my $value, my $numericValue, my $device, my $room;
    my $mapping;
    my $response = getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentSetOnOff called");

    # Mindestens Gerät und Wert müssen übergeben worden sein
    if (exists($data->{'Device'}) && exists($data->{'Value'})) {
        $room = roomName($hash, $data);
        $value = $data->{'Value'};
        $device = getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = getMapping($hash, $device, "SetOnOff", undef);

        # Mapping gefunden?
        if (defined($device) && defined($mapping)) {
            my $cmdOn  = (defined($mapping->{'cmdOn'}))  ? $mapping->{'cmdOn'}  :  "on";
            my $cmdOff = (defined($mapping->{'cmdOff'})) ? $mapping->{'cmdOff'} : "off";
            my $cmd = ($value eq 'an') ? $cmdOn : $cmdOff;

            # Antwort bestimmen
            $numericValue = ($value eq 'an') ? 1 : 0;
            if (defined($mapping->{'response'})) { $response = getValue($hash, $device, $mapping->{'response'}, $numericValue, $room); }
            else { $response = getResponse($hash, "DefaultConfirmation"); }

            # Cmd ausführen
            runCmd($hash, $device, $cmd);
        }
    }
    # Antwort senden
    respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
}


# Eingehende "GetOnOff" Intents bearbeiten
sub handleIntentGetOnOff($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $status;
    my $mapping;
    my $response = getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentGetOnOff called");

    # Mindestens Gerät und Status-Art wurden übergeben
    if (exists($data->{'Device'}) && exists($data->{'Status'})) {
        $room = roomName($hash, $data);
        $device = getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = getMapping($hash, $device, "GetOnOff", undef);
        $status = $data->{'Status'};

        # Mapping gefunden?
        if (defined($mapping)) {
            # Gerät ein- oder ausgeschaltet?
            $value = getOnOffState($hash, $device, $mapping);

            # Antwort bestimmen
            if    (defined($mapping->{'response'})) { $response = getValue($hash, $device, $mapping->{'response'}, $value, $room); }
            elsif ($status =~ m/^(an|aus)$/ && $value == 1) { $response = $data->{'Device'} . " ist eingeschaltet"; }
            elsif ($status =~ m/^(an|aus)$/ && $value == 0) { $response = $data->{'Device'} . " ist ausgeschaltet"; }
            elsif ($status =~ m/^(auf|zu)$/ && $value == 1) { $response = $data->{'Device'} . " ist geöffnet"; }
            elsif ($status =~ m/^(auf|zu)$/ && $value == 0) { $response = $data->{'Device'} . " ist geschlossen"; }
            elsif ($status =~ m/^(eingefahren|ausgefahren)$/ && $value == 1) { $response = $data->{'Device'} . " ist eingefahren"; }
            elsif ($status =~ m/^(eingefahren|ausgefahren)$/ && $value == 0) { $response = $data->{'Device'} . " ist ausgefahren"; }
            elsif ($status =~ m/^(läuft|fertig)$/ && $value == 1) { $response = $data->{'Device'} . " läuft noch"; }
            elsif ($status =~ m/^(läuft|fertig)$/ && $value == 0) { $response = $data->{'Device'} . " ist fertig"; }
        }
    }
    # Antwort senden
    respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
}


# Eingehende "SetNumeric" Intents bearbeiten
sub handleIntentSetNumeric($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $change, my $type, my $unit;
    my $mapping;
    my $validData = 0;
    my $response = getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentSetNumeric called");

    # Mindestens Device und Value angegeben -> Valid (z.B. Deckenlampe auf 20%)
    $validData = 1 if (exists($data->{'Device'}) && exists($data->{'Value'}));
    # Mindestens Device und Change angegeben -> Valid (z.B. Radio lauter)
    $validData = 1 if (exists($data->{'Device'}) && exists($data->{'Change'}));
    # Nur Change für Lautstärke angegeben -> Valid (z.B. lauter)
    $validData = 1 if (!exists($data->{'Device'}) && defined($data->{'Change'}) && $data->{'Change'} =~ m/^(lauter|leiser)$/i);
    # Nur Type = Lautstärke und Value angegeben -> Valid (z.B. Lautstärke auf 10)
    $validData = 1 if (!exists($data->{'Device'}) && defined($data->{'Type'}) && $data->{'Type'} =~ m/^Lautstärke$/i && exists($data->{'Value'}));

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

        # Gerät über Name suchen, oder falls über Lautstärke ohne Device getriggert wurde das ActiveMediaDevice suchen
        if (exists($data->{'Device'})) {
            $device = getDeviceByName($hash, $room, $data->{'Device'});
        } elsif (defined($type) && $type =~ m/^Lautstärke$/i) {
            $device = getActiveDeviceForIntentAndType($hash, $room, "SetNumeric", $type);
            $response = getResponse($hash, "NoActiveMediaDevice") if (!defined($device));
        }

        if (defined($device)) {
            $mapping = getMapping($hash, $device, "SetNumeric", $type);

            # Mapping und Gerät gefunden -> Befehl ausführen
            if (defined($mapping) && defined($mapping->{'cmd'})) {
                my $cmd     = $mapping->{'cmd'};
                my $part    = $mapping->{'part'};
                my $minVal  = (defined($mapping->{'minVal'})) ? $mapping->{'minVal'} : 0; # Snips kann keine negativen Nummern bisher, daher erzwungener minVal
                my $maxVal  = $mapping->{'maxVal'};
                my $diff    = (defined($value)) ? $value : ((defined($mapping->{'step'})) ? $mapping->{'step'} : 10);
                my $up      = (defined($change) && ($change =~ m/^(höher|heller|lauter|wärmer)$/)) ? 1 : 0;
                my $forcePercent = (defined($mapping->{'map'}) && lc($mapping->{'map'}) eq "percent") ? 1 : 0;

                # Alten Wert bestimmen
                my $oldVal  = getValue($hash, $device, $mapping->{'currentVal'});
                if (defined($part)) {
                    my @tokens = split(/ /, $oldVal);
                    $oldVal = $tokens[$part] if (@tokens >= $part);
                }

                # Neuen Wert bestimmen
                my $newVal;
                # Direkter Stellwert ("Stelle Lampe auf 50")
                if ($unit ne "Prozent" && defined($value) && !defined($change) && !$forcePercent) {
                    $newVal = $value;
                }
                # Direkter Stellwert als Prozent ("Stelle Lampe auf 50 Prozent", oder "Stelle Lampe auf 50" bei forcePercent)
                elsif (defined($value) && ((defined($unit) && $unit eq "Prozent") || $forcePercent) && !defined($change) && defined($minVal) && defined($maxVal)) {
                    # Wert von Prozent in Raw-Wert umrechnen
                    $newVal = $value;
                    $newVal =   0 if ($newVal <   0);
                    $newVal = 100 if ($newVal > 100);
                    $newVal = main::round((($newVal * (($maxVal - $minVal) / 100)) + $minVal), 0);
                }
                # Stellwert um Wert x ändern ("Mache Lampe um 20 heller" oder "Mache Lampe heller")
                elsif ((!defined($unit) || $unit ne "Prozent") && defined($change) && !$forcePercent) {
                    $newVal = ($up) ? $oldVal + $diff : $oldVal - $diff;
                }
                # Stellwert um Prozent x ändern ("Mache Lampe um 20 Prozent heller" oder "Mache Lampe um 20 heller" bei forcePercent oder "Mache Lampe heller" bei forcePercent)
                elsif (($unit eq "Prozent" || $forcePercent) && defined($change)  && defined($minVal) && defined($maxVal)) {
                    my $diffRaw = main::round((($diff * (($maxVal - $minVal) / 100)) + $minVal), 0);
                    $newVal = ($up) ? $oldVal + $diffRaw : $oldVal - $diffRaw;
                }

                if (defined($newVal)) {
                    # Begrenzung auf evtl. gesetzte min/max Werte
                    $newVal = $minVal if (defined($minVal) && $newVal < $minVal);
                    $newVal = $maxVal if (defined($maxVal) && $newVal > $maxVal);

                    # Antwort festlegen
                    if (defined($mapping->{'response'})) { $response = getValue($hash, $device, $mapping->{'response'}, $newVal, $room); }
                    else { $response = getResponse($hash, "DefaultConfirmation"); }

                    # Cmd ausführen
                    runCmd($hash, $device, $cmd, $newVal);
                }
            }
        }
    }
    # Antwort senden
    respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
}


# Eingehende "GetNumeric" Intents bearbeiten
sub handleIntentGetNumeric($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $type;
    my $mapping;
    my $response = getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentGetNumeric called");

    # Mindestens Type oder Device muss existieren
    if (exists($data->{'Type'}) || exists($data->{'Device'})) {
        $type = $data->{'Type'};
        $room = roomName($hash, $data);

        # Passendes Gerät suchen
        if (exists($data->{'Device'})) {
            $device = getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = getDeviceByIntentAndType($hash, $room, "GetNumeric", $type);
        }

        $mapping = getMapping($hash, $device, "GetNumeric", $type) if (defined($device));

        # Mapping gefunden
        if (defined($mapping)) {
            my $part = $mapping->{'part'};
            my $minVal  = $mapping->{'minVal'};
            my $maxVal  = $mapping->{'maxVal'};
            my $mappingType = $mapping->{'type'};
            my $forcePercent = (defined($mapping->{'map'}) && lc($mapping->{'map'}) eq "percent" && defined($minVal) && defined($maxVal)) ? 1 : 0;
            my $isNumber;

            # Zurückzuliefernden Wert bestimmen
            $value = getValue($hash, $device, $mapping->{'currentVal'});
            if (defined($part)) {
              my @tokens = split(/ /, $value);
              $value = $tokens[$part] if (@tokens >= $part);
            }
            $value = main::round((($value * (($maxVal - $minVal) / 100)) + $minVal), 0) if ($forcePercent);
            $isNumber = main::looks_like_number($value);

            # Punkt durch Komma ersetzen in Dezimalzahlen
            $value =~ s/\./\,/g;

            # Antwort falls Custom Response definiert ist
            if    (defined($mapping->{'response'})) { $response = getValue($hash, $device, $mapping->{'response'}, $value, $room); }

            # Antwort falls mappingType matched
            elsif ($mappingType =~ m/^(Helligkeit|Lautstärke|Sollwert)$/i) { $response = $data->{'Device'} . " ist auf $value gestellt."; }
            elsif ($mappingType =~ m/^Temperatur$/i) { $response = "Die Temperatur von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value" . ($isNumber ? " Grad" : ""); }
            elsif ($mappingType =~ m/^Luftfeuchtigkeit$/i) { $response = "Die Luftfeuchtigkeit von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value" . ($isNumber ? " Prozent" : ""); }
            elsif ($mappingType =~ m/^Batterie$/i) { $response = "Der Batteriestand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . ($isNumber ?  " beträgt $value Prozent" : " ist $value"); }
            elsif ($mappingType =~ m/^Wasserstand$/i) { $response = "Der Wasserstand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value"; }

            # Andernfalls Antwort falls type aus Intent matched
            elsif ($type =~ m/^(Helligkeit|Lautstärke|Sollwert)$/) { $response = $data->{'Device'} . " ist auf $value gestellt."; }
            elsif ($type =~ m/^Temperatur$/i) { $response = "Die Temperatur von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value" . ($isNumber ? " Grad" : ""); }
            elsif ($type =~ m/^Luftfeuchtigkeit$/i) { $response = "Die Luftfeuchtigkeit von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value" . ($isNumber ? " Prozent" : ""); }
            elsif ($type =~ m/^Batterie$/i) { $response = "Der Batteriestand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . ($isNumber ?  " beträgt $value Prozent" : " ist $value"); }
            elsif ($type =~ m/^Wasserstand$/i) { $response = "Der Wasserstand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value"; }

            # Antwort wenn Custom Type
            elsif (defined($mappingType)) { $response = "$mappingType von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value"; }

            # Standardantwort falls der Type überhaupt nicht bestimmt werden kann
            else { $response = "Der Wert von " . $data->{'Device'} . " beträgt $value."; }
        }
    }
    # Antwort senden
    respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
}


# Eingehende "Status" Intents bearbeiten
sub handleIntentStatus($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room;
    my $mapping;
    my $response = getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentStatus called");

    # Mindestens Device muss existieren
    if (exists($data->{'Device'})) {
        $room = roomName($hash, $data);
        $device = getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = getMapping($hash, $device, "Status", undef);

        if (defined($mapping->{'response'})) {
            $response = getValue($hash, $device, $mapping->{'response'},undef,  $room);
        }
    }
    # Antwort senden
    respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
}


# Eingehende "MediaControls" Intents bearbeiten
sub handleIntentMediaControls($$) {
    my ($hash, $data) = @_;
    my $command, my $device, my $room;
    my $mapping;
    my $response = getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentMediaControls called");

    # Mindestens Kommando muss übergeben worden sein
    if (exists($data->{'Command'})) {
        $room = roomName($hash, $data);
        $command = $data->{'Command'};

        # Passendes Gerät suchen
        if (exists($data->{'Device'})) {
            $device = getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = getActiveDeviceForIntentAndType($hash, $room, "MediaControls", undef);
            $response = getResponse($hash, "NoActiveMediaDevice") if (!defined($device));
        }

        $mapping = getMapping($hash, $device, "MediaControls", undef);

        if (defined($device) && defined($mapping)) {
            my $cmd;

            if    ($command =~ m/^play$/i)   { $cmd = $mapping->{'cmdPlay'}; }
            elsif ($command =~ m/^pause$/i)  { $cmd = $mapping->{'cmdPause'}; }
            elsif ($command =~ m/^stop$/i)   { $cmd = $mapping->{'cmdStop'}; }
            elsif ($command =~ m/^vor$/i)    { $cmd = $mapping->{'cmdFwd'}; }
            elsif ($command =~ m/^zurück$/i) { $cmd = $mapping->{'cmdBack'}; }

            if (defined($cmd)) {
                if (defined($mapping->{'response'})) { $response = getValue($hash, $device, $mapping->{'response'}, $command, $room); }
                else { $response = getResponse($hash, "DefaultConfirmation"); }

                # Cmd ausführen
                runCmd($hash, $device, $cmd);
            }
        }
    }
    # Antwort senden
    respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
}


# Eingehende "MediaChannels" Intents bearbeiten
sub handleIntentMediaChannels($$) {
    my ($hash, $data) = @_;
    my $channel, my $device, my $room;
    my $cmd;
    my $response = getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentMediaChannels called");

    # Mindestens Channel muss übergeben worden sein
    if (exists($data->{'Channel'})) {
        $room = roomName($hash, $data);
        $channel = $data->{'Channel'};

        # Passendes Gerät suchen
        if (exists($data->{'Device'})) {
            $device = getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = getDeviceByMediaChannel($hash, $room, $channel);
        }

        $cmd = getCmd($hash, $device, "snipsChannels", $channel, undef);

        if (defined($device) && defined($cmd)) {
            $response = getResponse($hash, "DefaultConfirmation");

            # Cmd ausführen
            runCmd($hash, $device, $cmd);
        }
    }
    # Antwort senden
    respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
}


# Eingehende "SetColor" Intents bearbeiten
sub handleIntentSetColor($$) {
    my ($hash, $data) = @_;
    my $color, my $device, my $room;
    my $cmd;
    my $response = getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentSetColor called");

    # Mindestens Device und Color muss übergeben worden sein
    if (exists($data->{'Color'}) && exists($data->{'Device'})) {
        $room = roomName($hash, $data);
        $color = $data->{'Color'};

        # Passendes Gerät & Cmd suchen
        $device = getDeviceByName($hash, $room, $data->{'Device'});
        $cmd = getCmd($hash, $device, "snipsColors", $color, undef);

        if (defined($device) && defined($cmd)) {
            $response = getResponse($hash, "DefaultConfirmation");

            # Cmd ausführen
            runCmd($hash, $device, $cmd);
        }
    }
    # Antwort senden
    respond ($hash, $data->{'requestType'}, $data->{sessionId}, $response);
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
