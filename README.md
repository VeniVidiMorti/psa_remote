# PSA Remote

Sailfish-app voor een Citroën ë-C4 (en andere auto's van de PSA-merken van Stellantis) die een **ongewijzigde release** van
[flobz/psa_car_controller](https://github.com/flobz/psa_car_controller) (GPL-3.0) gebruikt, met een eigen wrapper eromheen.
Daarnaast staat er een webproeftuin in, die de wrapper op de desktop aanbiedt.

## Opzet

| Pad | Inhoud |
|---|---|
| `psa_bridge.py` | de wrapper: de functies die de app via PyOtherSide aanroept |
| `sailfish/` | de app: QML, `stellamaris.desktop`, `rpm/stellamaris.spec`, het icoon |
| `requirements.txt` | alleen de afhankelijkheden die de PSA-client van flobz echt importeert |
| `requirements-psacc.txt` | de release van psa_car_controller (altijd met `--no-deps`) |
| `requirements-setup.txt` | extra voor `tools/setup.py` op de desktop (androguard, cryptography); niet voor de telefoon |
| `stubs/reverse_geocode.py` | lege vervanger, zodat numpy en scipy niet nodig zijn |
| `tools/create-venv.sh` | `.venv` met Python 3.11 (zoals op de telefoon) en de release van psa_car_controller |
| `tools/setup.py` | flobz' eigen `InitialSetup`: client-gegevens uit de APK en de `customer_id` (vraagt e-mail en wachtwoord) naar `data/config.json` |
| `tools/prepare-sailfish.sh` | zet `psa_bridge` en de stubs in `sailfish/python`, de release en afhankelijkheden (aarch64) in `sailfish/lib` |
| `tools/publish-release.sh` | publiceert de gebouwde RPM als GitHub-release, voor de updatefunctie van de app |
| `tools/render-icon.sh` | zet `sailfish/icons/stellamaris.svg` om naar de PNG-formaten van Sailfish (86, 108, 128, 172 px) |
| `server.py`, `public/` | de webproeftuin: lokale HTTP-server (alleen standaardbibliotheek) met een testpagina |
| `tools/install-redirect-handler.sh` | koppelt `mymacsdk://`-links op de desktop aan de webproeftuin |
| `data/` | werkmap van psa_car_controller op de desktop: `config.json`, `cars.json`, `otp.bin`; geheim |
| `docs/flobz-notes.md` | bevindingen over psa_car_controller, kandidaten voor een pull request |

## Eenmalig op de desktop

Vereist [uv](https://docs.astral.sh/uv/).

```sh
tools/create-venv.sh
.venv/bin/python tools/setup.py NL       # client-gegevens en customer id naar data/config.json
```

## App bouwen

```sh
tools/prepare-sailfish.sh
cd sailfish && sfdk -c target=SailfishOS-5.1.0.11-aarch64 build
```

Verhoog bij elke build `Release` in `rpm/stellamaris.spec`. Installeren op de telefoon: `devel-su pkcon install-local stellamaris-….rpm`.

De teksten in de code zijn Engels (`qsTr`); de app toont de vertaling voor de systeemtaal uit
`sailfish/translations/stellamaris-<taal>.ts` en anders Engels. Na een tekstwijziging werkt
`sfdk -c target=… build-shell lupdate qml -locations none -ts translations/stellamaris-nl.ts` (in `sailfish/`) het
vertaalbestand bij; nieuwe teksten staan er daarna als `unfinished` in. De meldingen die `psa_bridge.py` als
`RuntimeError` geeft, staan nog een keer in `bridgeErrorText()` in `qml/stellamaris.qml`, zodat ze vertaald worden.

De app werkt zichzelf bij vanaf GitHub: de pagina Over toont een knop zodra er een nieuwere release is, downloadt de RPM
en geeft die aan het installatievenster van Sailfish. `tools/publish-release.sh` publiceert daarvoor de gebouwde RPM als
release (vereist `gh`, ingelogd), met als tag versie en release uit de spec (bijvoorbeeld `0.3.0-7`). Het script weigert
zolang de broncode van die build niet op GitHub staat: eerst committen en pushen.

De app heeft alleen een `config.json` van `tools/setup.py` nodig (client-gegevens en customer id), in zijn datamap
`~/.local/share/nl.stellamaris/stellamaris`. Daar staan ook `otp.bin`, `cars.json` en de log `stellamaris.log`.

- **Inloggen** gebeurt in de app: de inlogpagina van Citroën opent in een webweergave. Gecko kan de redirect naar
  `mymacsdk://` niet volgen en breekt die navigatie af; het frame script `qml/pages/RedirectCatcher.js` ziet de
  302-respons en geeft de `Location` (met de code) door aan de QML.
- **Activeren voor commando's** (sms-code plus pincode van de MyCitroën-app) zit in het uittrekmenu. Daarna staat het
  OTP-geheim van deze installatie in `otp.bin`. De claxon ontbreekt bewust: `RemoteClient.horn()` werkt niet in 3.7.10.
- **Ritten** komen rauw uit `/trips` (nieuwste eerst), omdat het ritmodel in de release van flobz achterloopt op de API.
- **Voorverwarmschema's** komen uit het MQTT-statusbericht van de auto en zijn te wijzigen; de bridge zet ze in flobz'
  `precond_programs` en verstuurt ze met flobz' `preconditioning()`.
- **Laadlimiet** (optioneel): de auto kent zelf geen limiet. Met een limiet ingesteld wekt een `BackgroundJob` de
  telefoon (elke 2,5 minuut tijdens laden, anders elk kwartier) en draait flobz' `ChargeControl`, dat het laden stopt bij
  het percentage en zo nodig de starttijd van uitgesteld laden verzet. Werkt alleen zolang de app draait.

Snel QML testen zonder RPM: kopieer `sailfish/qml` en `sailfish/python` naar `~/stellamaris-dev/` op de telefoon, maak daar
een symlink `lib` naar `/usr/share/stellamaris/lib`, zet `dataDir` in de kopie op de echte datamap en start
`qmlscene ~/stellamaris-dev/qml/stellamaris.qml` (met de Wayland-omgeving van de sessie en `QT_LOGGING_TO_CONSOLE=1`).

## Webproeftuin (desktop)

```sh
tools/install-redirect-handler.sh        # eenmalig; --uninstall om te verwijderen
.venv/bin/python server.py               # http://localhost:3000 (andere poort: PORT=…, ook bij de handler)
```

Na het inloggen stuurt Citroën de browser naar `mymacsdk://oauth2redirect/nl?code=…`, het adres van de officiële app.
De handler geeft die code door aan `/callback`, en daar rondt `psa_bridge.finish_login()` de login af.
De server logt elke uitgaande call naar PSA.
