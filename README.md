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
[Snips Installation](#snips-installation)\
[Erweiterungen für Snips](#erweiterungen-für-snips)

## Über Snips
Snips ist ein Sprachassistent ähnlich Siri oder Alexa.\
Die Besonderheit ist hier, dass Snips nach der Installation komplett Offline betrieben wird.\
Es wir also keine Sprache zur Erkennung an einen Server im Internet geschickt.

Snips ist dennoch kein Sprachassistent der nur ein paar simple, eintrainierte Sätze versteht.\
Auch bei Snips steht *Natural Language* im Vordergrund,\
damit man sich nicht an eine feste Syntax bei den Sprachbefehlen halten muss.

Man legt dafür im Snips Konfigurator unter https://console.snips.ai einen Account an und erstellt sich einen Assistenten indem man *Apps* erstellt oder bestehende hinzufügt.\
Jede App kann mehrere Intents beinhalten welche Slots für bestimmte Begriffe (z.B. Gerätenamen, Räume, Schaltzustände, ...) beinhaltet.\
Man *trainiert* die Intents dann mit verschiedensten Beispielsätzen damit der Assistent nachher möglichst gut entscheiden kann was der Nutzer von ihm will.

Snips kann so sehr gut verschiedene Intents unterscheiden, ohne dass diese z.B. wie bei Alexa mit ansagen muss.\
Es ist also nicht wie bei Alexa Custom Skills nötig eine Frage so zu bilden:
> Alexa, frage SmartHome wie viele Fenster sind geöffnet?

Sondern kann die Frage direkt aussprechen:
> Hey Snips, wieviele Fenster sind geöffnet.

Das verbessert die Akzeptanz einer Sprachsteuerung durch die anderen Familienmitglieder zumindest hier enorm.

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
define <name> SNIPS <Prefix> <DefaultRoom>
```
* *Prefix* ist euer Accountname auf https://console.snips.ai \
Dieser wird als Prefix vor jedem Intent von Snips über MQTT mitgeschickt,\
damit mehrere Snips Instanzen auf einem MQTT Server möglich sind.\
Im Beispiel vom Account Namen Homer sähe ein Intent also z.B. so aus: *hermes/intent/Homer:OnOffIntent*

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

## Snips Installation

### Raspberry Pi
ARM Installation basiert auf Raspbian Stretch
Anleitung hier befolgen:
https://snips.gitbook.io/documentation/installing-snips/on-a-raspberry-pi

### AMD64
Installation muss aktuell noch auf Debian Jessie erfolgen.

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
User & Groups Dashboard aufrufen: console.aws.amazon.com/aim \
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
Raute am Anfang der Zeile `mqtt = "localhost:1883" in Section` *[snips-common]* entfernen
```
sudo apt-get install git
cd /opt
sudo git clone https://github.com/Thyraz/snips-tts-polly.git
cd snips-tts-polly
```
testweise mit `sudo ./snips-tts-polly` starten.\
Wenn keine Fehler kommen und das Programm bis *MQTT connected* läuft kann mit __STRG+C__ abgebrochen werden.\
Kopieren des python scripts: `sudo cp snips-tts-polly /usr/bin` \
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
