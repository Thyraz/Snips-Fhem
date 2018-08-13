# Snips-Fhem
FHEM Modul für [snips.ai](http://snips.ai)

Danke an Matthias Kleine, der mir erlaubt hat sein MQTT Client Modul als Vorlage zu verwenden:\
https://haus-automatisierung.com/hardware/sonoff/2017/12/20/sonoff-vorstellung-part-9.html

## Inhalt
[Über Snips](#Über-snips)\
[Über Snips-Fhem](#Über-snips-fhem)\
[Assistent erstellen](#assistent-erstellen)\
[Modul Installation](#modul-installation)\
[Geräte in FHEM für Snips sichtbar machen](#geräte-in-fhem-für-snips-sichtbar-machen)\
[Für Fortgeschrittene: Eigene Custom Intents erstellen und in FHEM darauf reagieren](#f%C3%BCr-fortgeschrittene-eigene-custom-intents-erstellen-und-in-fhem-darauf-reagieren)\
[Anhang 1: Snips Installation](#snips-installation)\
[Anhang 2: Erweiterungen für Snips](#erweiterungen-für-snips)

## Über Snips
Snips ist ein Sprachassistent ähnlich Siri oder Alexa.\
Die Besonderheit ist hier, dass Snips nach der Installation komplett Offline betrieben wird.\
Es wir also keine Sprache zur Erkennung an einen Server im Internet geschickt.

Man legt dafür im Snips Konfigurator unter https://console.snips.ai einen Account an und erstellt sich einen Assistenten indem man *Apps* erstellt oder bestehende hinzufügt.\
Jede App kann mehrere Intents beinhalten welche Slots für bestimmte Begriffe (z.B. Gerätenamen, Räume, Schaltzustände, ...) beinhaltet.\
Man *trainiert* die Intents dann mit verschiedensten Beispielsätzen damit der Assistent nachher möglichst gut entscheiden kann was der Nutzer von ihm will.

Snips kann so sehr gut verschiedene Intents unterscheiden, ohne dass diese z.B. wie bei Alexa mit ansagen muss.\
Es ist also nicht wie bei Alexa Custom Skills nötig eine Frage so zu bilden:
> Alexa, frage SmartHome wie viele Fenster sind geöffnet?

Sondern kann die Frage direkt aussprechen:
> Hey Snips, wieviele Fenster sind geöffnet.

Snips unterstüzt "Satelliten" um weitere Räume anzubinden.
Dies können z.B. weitere Raspberry Pi mit Mikrofon und einen kleinen Lautsprecher sein.
Die Software für die Satelliten benötigt keine schnelle Hardware, kann also auch ein Pi Zero sein.

Wenn man seinen Assistent fertig konfiguriert hat, kann man ihn als Zip Datei herunterladen und in die Snips Installation einspielen.\
Ab da funktioniert die Spracherkennung lokal auf dem System.

## Über Snips-Fhem
Snips besteht aus mehreren Modulen (Hot-Word Detection, Texterkennung, Natural Language zu Intent Parser, ...)\
All diese Module kommunizieren per MQTT miteinander.\
Auch das resultiernde JSON Konstrukt, welches Snips am Ende ausspuckt wird über MQTT published.\
Dieses beinhaltet den IntentNamen und die gesprochenen Wörter der einzelnen Slots. Also z.B. Gerätenamen, Raum, usw.

Snips-Fhem wertet diese JSON Nachrichten aus und setzt sie entsprechend in Befehle um.\
In die andere Richtung sendet Snips-Fhem ebenfalls Nachrichten an Snips um z.B. Antworten für TextToSpeech bereitzustellen.

Snips-Fhem implementiert hierfür keinen eigene MQTT-Verbindung, sondern setzt dafür auf das bestehende 00_MQTT.pm Modul und meldet sich bei diesem als Client an.

Es muss vor dem Snips Modul also ein MQTT Device für den Snips MQTT Server in Fhem definiert werden.

## Assistent erstellen
Account unter https://console.snips.ai erstellen und einen neuen Assistenten erstellen.

Dort eine neue App aus dem Store hinzufügen.\
Oben den Haken **only show apps with actions** entfernen und nach *FHEM* suchen.

Die App hinzufügen und danach anwählen. Hier auf *Edit App* klicken, dann auf *Fork*.\
Nun könnt ihr in die einzelnen Intents hineinschauen und die Beispielsätze sehen.

Zusätzlich könnt ihr die Beispiel-Geräte um eure eigenen erweitern.\
Dazu z.B. den SetOnOff Intent öffnen und beim Slot **de.fhem.Devices** auf editieren klicken.\
Nun bekommt ihr eine Liste mit bisher von mir eingetragenen Gerätenamen.\
Erweitert diese um eure Geräte.\
Der vorne eingetragene Name muss später in Fhem über das Attribut *snipsName* bekannt gemacht werden.

Es sind auch ein oder mehrere Synonyme möglich.\
So kann man für die Deckenlampe z.B. noch Deckenlicht und Wohnzimmerlampe eintragen.\
Snips wird bei all diesen Bezeichnungen dann später dennoch Deckenlampe als Slot Device an FHEM übertragen.

Wenn ihr fertig seid, drückt ihr auf Save und danach auf Deploy Assistant um das ZIP File herunterzuladen.\
In diesem Schritt findet auch erst die finale Optimierung der Natural Language und Voice Erkennung statt.\
Falls ihr Snips statt auf einer echten Installation erstmal im Browser unter https://console.snips.ai testen wollt,\
solltet ihr also dennoch nach jeder Änderung einmal den Download des Assistenten anstoßen.\
Ansonsten kann es sein, dass die Spracherkennung über das Micro des Rechners, oder die Texterkennung des eingegebenen Textes nicht richtig funktioniert.

## Modul Installation
10_SNIPS.pm nach `opt/fhem/FHEM`kopieren.
Danach FHEM neu starten.

Die Syntax zur Definition des Moduls sieht so aus:
```
define <name> SNIPS <MqttDevice> <DefaultRoom>
```

* *DefaultRoom* weist die Snips Hauptinstanz einem Raum zu.\
Im Gegensatz zu weiteren Snips Satellites in anderen Räumen,\
kann die Hauptinstanz nicht umbenannt werden und heißt immer *default*.\
Um den Raumnamen bei einigen Befehlen weglassen zu können, sofern sie den aktuellen Raum betreffen ,\
muss Snips eben wissen in welchem Raum man sich befindet.\
Dies ermöglicht dann z.B. ein "Deckenlampe einschalten"\
auch wenn man mehrere Geräte mit dem Alias Deckenlampe in unterschiedlichen Räumen hat.

Beispiel für die Definition des MQTT Servers und Snips in FHEM:
```
define SnipsMQTT MQTT <ip-or-hostname-of-snips-machine>:1883
define Snips SNIPS SnipsMQTT Homer Wohnzimmer
```


## Geräte in FHEM für Snips sichtbar machen
Damit Snips Geräte aus FHEM erkennt und auch ansprechen/abfragen kann, sind ein paar Voraussetzungen zu erfüllen:

### Raum Snips
Snips sucht nur nach Geräten, die in FHEM im Raum **Snips** liegen.\
Also bei allen Geräten die ihr ansprechen wollt diesen Raum hinzufügen.

### Attribut *snipsName*
Jedem Gerät in FHEM kann das Attribut **snipsName** hinzugefügt werden.\
Snips kann Geräte anhand dieser Kriterien finden:
* Attribut snipsName
* Attribut alias
* Name des Geräts in FHEM

### Attribut *snipsRoom*
Jedem Gerät in FHEM kann das Attribut **snipsRoom** hinzugefügt werden.\
Snips kann Geräte anhand dieser Kriterien einem Raum zuordnen:
* Attribut snipsRoom
* Alle gewählten Räume im Attribut room

### Intents über *snipsMapping* zuordnen
Das Snips Modul hat bisher noch keine automatische Erkennung von Intents für bestimmte Gerätetypen.\
Es müssen also noch bei jedem Device die unterstützten Intents über ein Mapping bekannt gemacht werden.\
Einem Gerät können mehrere Intents zugewiesen werden, dazu einfach eine Zeile pro Mapping im Attribut einfügen.

Das Mapping folgt dabei dem Schema:
```
IntentName=currentValueReading,option1=value1,option2=value2,...
```
currentValueReading ist dabei ein Reading, welches den aktuellen Wert des Geräts zurückspiegelt.\
Bei einem SetOnOff Intent wären das die Werte aus den Mapping-Optionen cmdOn bzw. cmdOff.\
Für einen SetNumeric Intent muss das Reading z.B. den aktuell per dim XX gesetzten Helligkeitswert zurückliefern.\
Liefert das Device zusätzlich zu der benötigten Info noch eine Einheit wie z.B. `5 °C`,\
kann die Zahl über die Option *part=0* extrahiert werden.

* **SetOnOff**\
  Intent zum Ein-/Ausschalten, Öffnen/Schließen, Starten/Stoppen, ...\
  Beispiel: `SetOnOff=brightness,valueOff=0,cmdOn=on,cmdOff=off`\
  \
  Optionen:\
  *Hinweis: es muss nur valueOn ODER valueOff gesetzt werden. Alle anderen Werte werden jeweils dem anderen Status zugeordnet.*
    * __*valueOff*__ Wert von *currentValueReading* der als **off** gewertet wird
    * __*valueOn*__ Wert von *currentValueReading* der als **on** gewertet wird
    * __*cmdOn*__ Befehl der das Gerät einschaltet
    * __*cmdOff*__ Befehl der das Gerät ausschaltet

  Beispielsätze:
  > Schalte die Deckenlampe ein\
  > Mache das Radio an\
  > Öffne den Rollladen im Wohnzimmer

* **GetOnOff**\
  Intent zur Zustandsabfrage von Schaltern, Kontakten, Geräten, ...
  Beispiel: `GetOnOff=reportedState,valueOff=closed`\
  \
  Optionen:\
  *Hinweis: es muss nur valueOn ODER valueOff gesetzt werden. Alle anderen Werte werden jeweils dem anderen Status zugeordnet.*
    * __*valueOff*__ Wert von *currentValueReading* der als **off** gewertet wird
    * __*valueOn*__ Wert von *currentValueReading* der als **on** gewertet wird

  Beispielsätze:
  > Ist die Deckenlampe im Büro eingeschaltet?\
  > Ist das Fenster im Bad geöffnet?\
  > Läuft die Waschmaschine?
  
* **SetNumeric**\
  Intent zum Dimmen, Lautstärke einstellen, Temperatur einstellen, ...\
  Beispiel: `SetNumeric=pct,cmd=dim,minVal=0,maxVal=99,step=25`\
  \
  Optionen:
    * __*part*__ Splittet *currentValueReading* bei Leerzeichen. z.B. mit `part=1` kann so der gewünschte Wert extrahiert werden
    * __*cmd*__ Set-Befehl des Geräts der ausgeführt werden soll. z.B. dim
    * __*minVal*__ Minimal möglicher Stellwert
    * __*maxVal*__ Maximal möglicher Stellwert
    * __*step*__ Schrittweite für relative Änderungen wie z.B. *Mach die Deckenlampe heller*
    * __*map*__ Bisher nur ein Wert für diese Option möglich: *percent*
  
  *Erläuterung zu map=percent:\
  Ist die Option gesetzt, werden alle numerischen Stellwerte als Prozentangaben zwischen minVal und maxVal verstanden.\
  Bei einer Lampe mit `minVal=0` und `maxVal=255` hat also **Stelle die Lampe auf 50**\
  das selbe Verhalten wie **Stelle die Lampe auf 50 Prozent**.\
  Dies mag bei einer Lampe mehr Sinn ergeben als Werte von 0...255 anzusagen.\
  Beim Sollwert eines Thermostats hingegen wird man die Option eher nicht nutzen,\
  da dort die Angaben normal in °C erfolgen und nicht prozentual zum möglichen Sollwertbereich.*
  
  Beispielsätze:
  > Stelle die Deckenlampe auf 30 Prozent\
  > Mach das Radio leiser\
  > Stelle die Heizung im Büro um 2 Grad wärmer

* **GetNumeric**\
Intent zur Abfrage von numerischen Readings wie Temperatur, Helligkeit, Lautstärke, ...
Beispiel: `GetNumeric=temperature,part=1`\
\
Optionen:
  * __*part*__ Splittet *currentValueReading* bei Leerzeichen. z.B. mit `part=1` kann so der gewünschte Wert extrahiert werden
  * __*map*__ Siehe Beschreibung im *SetNumeric* Intent. Hier wird rückwärts gerechnet um wieder Prozent zu erhalten
  * __*minVal*__ nur nötig bei genutzter `map` Option
  * __*maxVal*__ nur nötig bei genutzter `map` Option
  * __*type*__ Zur Unterscheidung bei mehreren GetNumeric Intents in einem Device.\
    Zum Beispiel für die Möglichkeit getrennt eingestellter Sollwert und Ist-Temperatur von einem Thermostat abzufragen.\
    Mögliche Werte: `Helligkeit`, `Temperatur`, `Sollwert`, `Lautstärke`, `Luftfeuchtigkeit`
 
  Beispielsätze:
  > Wie ist die Temperatur vom Thermometer im Büro?\
  > Auf was ist das Thermostat im Bad gestellt?\
  > Wie hell ist die Deckenlampe?\
  > Wie laut ist das Radio im Wohnzimmer?

## Für Fortgeschrittene: Eigene Custom Intents erstellen und in FHEM darauf reagieren

### Was ist damit möglich
Eigene Intents ermöglichen es euch Snips weitere Sätze / Fragen beizubringen.\
In diesen könnt Ihr auch eigene Slots mit möglichen Begriffen anlegen.\
Ein mögliches Beispiel wäre die Einbindung des Abfall Moduls in den Sprachassistent.\
Snips wird ein neuer Intent *Abfall* beigebracht, mit Beispielsätzen wie *Wann wird der Restmüll abgeholt*.\
Dieser kann dann einen Slot *Type* beinhalten mit verschiedenen Werte wie z.B. Restmüll, Biomüll, Gelber Sack).

### Einen Intent für Snips erstellen
Intents werden auf https://console.snips.ai konfiguriert.\
Es empfiehlt sich für eure Custom Intents in Snips eine extra App anzulegen,\
anstatt die FHEM App dafür zu forken und diese darin abzulegen.\
Eine bebilderte Anleitung zum Erstellen eines Intents, der zugehörigen Slots und den Beispielsätzen findet ihr hier:\
https://snips.gitbook.io/documentation/console/set-intents#create-a-new-intent

### Anfragen zum Custom Intent in Fhem entgegen nehmen
Wird der Satz von Snips erkannt, erhält FHEM als Intent-Name *Abfall* geliefert und für den Slot **Type** den Begriff aus dem Slot.\
Im Snips Modul in FHEM kann einem Intent dann über das Attribut __*snipsIntents*__ eine Perl Funktion z.B. aus 99_myUtils.pm zugewiesen werden.\
Pro Intent wird hier eine neue Zeile hinzugefügt. Diese hat folgenden Syntax:
```
IntentName=nameDerFunktion(SlotName1,SlotName2,...)
```
Für unseren Abfall Intent könnte da so aussehen (die Perl Funktion müsste *snipsAbfall* heißen und würde einen Parameter übergeben bekommen:
```
Abfall=snipsAbfall(Type)
```
Die Perl Funktionen können einen Text zurückliefern, welcher dann von Snips als Antwort ausgegeben wird.\
Hier ein Beispiel passend zum oben erstellten Intent:
```
# Abfall Intent
sub snipsAbfall($) {
    # Übergebene Parameter in Variablen speichern
    my ($type) = @_;
	
    # Standardantwort festlegen
    my $response = "Das kann ich leider nicht beantworten";
	
    if ($type eq "Restmüll") {
        # Wert aus Reading lesen
        my $days = ReadingsVal("MyAbfallDevice","Restmuell_days", undef);
        # Antwort überschreiben mit dem Ergebnis
        $response = "Der Restmüll wird in $days abgeholt";
    }
	
    # Antwort an das Snipsmodul zurück geben
    return $response;
}
```

Ein weiteres Beispiel findet sich hier im Forum:\
https://forum.fhem.de/index.php/topic,89548.msg821359.html#msg821359

### Troubleshooting
Solltet ihr keine Antwort von Snips bekommen, einfach Verbose im Snips Device auf 5 setzen.\
Ihr solltet dann im Log sehen welcher Intent erkannt wurde und welche Slots mit welchen Werten belegt sind.\
Gibt es Fehler beim Aufruf der Perl Funktion sollte man dies hier auch sehen.

Wenn Snips eure Geräte- oder Raumnamen nicht versteht,\
wurde evtl. das ASR Inject Paket nicht installiert:\
[Installation ASR Injection](#wichtig-asr-injection-installieren)

## Snips Installation

### Raspberry Pi
ARM Installation basiert auf Raspbian Stretch
Anleitung hier befolgen:
https://snips.gitbook.io/documentation/installing-snips/on-a-raspberry-pi

### AMD64
Installation muss aktuell neuerdings auf __Debian Stretch__ erfolgen.

Für die erfolgreiche Installation musste ich die non-free Packages in Apt hinzufügen:
```
sudo nano /etc/apt/sources.list
```
in jeder Zeile hinter „contrib“ „non-free“ anhängen

Außerdem vor der Snips Installation diese Pakete installieren:
```
sudo apt-get install lsb-release apt-transport-https ca-certificates systemd systemd-sysv libttspico-utils alsa-utils
```
Wegen Systemd Installation danach evtl. neu booten.

Dann Anleitung hier befolgen:\
https://snips.gitbook.io/documentation/advanced-configuration/advanced-solutions

### Wichtig: ASR Injection installieren
Damit das FHEM Modul der Snips App eure Geräte- und Raumnamen zur Verfügung stellen kann,\
muss zusätzlich noch snips-asr-snip-asr-injection installiert werden:
```
   sudo apt-get install -y snips-asr-injection
```
Andernfalls wird Snips eure Geräte- und Raumbezeichnungen nicht verstehen.

### Sound Setup
über `aplay -l` und `arecord -l` kann man sich erkannte Soundkarten und Mikrofone anzeigen lassen.\
Hier ist jeweils die Nummer für "card" und "device" interessant.

Mit den Werten muss dann die Datei `/etc/asound.conf` angepasst bzw. erstellt werden:
```
sudo nano /etc/asound.conf
```
Inhalt sollte dann so aussehen:
```
pcm.!default {
  type asym
  playback.pcm {
    type plug
    slave.pcm "hw:0,0"
  }
  capture.pcm {
    type plug
    slave.pcm "hw:1,0"
  }
}
```
Hier bei `hw:x,x` entsprechend Card und Device aus euren Listings von oben verwenden.\
Bei dem obigen Beispiel ist die interne Soundkarte Card 0 und Device 0.\
Das Mikrofon ist ein USB-Gerät, welches als Card 1, Device0 erkannt wurde.

Mit `alsamixer`kann ein Tool zum ändern der Lautstärke gestartet werden.\
Evtl. muss hier noch die Masterlautstärke für die Lautsprecher oder das Mikrofon erhöht werden.\
Um die Änderungen an den Reglern dauerhaft zu machen einmal `sudo alsactl store`ausführen.

### Assistent installieren
Assistant auf https://console.snips.ai konfigurieren und runterladen.\
Entpacktes assistant Verzeichnis als /usr/share/snips/assistant speichern

Danach die Snips Services stoppen:
```
sudo systemctl stop "snips-*"
```
und wieder starten:
```
sudo systemctl start "snips-*"
```
So kann man noch überprüfen ob die Services laufen und alles ok zu sein scheint:
```
sudo systemctl status "snips-*"
```

Danach sollte Snips über *Hey Snips* geweckt werden können.


## Erweiterungen für Snips

### Bessere Sprachausgabe mit Amazon Polly
#### AWS Konto erstellen 
Konto erstellen auf aws.amazon.com\
User & Groups Dashboard aufrufen: https://console.aws.amazon.com/iam/home \
Links im Menu auf Groups klicken\
Create new Group wählen und als Name polly eingeben\
AmazonPollyFullAccess policy auswählen und Gruppe erstellen\
Links im Menu auf Users klicken\
Add User wählen und als Name polly eingeben und als Access Type "Programatic Access" wählen\
Im nächsten Schritt als Gruppe die vorhin erstellte Gruppe polly anwählen\
Achtung: Am Ende werden Access key ID und Secret access key angezeigt. Diese jetzt kopieren, da wir sie nachher zum Authorisieren brauchen.

#### Installation auf dem Snips Rechner
```
sudo apt-get install mpg123
sudo pip3 install toml
sudo pip3 install paho-mqtt
sudo pip3 install boto3
sudo pip3 install awscli
sudo aws configure
```
Als Default region name `eu-central-1` eingeben\
Als output format `json` eingeben\
Testen in der Console:
```
sudo aws polly synthesize-speech --output-format mp3 --voice-id Marlene --text 'Hallo, ich kann deine neue Snips Stimme sein wenn du willst.' hello.mp3
```
Sollte eine hello.mp3 erstellen

#### Snips-TTS-Polly installieren
Snips liefert von sich aus eine TextToSpeech Lösung aus.\
Diese funktioniert auch komplett offline, klingt aber teilweise etwas dumpf.\
Wer damit leben kann, dass die ausgegebene Sprache über Amazons Server geht, findet mit Polly einen natürlicher klingenden Ersatz.\
Um sich bei AWS zu registrieren braucht man eine Kreditkarte.

Das Modul cached alle von Amazon empfangenen Audiodaten unter /tmp/tss/ um wiederkehrende Texte nicht erneut von Amazon laden zu müssen.\
Das geht erstens schneller, spart aber auch verbrauchte Zeichen im AWS Konto.\
Polly bietet im ersten Jahr 5 Millionen Zeichen pro Monat kostenlos.\
Danach zahlt man 4$ pro einer Million zu Sprache gewandelter Zeichen.\
Einmal die Bibel vorlesen lassen würde somit etwas 16$ kosten. ;)\
Für normale Sprachausgaben sollte man dank Caching mit 4$ also sehr lange auskommen.

Das Snips-TTS-Polly Modul simuliert als Drop-In Ersatz das Verhalten des original Snips-TTS Moduls und lauscht auf entsprechende Anforderungen im MQTT Stream von Snips.\
Die von Amazon empfangenen Audiodaten werden dann auch über MQTT zurück geliefert, damit die nachfolgenden Snips-Module wie gewohnt funktionieren.

Der von mir unten verlinkte Fork hier auf Github enthält ein paar Änderungen gegenüber dem original Snips-TTS-Polly Modul,\
damit es auch mit Python Versionen kleiner 3.5 lauffähig ist.\
Damit kann man das Modul auch auf Debian Jessie ohne Probleme betreiben.

Damit snips-tts-polly den mqtt server findet muss man die Serverzeile in der Snips config */etc/snips.toml* einkommentieren:\
Raute am Anfang der Zeile `mqtt = "localhost:1883"` in Section *[snips-common]* entfernen
```
sudo apt-get install git
cd /opt
sudo git clone https://github.com/Thyraz/snips-tts-polly.git
cd snips-tts-polly
```
testweise mit `sudo ./snips-tts-polly.py` starten.\
Wenn keine Fehler kommen und das Programm bis *MQTT connected* läuft kann mit __STRG+C__ abgebrochen werden.\
Kopieren des python scripts: `sudo cp snips-tts-polly.py /usr/bin` \
Kopieren des Systemd services: `sudo cp snips-tts-polly.service /etc/systemd/system/` \
`sudo systemctl daemon-reload` \
Dann den normalen TTS Service von Snips beenden und Polly starten:
```
sudo systemctl stop snips-tts
sudo systemctl start snips-tts-polly
```
Nun sollten Textausgaben mit Polly erfolgen.\
Damit das noch einen Systemstart überlebt, muss noch folgendes ausgeführt werden:
```
sudo systemctl disable snips-tts
sudo systemctl enable snips-tts-polly
```
