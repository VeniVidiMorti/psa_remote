# Notities over psa_car_controller (flobz), release 3.7.10

Waarnemingen bij het gebruik van de ongewijzigde release. Kandidaten voor een issue of pull request bij
[flobz/psa_car_controller](https://github.com/flobz/psa_car_controller).

## Gegenereerde API-client loopt achter op de v4-API

`psa/connected_car_api` is gegenereerd uit een oudere specificatie ("Connected Car V2 API" in de docstrings).
De echte v4-responses wijken daarvan af, gezien bij een Citroën ë-C4 (november 2026):

| Model in flobz (`models/trip.py`) | Werkelijke v4-respons van `/user/vehicles/{id}/trips` |
|---|---|
| `avgConsumption` (`type`, `value`) | `energyConsumptions[]` met `consumption` (Wh), `avgConsumption` (Wh/100 km), `type`, `subType` |
| `odometer` | `startMileage` |
| `zeroEmissionRatio` | ontbreekt |
| `duration` als ISO 8601-duur | `duration` in seconden |
| ontbreekt | `startEnergies[]` / `endEnergies[]` (`level`, `autonomy`) |
| ontbreekt | `kinetic` (`avgSpeed` in wisselende eenheid, `maxSpeed` steeds 0) |
| `faults` als enum | `faults[]` met `fault` en `cause` (bijv. `DataLacking` / `PrivacyGeo`) |

`kinetic.avgSpeed` is niet bruikbaar: bij een rit van 11,3 km in 783 s stond er 14,43 (m/s, klopt met 52 km/u),
bij een rit van 47,6 km stond er 74,2 (km/u). Deze app rekent de gemiddelde snelheid zelf uit `distance` en `duration`.
Er staan ook veel ritten van 0–0,1 km en een paar minuten in de lijst, vermoedelijk door ontgrendelen of kort aanzetten.

Verder voor deze auto: `/trips/{tid}/ecoaching` en `/trips/{tid}/telemetry` geven 404, `/trips/{tid}/wayPoints` geeft 500
(fout in de database van PSA). De lijst met ritten begint bij de oudste rit; `_links.last` wijst naar de nieuwste.

Deze app leest de ritten daarom rauw via flobz' sessie (`psa_bridge.get_trips`). Een update zou de specificatie opnieuw
genereren of in elk geval het tripmodel bijwerken.

## `OauthAPIClient.call_api` geeft `None` na een tokenverversing

`psa/oauth.py`, `OauthAPIClient.call_api`: de `return None` staat binnen de `for attempt in range(0, 2)`-lus. Als de
eerste poging een 401 geeft en de token ververst wordt, keert de functie terug met `None` in plaats van het verzoek een
tweede keer te doen. (De nieuwe token zou bovendien nog in `configuration.access_token` gezet moeten worden; `PSAClient.api()`
doet dat alleen bij het aanmaken.)

Gevolg: `PSAClient.get_vehicles()` crasht met `AttributeError: 'NoneType' object has no attribute 'embedded'`.
PSA geeft vlak na het uitgeven van een nieuwe token soms toch 401; in een vers proces gebeurde dat ongeveer één op de drie keer,
zodat de app bij het opstarten geen auto kon laden. (`get_vehicle_info` heeft er geen last van: die probeert zelf twee keer.)

**Omzeiling in deze app, weghalen zodra dit in flobz is opgelost:** `psa_bridge.get_vehicles()` roept
`get_vehicles()` bij deze `AttributeError` eenmaal opnieuw aan. Een pull request zou de `return None` uit de lus halen,
zodat de tweede poging echt plaatsvindt, en daarbij de nieuwe token in `configuration.access_token` zetten.

## Remote token: verse toegangstoken wordt geweigerd, tokenlimiet raakt snel op

`RemoteClient._refresh_remote_token()` roept bij elke verversing van de remote token eerst
`manager.refresh_token_now()` aan en gebruikt de nieuwe toegangstoken meteen. PSA weigert een gloednieuwe
toegangstoken soms nog een paar seconden (`401` met "Cannot pass the security checks that are required by the
target API"), hetzelfde verschijnsel als bij `call_api` hierboven. Dan:

1. mislukt het verversen met de remote refresh token ("can't refresh_remote_token … Create a new one");
2. valt flobz terug op een nieuwe OTP-code (er zijn er maar ongeveer 6 per dag), die met dezelfde toegangstoken ook 401 geeft
   ("Can't refresh remote token, please redo otp procedure");
3. is de limiet van `refresh_token_now` (6 per 30 minuten) na een paar van zulke rondes op, en mislukt elke volgende
   `publish()` met "Rate limit exceeded for refresh_token_now".

Gezien op 4 november 2026: binnen 15 seconden na het starten van de app vijf keer "access token refreshed", en binnen
een minuut was de limiet op. Bovendien melden de commando's (`wakeup`, `preconditioning`, `lights`, …) succes terug,
ook als `publish()` niets verstuurd heeft.

Daarbij slaat de cache van `_refresh_remote_token` (`MQTT_TOKEN_TTL`) vaak niet aan: die kijkt naar
`remoteCredentials.last_update`, en dat wordt alleen bijgewerkt als PSA een nieuwe remote refresh token teruggeeft. Wat
flobz na een geslaagde verversing wel bijhoudt (`remote_token_last_update`) gebruikt die controle niet. Zo kost elke
`publish()` een `refresh_token_now()`.

Ideeën voor een pull request: de toegangstoken alleen verversen als die verlopen is (of bij een 401), de TTL-controle op
`remote_token_last_update` baseren, na een verse token kort wachten of één keer opnieuw proberen voordat de OTP-route
gekozen wordt, en `publish()`'s resultaat doorgeven vanuit de commando's.

**In deze app:** `psa_bridge` omwikkelt `RemoteClient.publish()` om het resultaat te zien (flobz' gedrag verandert niet),
en meldt een fout als een commando niet verstuurd is. Een eerdere versie controleerde de remote token vóór elk commando
met `_refresh_remote_token()`; door de niet-werkende cache kostte dat een extra tokenverversing per commando.

Let op bij het testen: meerdere processen met dezelfde `config.json` en `otp.bin` (de app, een ontwikkelkopie, losse
scripts) roteren elkaars remote refresh token en laten de OTP-teller uit de pas lopen. Gebruik er één tegelijk.

## `RemoteClient.start()` wekt de auto meteen

`start()` roept `__keep_mqtt()` aan, en die stuurt direct een wake-up naar de eerste auto (daarna elke 8 uur), om het
remote token vers te houden. Geen fout van flobz, maar wel iets om rekening mee te houden. Stuurt een client vlak daarna
zelf een wake-up, dan weigert PSA die met `return_code` 502, `reason` `duplicate.message.key`. De eerste wake-up loopt
gewoon door en levert een statusbericht op.

**In deze app:** `psa_bridge` zet ook de verzonden verzoeken in de lijst met MQTT-berichten, zodat de app de wake-ups
van flobz toont als "Status opvragen (automatisch)". `psa_bridge.wakeup()` stuurt geen eigen wake-up als het opzetten
van de verbinding er al een verstuurde.

## `RemoteClient.horn()` verstuurt niets

`horn()` roept `self.mqtt_client.publish(msg)` aan met het `MQTTRequest`-object, in plaats van `self.publish(msg)`
zoals de andere commando's. paho kan dat object niet versturen.

## `_fix_not_updated_api` slaat aan zonder dat er geladen wordt

Bij elk MQTT-statusbericht met `charging_state.remaining_time` ≠ 0 en een serverstatus die niet `InProgress` is,
wacht flobz 60 seconden (in de MQTT-thread) en stuurt een extra wake-up. Bij deze auto meldde MQTT `remaining_time: 635`
terwijl de auto niet aan de stekker stond (waarschijnlijk de tijd tot het uitgestelde laden), dus dit gebeurt na elk
statusbericht.

Omdat de wake-up zelf weer een statusbericht oplevert, is het een kringloop: elke minuut een wake-up en een
tokenverversing. Gezien op 4 november 2026: 21:42 statusbericht, 21:43 wake-up en statusbericht, 21:44 wake-up, …;
binnen 6 minuten na het starten was de limiet van `refresh_token_now` (6 per 30 minuten) op en mislukten alle commando's
van de gebruiker. Elke wake-up maakt bovendien de auto wakker (12V-accu).

Idee voor een pull request: de voorwaarde laten kijken of er echt geladen wordt (`rate` ≠ 0, of `cable_detected`/`plugged`)
in plaats van alleen `remaining_time`, en hoogstens één extra wake-up per laadsessie sturen.

**Omzeiling in deze app, weghalen zodra dit in flobz is opgelost:** `psa_bridge` vervangt `_fix_not_updated_api` op de
remote client van de app door een functie die niets doet. Gevolg: na het inpluggen kan de serverstatus wat later
"laden" tonen; de wake-ups en tokenverversingen gaan alleen nog naar acties van de gebruiker.
