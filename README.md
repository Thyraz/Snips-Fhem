# Snips-Fhem
FHEM Modul für [snips.ai](http://snips.ai)

## Inhalt
[Modul Installation](#Modul-Installation)

[Definition und Konfiguration in FHEM](#Definition-und-Konfiguration-in-FHEM)

[Snips Installation](#Snips-Installation)

[Erweiterungen für Snips](#Erweiterungen-für-Snips)


## Modul Installation
10_SNIPS.pm nach `opt/fhem/FHEM`kopieren.
Danach FHEM neu starten


## Definition und Konfiguration in FHEM


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

Dann Anleitung hier befolgen:
https://snips.gitbook.io/documentation/advanced-configuration/advanced-solutions


### Sound Setup
über `aplay -l` und `arecord -l` kann man sich erkannte Soundkarten und Mikrofone anzeigen lassen.
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
Hier bei `hw:x,x` entsprechend Card und Device aus euren Listings von oben verwenden.
Bei dem obigen Beispiel ist die interne Soundkarte Card 0 und Device 0.
Das Mikrofon ist ein USB-Gerät, welches als Card 1, Device0 erkannt wurde.

Mit `alsamixer`kann ein Tool zum ändern der Lautstärke gestartet werden.
Evtl. muss hier noch die Masterlautstärke für die Lautsprecher oder das Mikrofon erhöht werden.
Um die Änderungen an den Reglern dauerhaft zu machen einmal `sudo alsactl store`ausführen.

### Assistent installieren
Assistant auf
https://console.snips.ai
konfigurieren und runterladen.
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
Konto erstellen auf aws.amazon.com
User & Groups Dashboard aufrufen: console.aws.amazon.com/aim
Links im Menu auf Groups klicken
Create new Group wählen und als Name polly eingeben
AmazonPollyFullAccess policy auswählen und Gruppe erstellen
Links im Menu auf Users klicken
Add User wählen und als Name polly eingeben und als Access Type "Programatic Access" wählen
Im nächsten Schritt als Gruppe die vorhin erstellte Gruppe polly anwählen
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
Als Default region name `eu-central-1` eingeben
Als output format `json` eingeben
Testen in der Console:
```
sudo aws polly synthesize-speech --output-format mp3 --voice-id Marlene --text 'Hallo, ich kann deine neue Snips Stimme sein wenn du willst.' hello.mp3
```
Sollte eine hello.mp3 erstellen

#### Snips-TTS-Polly installieren
Snips liefert von sich aus eine TextToSpeech Lösung aus.
Diese funktioniert auch komplett offline, klingt aber teilweise etwas dumpf.
Wer damit leben kann, dass die ausgegebene Sprache über Amazons Server geht, findet mit Polly einen natürlicher klingenden Ersatz.
Um sich bei AWS zu registrieren braucht man eine Kreditkarte.

Das Modul cached alle von Amazon empfangenen Audiodaten unter /tmp/tss/ um wiederkehrende Texte nicht erneut von Amazon laden zu müssen.
Das geht erstens schneller, spart aber auch verbrauchte Zeichen im AWS Konto.
Polly bietet im ersten Jahr 5 Millionen Zeichen pro Monat kostenlos.
Danach zahlt man 4$ pro einer Million zu Sprache gewandelter Zeichen.
Einmal die Bibel vorlesen lassen würde somit etwas 16$ kosten. ;)
Für normale Sprachausgaben sollte man dank Caching mit 4$ also sehr lange auskommen.

Das Snips-TTS-Polly Modul simuliert als Drop-In Ersatz das Verhalten des original Snips-TTS Moduls und lauscht auf entsprechende Anforderungen im MQTT Stream von Snips. Die von Amazon empfangenen Audiodaten werden dann auch über MQTT zurück geliefert, damit die nachfolgenden Snips-Module wie gewohnt funktionieren.

Der von mir unten verlinkte Fork hier auf Github enthält ein paar Änderungen gegenüber dem original Snips-TTS-Polly Modul,
damit es auch mit Python Versionen kleiner 3.5 lauffähig ist.
Damit kann man das Modul auch auf Debian Jessie ohne Probleme betreiben.

Damit snips-tts-polly den mqtt server findet muss man die Serverzeile in der Snips config */etc/snips.toml* einkommentieren:
Raute am Anfang der Zeile `mqtt = "localhost:1883" in Section` *[snips-common]* entfernen
```
sudo apt-get install git
cd /opt
sudo git clone https://github.com/Thyraz/snips-tts-polly.git
cd snips-tts-polly
```
testweise mit `sudo ./snips-tts-polly` starten.
Wenn keine Fehler kommen und das Programm bis *MQTT connected* läuft kann mit __STRG+C__ abgebrochen werden.
Kopieren des python scripts: `sudo cp snips-tts-polly /usr/bin`
Kopieren des Systemd services: `sudo cp snips-tts-polly.service /etc/systemd/system/`
`sudo systemctl daemon-reload`
Dann den normalen TTS Service von Snips beenden und Polly starten:
```
sudo systemctl stop snips-tts
sudo systemctl start snips-tts-polly
```
Nun sollten Textausgaben mit Polly erfolgen.
Damit das noch einen Systemstart überlebt, muss noch folgendes ausgeführt werden:
```
sudo systemctl disable snips-tts
sudo systemctl enable snips-tts-polly
```
