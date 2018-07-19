# Snips-Fhem
Fhem module for snips.ai



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
über `<aplay -l>` und `<arecord -l>` kann man sich erkannte Soundkarten und Mikrofone anzeigen lassen.
Hier ist jeweils die Nummer für "card" und "device" interessant.

Mit den Werten muss dann die Datei `</etc/asound.conf>` angepasst bzw. erstellt werden:
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
Hier bei `<hw:x,x>` entsprechend Card und Device aus euren Listings von oben verwenden.
Bei dem obigen Beispiel ist die interne Soundkarte Card 0 und Device 0.
Das Mikrofon ist ein USB-Gerät, welches als Card 1, Device0 erkannt wurde.

Mit `<alsamixer>`kann ein Tool zum ändern der Lautstärke gestartet werden.
Evtl. muss hier noch die Masterlautstärke für die Lautsprecher oder das Mikrofon erhöht werden.
Um die Änderungen an den Reglern dauerhaft zu machen einmal `<sudo alsactl store>`ausführen.

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
