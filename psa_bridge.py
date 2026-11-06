"""Wrapper around an unmodified psa_car_controller release.

These functions are what the Sailfish app will call through PyOtherSide; they only return plain dicts, lists and strings.
"""
import json
import logging
import os
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parent / "stubs"))

from psa_car_controller.psa.otp.otp import new_otp_session  # noqa: E402
from psa_car_controller.psa.RemoteClient import RemoteClient  # noqa: E402
from psa_car_controller.psacc.application.charge_control import ChargeControl  # noqa: E402
from psa_car_controller.psacc.application.psa_client import PSAClient  # noqa: E402

CONFIG_FILE = "config.json"
OTP_FILE = "otp.bin"
API_BASE_URL = "https://api.groupe-psa.com/connectedcar/v4"
MQTT_CONNECT_TIMEOUT = 20
WAKEUP_TOPIC = "/VehCharge/state"

_client: PSAClient | None = None
_remote_messages: list[dict] = []
_publish_result = threading.local()
_charge_control: ChargeControl | None = None
_charge_control_lock = threading.Lock()


def init(data_dir: str, log_file: str | None = None) -> None:
    """Loads the client from data_dir/config.json; data_dir becomes the working directory,
    because psa_car_controller keeps config.json, cars.json and otp.bin in the current directory.
    With log_file, the log of this session (INFO and up) is written to that file in data_dir."""
    global _client
    # psa_car_controller writes otp.bin and cars.json with the default mode, readable by every user.
    os.umask(0o077)
    os.makedirs(data_dir, exist_ok=True)
    os.chdir(data_dir)
    if log_file is not None:
        handler = logging.FileHandler(log_file, mode="w")
        handler.setFormatter(logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s"))
        logging.getLogger().addHandler(handler)
        logging.getLogger().setLevel(logging.INFO)
    _client = None
    if os.path.isfile(CONFIG_FILE):
        _client = PSAClient.load_config(CONFIG_FILE)
        _client.manager.refresh_callbacks.append(_client.save_config)


def is_configured() -> bool:
    return _client is not None


def is_connected() -> bool:
    return _client is not None and _client.manager.refresh_token is not None


def has_customer_id() -> bool:
    """True when tools/setup.py has stored the customer id that MQTT needs."""
    return _client is not None and _client.customer_id is not None


def is_remote_activated() -> bool:
    """True when this installation has an OTP session (otp.bin), so it can send commands."""
    return os.path.isfile(OTP_FILE)


def get_session() -> dict:
    """The setup state in one call, for the user interface."""
    return {
        "configured": is_configured(),
        "connected": is_connected(),
        "hasCustomerId": has_customer_id(),
        "remoteActivated": is_remote_activated(),
    }


def _configured_client() -> PSAClient:
    if _client is None:
        raise RuntimeError("Geen config.json; maak die eerst met tools/setup.py op de desktop")
    return _client


def _connected_client() -> PSAClient:
    client = _configured_client()
    if client.manager.refresh_token is None:
        raise RuntimeError("Niet ingelogd")
    # After a restart only the refresh token is known; the generated API client cannot do without an access token.
    if client.manager.access_token is None and not client.manager.refresh_token_now():
        raise RuntimeError("Kan de toegang tot PSA niet vernieuwen; log opnieuw in")
    return client


def start_login() -> str:
    """Starts a login and returns the URL of the brand's login page."""
    return _configured_client().manager.generate_redirect_url()


def finish_login(code: str) -> None:
    """Completes the login with the code from the <scheme>://oauth2redirect redirect."""
    client = _configured_client()
    client.connect(code)
    client.save_config()


def logout() -> None:
    client = _configured_client()
    client.manager.refresh_token = None
    client.save_config()


def get_vehicles() -> list[dict]:
    client = _connected_client()
    try:
        cars = client.get_vehicles()
    except AttributeError:
        # psa_car_controller 3.7.10 gets None instead of a retry after a 401 plus token refresh; see docs/flobz-notes.md.
        cars = client.get_vehicles()
    return [car.to_dict() for car in cars]


def get_status(vin: str) -> dict:
    client = _connected_client()
    status = client.get_vehicle_info(vin)
    if status is None:
        raise RuntimeError(f"Geen status beschikbaar voor {vin}")
    return client.api().api_client.sanitize_for_serialization(status)


def api_get(path: str) -> dict:
    """Raw GET on the API, for exploring endpoints psa_car_controller has no method for."""
    client = _connected_client()
    start = time.monotonic()
    response = client.manager.get(
        API_BASE_URL + path,
        params={"client_id": client.client_id},
        headers={
            "x-introspect-realm": client.realm,
            # lastPosition answers with GeoJSON instead of HAL.
            "Accept": "application/vnd.geo+json" if path.split("?")[0].endswith("/lastPosition") else "application/hal+json",
        },
    )
    try:
        body = response.json()
    except ValueError:
        body = response.text
    return {
        "path": path,
        "status": response.status_code,
        "durationMs": round((time.monotonic() - start) * 1000),
        "body": body,
    }


def _get_json(path: str) -> dict:
    result = api_get(path)
    if result["status"] != 200:
        raise RuntimeError(f"De server van PSA gaf HTTP {result['status']} op {path.split('?')[0]}")
    return result["body"]


def get_trips(vin: str, page: str | None = None) -> dict:
    """Trips of the car, newest first, one page at a time: {"trips": [...], "older": page or None}.
    Without page it returns the newest page; pass "older" to get the trips before those.
    Read raw, because the trip model in psa_car_controller predates the current API (see docs/flobz-notes.md).
    The API lists the oldest trips first, so this starts at the last page and goes back."""
    if page is None:
        vehicle_id = _connected_client().vehicles_list.get_car_by_vin(vin).vehicle_id
        links = _get_json(f"/user/vehicles/{vehicle_id}/trips")["_links"]
        page = links.get("last", links["self"])["href"]
    body = _get_json(page.removeprefix(API_BASE_URL))
    older = body["_links"].get("prev")
    return {
        "trips": list(reversed(body.get("_embedded", {}).get("trips", []))),
        "older": older["href"] if older else None,
    }


def _decode_payload(payload: bytes):
    try:
        return json.loads(payload)
    except ValueError:
        return payload.decode(errors="replace")


def _recording(handler):
    """Wraps the MQTT message handler of psa_car_controller so the app can show the responses too."""

    def on_message(client, userdata, message):
        _remote_messages.append({
            "time": datetime.now().isoformat(timespec="seconds"),
            "topic": message.topic,
            "payload": _decode_payload(message.payload),
        })
        handler(client, userdata, message)

    return on_message


def _remote_client() -> RemoteClient:
    """Returns the remote client with a live MQTT connection, starting it on first use.
    paho silently drops a message published while not connected, so this waits for the connection."""
    client = _connected_client()
    remote = client.remote_client
    if remote.mqtt_client is None:
        if client.customer_id is None:
            raise RuntimeError("Geen customer id in config.json; maak die met tools/setup.py op de desktop")
        # Switched off: with this car it sends a wakeup after every state message, which brings the next state
        # message, and so uses up the token refresh limit within minutes. See docs/flobz-notes.md.
        remote._fix_not_updated_api = lambda charge_info, vin: None
        # Wrapped before start(), which already sends a wake-up (psa_car_controller's keep-alive); only once, because
        # this block runs again after a failed start or a new activation.
        if "publish" not in vars(remote):
            remote.publish = _recording_publish(remote.publish)
        remote.start()
        if remote.mqtt_client is None:
            raise RuntimeError("Commando's zijn nog niet geactiveerd; vraag een sms-code aan en activeer")
        remote.mqtt_client.on_message = _recording(remote.mqtt_client.on_message)
    deadline = time.monotonic() + MQTT_CONNECT_TIMEOUT
    while not remote.mqtt_client.is_connected() and time.monotonic() < deadline:
        time.sleep(0.5)
    if not remote.mqtt_client.is_connected():
        raise RuntimeError("Geen verbinding met de MQTT-server van PSA; probeer het zo opnieuw")
    return remote


def _recording_publish(publish):
    """Wraps RemoteClient.publish() to keep its result for the calling thread: the commands of psa_car_controller
    ignore it, so a command that could not be sent (no remote token) would otherwise look like a success.
    Sent requests are added to the MQTT messages (marked outgoing, without the token), so the app also sees the
    wake-ups psa_car_controller sends of its own accord."""

    def wrapper(mqtt_request, store=True):
        result = publish(mqtt_request, store)
        _publish_result.ok = result
        if result:
            _remote_messages.append({
                "time": datetime.now().isoformat(timespec="seconds"),
                "sentAt": time.time() * 1000,
                "outgoing": True,
                "topic": mqtt_request.topic,
                "payload": {"vin": mqtt_request.vin, "req_parameters": mqtt_request.req_parameters},
            })
        return result

    return wrapper


def _sent(command) -> None:
    """Runs a command of psa_car_controller and raises when the publish() it did failed."""
    _publish_result.ok = None
    command()
    if _publish_result.ok is False:
        raise RuntimeError("Het commando is niet verstuurd: psa_car_controller kreeg geen remote token (vaak zijn "
                           "limiet van 6 tokenverversingen per 30 minuten); probeer het later opnieuw, de log van "
                           "de app vermeldt de oorzaak")


def request_sms() -> None:
    """Asks PSA to send an activation code by SMS to the phone number of the account."""
    _connected_client().remote_client.get_sms_otp_code()


def activate_remote(sms_code: str, pin: str) -> None:
    """Registers this installation for remote control with the SMS code and the PIN of the official app."""
    client = _connected_client()
    remote = client.remote_client
    remote.otp = new_otp_session(sms_code, pin, remote.otp)
    client.save_config()
    if remote.mqtt_client is not None:
        remote.stop()
        remote.mqtt_client = None
    _remote_client()


def get_remote_messages(since: int = 0) -> list[dict]:
    """MQTT messages received since the given index; PyOtherSide passes JavaScript numbers as floats."""
    return _remote_messages[int(since):]


def wakeup(vin: str) -> None:
    """Asks the car to send a fresh status; limited by psa_car_controller to 6 per 20 minutes.
    Setting up the MQTT connection already wakes the car (psa_car_controller's keep-alive). PSA refuses a second
    request right after it with 502 duplicate.message.key, so none is sent when one went out during this call."""
    already_known = len(_remote_messages)
    remote = _remote_client()
    if not any(message.get("outgoing") and message["payload"]["vin"] == vin and message["topic"].endswith(WAKEUP_TOPIC)
               for message in _remote_messages[already_known:]):
        _sent(lambda: remote.wakeup(vin))


def preconditioning(vin: str, activate: bool) -> None:
    """Refused until an MQTT state message has brought the car's programs: psa_car_controller always sends
    all four programs along, and without known ones it sends its defaults, which wipes the programs in the car."""
    remote = _remote_client()
    if vin not in remote.precond_programs:
        raise RuntimeError("De voorverwarmprogramma's van de auto zijn nog niet bekend; vraag eerst de status op bij de auto")
    _sent(lambda: remote.preconditioning(vin, activate))


def _program(program: dict) -> dict:
    """A preconditioning program in the car's format; PyOtherSide passes JavaScript numbers as floats."""
    result = {
        "day": [int(day) for day in program["day"]],
        "hour": int(program["hour"]),
        "minute": int(program["minute"]),
        "on": int(program["on"]),
    }
    # Hour 34 and minute 7 mark a program that is not set.
    if len(result["day"]) != 7 or not (0 <= result["hour"] <= 23 or result["hour"] == 34) or not 0 <= result["minute"] <= 59:
        raise RuntimeError(f"Ongeldig voorverwarmprogramma: {result}")
    return result


def set_preconditioning_programs(vin: str, programs: dict, activate: bool) -> None:
    """Sends changed preconditioning programs (program1…program4) to the car. psa_car_controller has no call for this:
    its preconditioning() sends the programs it keeps from the car's last state message, together with "asap"
    (start or stop now). So those are replaced first; activate is the "asap" to send along."""
    remote = _remote_client()
    if vin not in remote.precond_programs:
        raise RuntimeError("De voorverwarmprogramma's van de auto zijn nog niet bekend; vraag eerst de status op bij de auto")
    remote.precond_programs[vin] = {key: _program(program) for key, program in programs.items()}
    _sent(lambda: remote.preconditioning(vin, activate))


def charge_now(vin: str, start: bool) -> None:
    """Starts charging now, or goes back to the delayed charging time; needs a loaded status."""
    remote = _remote_client()
    if _connected_client().vehicles_list.get_car_by_vin(vin).status is None:
        get_status(vin)
    _sent(lambda: remote.charge_now(vin, start))


def _run_charge_control() -> None:
    # Skipped when the previous run is still waiting for its acknowledgement (that takes a minute).
    if _charge_control_lock.acquire(blocking=False):
        try:
            _charge_control.process()
        finally:
            _charge_control_lock.release()


def check_charge_limit(vin: str, percentage: int) -> dict:
    """Charge limit through psa_car_controller's ChargeControl; call it every few minutes while a limit is set.
    Fetches a fresh server status (no wake-up of the car) and returns it. When the car charges and the battery has
    reached percentage, ChargeControl stops the charge; when the limit is already reached shortly before delayed
    charging starts, it moves the car's charge start time. percentage 100 means no limit."""
    global _charge_control
    client = _connected_client()
    status = client.get_vehicle_info(vin)
    if status is None:
        raise RuntimeError(f"Geen status beschikbaar voor {vin}")
    if int(percentage) < 100:
        # ChargeControl sends its commands through the remote client, which needs the MQTT connection.
        _remote_client()
        if _charge_control is None or _charge_control.vin != vin:
            _charge_control = ChargeControl(client, vin, 100, None)
        _charge_control.percentage_threshold = int(percentage)
        threading.Thread(target=_run_charge_control, daemon=True).start()
    return client.api().api_client.sanitize_for_serialization(status)


def lights(vin: str) -> None:
    """Flashes the lights; the car always does this for about 10 seconds."""
    remote = _remote_client()
    _sent(lambda: remote.lights(vin, 10))


def lock_door(vin: str, lock: bool) -> None:
    remote = _remote_client()
    _sent(lambda: remote.lock_door(vin, lock))
