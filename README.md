# Snips-Fhem
FHEM Modul für [snips.ai](http://snips.ai)

Danke an Matthias Kleine, der mir erlaubt hat sein MQTT Client Modul als Vorlage zu verwenden:\
https://haus-automatisierung.com/hardware/sonoff/2017/12/20/sonoff-vorstellung-part-9.html

## Inhalt
[Über Snips](#Über-snips)\
[Über Snips-Fhem](#Über-snips-fhem)\
[Assistent erstellen](#assistent-erstellen)\
[Modul Installation](#modul-installation)\
[Befehle](#befehle)\
[Readings](#readings--events)\
[Attribute](#attribute)\
[Geräte in FHEM für Snips sichtbar machen](#geräte-in-fhem-für-snips-sichtbar-machen)\
&nbsp;&nbsp;&nbsp;&nbsp;[Der Raum Snips](#raum-snips)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribut snipsName](#attribut-snipsname)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribut snipsRoom](#attribut-snipsroom)\
&nbsp;&nbsp;&nbsp;&nbsp;[Intents über snipsMapping zuordnen](#intents-%C3%BCber-snipsmapping-zuordnen)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Formatierung von CMDs und Readings innerhalb eines snipsMappings](#formatierung-von-cmds-und-readings-innerhalb-eines-snipsmappings)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Standard-Intents](#standard-intents)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[SetOnOff](#setonoff)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[GetOnOff](#getonoff)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[SetNumeric](#setnumeric)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[GetNumeric](#getnumeric)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Status](#status)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[MediaControls](#mediacontrols)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[MediaChannels](#mediachannels)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[SetColor](#setcolor)\
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

Snips kann so sehr gut verschiedene Intents unterscheiden, ohne dass man diese z.B. wie bei Alexa mit ansagen muss.\
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
Oben den Haken **only show apps with actions** entfernen und nach *FHEM* suchen.\
Dann die App hinzufügen.

Wenn ihr fertig seid, drückt ihr auf auf Deploy Assistant um das ZIP File herunterzuladen.

## Modul Installation
10_SNIPS.pm nach `opt/fhem/FHEM`kopieren.
Danach FHEM neu starten.

Die Syntax zur Definition des Moduls sieht so aus:
```
define <name> SNIPS <MqttDevice> <DefaultRoom>
```

* *MqttDevice* Name des MQTT Devices in FHEM das zum MQTT Server von Snips verbindet.

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
define Snips SNIPS SnipsMQTT Wohnzimmer
```

## Befehle
### Set Befehle

* **say**\
  Sprachausgabe über TTS.\
  Snips gibt den übergeben Text per Sprache aus\
  Beispiel: `set <snipsDevice> say Dies ist ein Test`
  
* **textCommand**\
  Snips per Text steuern.\
  Kann zum Beispiel mit diversen Messengerlösungen wie TelegramBot verwendet werden.\
  Das Kommando wird normal abgearbeitet als wäre es vom Nutzer gesprochen worden.\
  Die Rückantwort wird aber nicht per TTS ausgegeben, sondern im Reading *textResponse* abgelegt.\
  Beispiel `set <snipsDevice> textCommand Wie warm ist es im Wohnzimmer`
  
* **updateModel**\
  Erweitert den Wortschatz eures Assistenen um die Begriffe aus eurer FHEM Konfiguration.\
  z.B. Geräte- oder Raumbezeichnungen.\
  Snips verwirft die angelernten Wörter wenn ihr einen neuen Assistenten installiert.\
  Kopiert ihr also einen neuen Assistenten (oder eine neue Version des aktuellen Assistenten) auf den Rechner,\
  müsst ihr updateModell erneut ausführen.\
  Auch nach dem Hinzufügen neuer snipsNames, snipsRoom oder MediaChannels muss updateModell erneut ausgeführt werden.

## Readings / Events

* **lastIntentPayload**\
  Daten des letzten Befehls der in FHEM ankam.

* **listening_*roomname***\
  Wechselt auf 1 wenn das Wakeword erkannt wurde\
  und wieder auf 0 zurück wenn Snips nach der Antwort wieder in den "Standby" geht.\
  Ein Reading pro Snips Satellit/Installation.\
  Kann z.B. verwendet werden um über ein Notify die Musik zu muten während Snips lauscht / spricht.
 
* **voiceResponse** bzw. **textResponse**\
  Antwort die Snips bei einem Sprachbefehle bzw. bei einem Aufruf über `set <snipsDevice> textCommand <text>`\
  zurückgeliefert hat.
  
## Attribute

* **errorResponse**\
  Standardtext den das Snips-Modul bei einem Fehler ausgibt.\
  Die Ausgabe kann durch den Wert `disabled` deaktiviert werden.

* **snipsIntents**\
  Siehe Kapitel *Custom Intents erstellen*
  
## Geräte in FHEM für Snips sichtbar machen
__Wichtig:__ Nach all den nachfolgenden Änderungen muss immer ein ```set <snipsDevice> updateModel``` ausgeführt werden.\
Dadurch wird das Vokabular von Snips um eure Geräte- und Raumnamen erweitert.\
Dies muss ebenfall ausgeführt werden nachdem eine neue Version eureres Assistenten (manuell oder über *sam install assistant*) installiert wurde,\
da hier die nachträglich durch FHEM angelernten Worte wieder verloren gehen.

Damit Snips Geräte aus FHEM erkennt und auch ansprechen/abfragen kann, sind ein paar Voraussetzungen zu erfüllen:

### Raum Snips
Snips sucht nur nach Geräten, die in FHEM im Raum **Snips** liegen.\
Also bei allen Geräten die ihr ansprechen wollt diesen Raum hinzufügen.

### Attribut *snipsName*
Jedem Gerät in FHEM muss das Attribut **snipsName** hinzugefügt werden.\
Es können auch mehrere Namen kommagetrennt angegeben werden.\
Snips findet das Gerät dann unter all diesen Bezeichnungen.\
Beispiel: `attr <device> snipsName Deckenlampe,Wohnzimmerlampe,Kronleuchter`\
Es können auch mehrere Geräte denselben snipsName haben, solange man sie über den Raum unterscheiden kann. 

### Attribut *snipsRoom*
Jedem Gerät in FHEM muss das Attribut **snipsRoom** hinzugefügt werden.\
Beispiel: `attr <device> snipsRoom Wohnzimmer`

### Intents über *snipsMapping* zuordnen
Das Snips Modul hat bisher noch keine automatische Erkennung von Intents für bestimmte Gerätetypen.\
Es müssen also noch bei jedem Device die unterstützten Intents über ein Mapping bekannt gemacht werden.\
Einem Gerät können mehrere Intents zugewiesen werden, dazu einfach eine Zeile pro Mapping im Attribut einfügen.

Das Mapping folgt dabei dem Schema:
```
IntentName:option1=value1,option2=value2,...
```

#### Formatierung von CMDs und Readings innerhalb eines snipsMappings
Einige Intents haben als Option auszuführende FHEM Kommandos oder Readings über die das Modul aktuelle Werte lesen kann.\
Diese können in der Regel auf 3 Arten angegeben werden:
* Set Kommando bzw. Reading des aktuellen Devices direkt angeben:\
  `cmd=on` bzw. `currentReading=temperature`
* Kommando oder Reading auf ein anderes Gerät umleiten:\
  `cmd=Otherdecice:on` bzw. `currentReading=Otherdevice:temperature`
* Perl-Code um ein Kommando auszuführen, oder einen Wert zu bestimmen.\
  Dies ermöglicht komplexere Abfragen oder das freie Zusammensetzen von Befehle.\
  Der Code muss in geschweiften Klammern angegeben werden: \
  `{currentVal={ReadingsVal($DEVICE,"state",0)}`\
  oder\
  `cmd={fhem("set $DEVICE dim $VALUE")}`\
  Innerhalb der geschweiften Klammern kann über $DEVICE auf das aktuelle Gerät zugegriffen werden.\
  Bei der *cmd* Option von *SetNumeric* wird außerdem der zu setzende Wert über $VALUE bereit gestellt.

Gibt man bei der Option `currentVal` das Reading im Format *reading* oder *Device:reading* an,\
kann mit der Option `part` das Reading an Leerzeichen getrennt werden.\
Über `part=1` bestimmt ihr, dass nur der erst Teil des Readings übernommen werden soll.\
Dies ist z.B. nützlich um die Einheit hinter dem Wert abzuschneiden.

#### Standard-Intents

* ##### SetOnOff
  Intent zum Ein-/Ausschalten, Öffnen/Schließen, Starten/Stoppen, ...\
  Beispiel: `SetOnOff:cmdOn=on,cmdOff=off`\
  \
  Optionen:
    * __*cmdOn*__ Befehl der das Gerät einschaltet. Siehe Kapitel zur Formatierung von CMDs.
    * __*cmdOff*__ Befehl der das Gerät ausschaltet. Siehe Kapitel zur Formatierung von CMDs.

  Beispielsätze:
  > Schalte die Deckenlampe ein\
  > Mache das Radio an\
  > Öffne den Rollladen im Wohnzimmer

* ##### GetOnOff
  Intent zur Zustandsabfrage von Schaltern, Kontakten, Geräten, ...\
  Beispiel: `GetOnOff:currentVal=state,valueOff=closed`\
  \
  Optionen:\
  *Hinweis: es muss nur valueOn ODER valueOff gesetzt werden. Alle anderen Werte werden jeweils dem anderen Status zugeordnet.*
    * __*currentVal*__ Reading aus dem der aktuelle Wert ausgelesen werden kann. Siehe Kapitel zur Formatierung von Readings.
    * __*valueOff*__ Wert von *currentVal* Reading der als **off** gewertet wird.
    * __*valueOn*__ Wert von *currentVal* Reading der als **on** gewertet wird.

  Beispielsätze:
  > Ist die Deckenlampe im Büro eingeschaltet?\
  > Ist das Fenster im Bad geöffnet?\
  > Läuft die Waschmaschine?
  
* ##### SetNumeric
  Intent zum Dimmen, Lautstärke einstellen, Temperatur einstellen, ...\
  Beispiel: `SetNumeric:currentVal=pct,cmd=dim,minVal=0,maxVal=99,step=25`\
  \
  Optionen:
    * __*currentVal*__ Reading aus dem der aktuelle Wert ausgelesen werden kann. Siehe Kapitel zur Formatierung von Readings.
    * __*part*__ Splittet *currentVal* Reading bei Leerzeichen. z.B. mit `part=1` kann so der gewünschte Wert extrahiert werden
    * __*cmd*__ Set-Befehl des Geräts der ausgeführt werden soll. z.B. dim. Siehe Kapitel zur Formatierung von CMDs.
    * __*minVal*__ Minimal möglicher Stellwert
    * __*maxVal*__ Maximal möglicher Stellwert
    * __*step*__ Schrittweite für relative Änderungen wie z.B. *Mach die Deckenlampe heller*
    * __*map*__ Bisher nur ein Wert für diese Option möglich: *percent*
    * __*type*__ Zur Unterscheidung bei mehreren GetNumeric Intents in einem Device.\
    Zum Beispiel für die Möglichkeit getrennt eingestellter Sollwert und Ist-Temperatur von einem Thermostat abzufragen.\
    Mögliche Werte: `Helligkeit`, `Temperatur`, `Sollwert`, `Lautstärke`, `Luftfeuchtigkeit`, `Batterie`
  
  *__Erläuterung zu map=percent:__\
  Ist die Option gesetzt, werden alle numerischen Stellwerte als Prozentangaben zwischen minVal und maxVal verstanden.\
  Bei einer Lampe mit `minVal=0` und `maxVal=255` und `map=percent` verhält sich also **Stelle die Lampe auf 50**\
  genauso wie **Stelle die Lampe auf 50 Prozent**.\
  Dies mag bei einer Lampe mehr Sinn ergeben als Werte von 0...255 anzusagen.\
  Beim Sollwert eines Thermostats hingegen wird man die Option eher nicht nutzen,\
  da dort die Angaben normal in °C erfolgen und nicht prozentual zum möglichen Sollwertbereich.*
  
  *__Besonderheit bei type=Lautstärke:__\
  Um die Befehle `leiser`und `lauter` ohne Angabe eines Gerätes verwenden zu können,\
  muss das Modul bestimmen welches Ausgabegerät gerade verwendet wird.\
  Hierfür wird mithilfe des GetOnOff Mappings geprüft welches Gerät mit type=Lautstärke eingeschaltet ist.\
  Dabei wird zuerst im aktuellen snipsRoom gesucht, dananch im Rest falls kein Treffer erfolgt ist.\
  Es empfiehlt sich daher bei Verwendung von type=Lautstärke auch immer ein GetOnOff Mapping einzutragen.\
  Ein `Gerätename lauter` bzw. `Gerätename leiser` ist unabhängig dieser Sonderbehandlung natürlich immer möglich.*
  
  Beispielsätze:
  > Stelle die Deckenlampe auf 30 Prozent\
  > Mach das Radio leiser\
  > Stelle die Heizung im Büro um 2 Grad wärmer
  > Lauter

* ##### GetNumeric
  Intent zur Abfrage von numerischen Readings wie Temperatur, Helligkeit, Lautstärke, ...
  Beispiel: `GetNumeric:currentVal=temperature,part=1`\
  \
  Optionen:
    * __*currentVal*__ Reading aus dem der aktuelle Wert ausgelesen werden kann. Siehe Kapitel zur Formatierung von Readings.
    * __*part*__ Splittet *currentVal* Reading bei Leerzeichen. z.B. mit `part=1` kann so der gewünschte Wert extrahiert werden
    * __*map*__ Siehe Beschreibung im *SetNumeric* Intent. Hier wird rückwärts gerechnet um wieder Prozent zu erhalten
    * __*minVal*__ nur nötig bei genutzter `map` Option
    * __*maxVal*__ nur nötig bei genutzter `map` Option
    * __*type*__ Zur Unterscheidung bei mehreren GetNumeric Intents in einem Device.\
      Zum Beispiel für die Möglichkeit getrennt eingestellter Sollwert und Ist-Temperatur von einem Thermostat abzufragen.\
      Mögliche Werte: `Helligkeit`, `Temperatur`, `Sollwert`, `Lautstärke`, `Luftfeuchtigkeit`, `Batterie`
 
  Beispielsätze:
  > Wie ist die Temperatur vom Thermometer im Büro?\
  > Auf was ist das Thermostat im Bad gestellt?\
  > Wie hell ist die Deckenlampe?\
  > Wie laut ist das Radio im Wohnzimmer?
  
* ##### Status
  Intent zur Abfrage von Informationen zu einem Gerät.\ Der Antworttext kann frei gewählt werden, 
  Beispiel: `Status:response=Die Temperatur beträgt [Thermometer:temperature] Grad bei [Thermometer:humidity] Prozent Luftfeuchtigkeit`\
  \
  Optionen:
    * __*response*__ Text den Snips ausgeben soll. Werte aus FHEM können im Format `[Device:Reading]` eingefügt werden.\
    Kommas im Text müssen escaped werden (`\,`statt `,`), da normale Kommas beim snipsMapping das Trennzeichen zwischen den verschiedenen Optionen gelten.
 
  Beispielsätze:
  > Wie ist der Status vom Thermometer im Büro?\
  > Status Deckenlampe im Wohnzimmer\
  > Status Waschmaschine
  
* ##### MediaControls
  Intent zum Steuern von Mediengeräten\
  Beispiel: `MediaControls:cmdPlay=play,cmdPause=pause,cmdStop=stop`\
  \
  Optionen:
    * __*cmdPlay*__ Befehl *Play* des Geräts. Siehe Kapitel zur Formatierung von CMDs.
    * __*cmdPause*__ Befehl *Pause* des Geräts. Siehe Kapitel zur Formatierung von CMDs.
    * __*cmdStop*__ Befehl *Stop* des Geräts. Siehe Kapitel zur Formatierung von CMDs.
    * __*cmdFwd*__ Befehl *Skip Forward* des Geräts. Siehe Kapitel zur Formatierung von CMDs.
    * __*cmdBack*__ Befehl *Skip Back* des Geräts. Siehe Kapitel zur Formatierung von CMDs.

  *__Hinweis zu Befehlen ohne Nennung des Gerätenamens:__\
  Um Befehle wie z.B. `Pause`, `Nächstes Lied` oder `Zurück` ohne Angabe eines Gerätes verwenden zu können,\
  muss das Modul bestimmen welches Ausgabegerät gerade verwendet wird.\
  Hierfür wird mithilfe des GetOnOff Mappings geprüft welches Gerät mit dem Intent MediaControls eingeschaltet ist.\
  Dabei wird zuerst im aktuellen snipsRoom gesucht, dananch im Rest falls kein Treffer erfolgt ist.\
  Es empfiehlt sich daher bei Verwendung von MediaControls auch immer ein GetOnOff Mapping einzutragen.\
  Ein `Radio pausieren` bzw. `Nächstes Lied auf dem Radio` ist unabhängig dieser Sonderbehandlung natürlich immer möglich.*
  
  Beispielsätze:
  > Auf dem Radio ein Titel nach vorne springen\
  > Pause\
  > Video auf dem DVD Player überspringen\
  > Wiedergabe stoppen\
  > Weiter\
  > Zurück
  
* ##### MediaChannels
  Intent zum Abspielen von Radio-/Fernsehsendern, Favoriten, Playlists, ...
  
  Anstatt im Attribut snipsMapping eingetragen zu werden,\
  wird Der Intent über ein eigenes Attribut `snipsChannels` im jeweiligen Gerät konfiguriert.\
  Grund dafür ist die mehrzeilige Konfiguration des Intents.\
  \
  Um dem Device das neue Attribut hinzuzufügen, muss das Attribut _userattr_ befüllt werden:\
  `attr <deviceName> userattr snipsChannels:textField-long`\
  \
  Danach kann das Attribut `snipsChannels` befüllt werden.\
  Pro Zeile ein Eintrag im Format *Channelbezeichnung=cmd*\
  *Channelbezeichnung* ist der Name den ihr sprechen wollt.\
  *cmd* ist der Set-Befehl des Geräts. Siehe Kapitel zur Formatierung von CMDs.
  \
  Beispiel:
  ```
  SWR3=favorite s_w_r_3
  SWR1=favorite s_w_r_1
  Das Ding=favorite das_ding
  BigFM=favorite bigfm
  ```
  
   *__Hinweis zu Befehlen ohne Nennung des Gerätenamens:__\
  Um die Wiedergabe ohne Angabe eines Gerätes starten zu können,\
  muss das Modul bestimmen welches Ausgabegerät verwendet werden soll.\
  Hierzu sucht das Modul über das Attribut `snipsChannels` nach einem passenden Device.
  Treffer im aktuellen (bzw. angesprochenen) Raum werden bevorzugt.*
  
  Beispielsätze:
  > Spiele SWR3 auf dem Radio im Büro\
  > Spiele SWR1\
  > Schalte um auf BigFM\
  > Sender vom Radio auf Das Ding wechseln

* ##### SetColor
  Intent zum Steuern von Lichtfarben, ...
  
  Anstatt im Attribut snipsMapping eingetragen zu werden,\
  wird Der Intent über ein eigenes Attribut `snipsColors` im jeweiligen Gerät konfiguriert.\
  Grund dafür ist die mehrzeilige Konfiguration des Intents.\
  \
  Um dem Device das neue Attribut hinzuzufügen, muss das Attribut _userattr_ befüllt werden:\
  `attr <deviceName> userattr snipsColors:textField-long`\
  \
  Danach kann das Attribut `snipsColors` befüllt werden.\
  Pro Zeile ein Eintrag im Format *Farbbezeichnung=cmd*\
  *Farbbezeichnung* ist der Name den ihr sprechen wollt.\
  *cmd* ist der Set-Befehl des Geräts. Siehe Kapitel zur Formatierung von CMDs.
  \
  Beispiel:
  ```
  rot=rgb FF0000
  grün=rgb 00FF00
  blau=rgb 0000FF
  weiß=ct 3000
  warmweiß=ct 2700
  ```
  
  Beispielsätze:
  > Stelle Deckenlampe im Wohnzimmer auf warmweiß\
  > Färbe Stehlampe blau\
  > Lichterkette auf grün

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

Sollte Snips nach Aktualisierung eures Assistenten, dem Hinzufügen neuer Geräte, oder dem Ändern von snipsName oder snipsRoom Attributen Geräte- oder Raumbezeichnungen nicht mehr verstehen,\
bitte sicherstellen, dass ```set <snipsDevice> updateModel``` ausgeführt wurde.

## Snips Installation

### Raspberry Pi
ARM Installation basiert auf Raspbian Stretch
Anleitung hier befolgen:
https://snips.gitbook.io/documentation/installing-snips/on-a-raspberry-pi

### AMD64
Installation muss aktuell auf __Debian Stretch__ erfolgen.

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
