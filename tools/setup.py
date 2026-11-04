"""One-time setup on the desktop: client credentials and customer id into data/config.json.

Usage: .venv/bin/python tools/setup.py [country code], e.g. NL. Stop the server first, it rewrites config.json.
Runs psa_car_controller's own InitialSetup: it downloads the MyCitroën APK, takes the client credentials from it
and logs in with your MyCitroën e-mail address and password to look up the customer id that MQTT needs.
The password is only sent to the MyCitroën login server and is not stored.
"""
import getpass
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.append(str(ROOT / "stubs"))

from psa_car_controller.psa.constants import BRAND  # noqa: E402
from psa_car_controller.psa.setup.app_decoder import InitialSetup  # noqa: E402

PACKAGE_NAME = "com.psa.mym.mycitroen"
DATA_DIR = ROOT / "data"
CONFIG_FILE = DATA_DIR / "config.json"


def main() -> None:
    country_code = (sys.argv[1] if len(sys.argv) > 1 else "NL").upper()
    email = input("MyCitroën e-mail address: ").strip()
    password = getpass.getpass("MyCitroën password: ")
    # InitialSetup downloads the APK and writes the app's client certificate to certs/ in the working directory.
    work_dir = DATA_DIR / "setup"
    work_dir.mkdir(parents=True, exist_ok=True)
    os.chdir(work_dir)
    setup = InitialSetup(PACKAGE_NAME, email, password, country_code)
    if CONFIG_FILE.is_file():
        config = json.loads(CONFIG_FILE.read_text())
    else:
        config = {"refresh_token": None, "remote_refresh_token": None}
    config.update(
        client_id=setup.client_id,
        client_secret=setup.client_secret,
        customer_id=setup.customer_id,
        realm=BRAND[PACKAGE_NAME]["realm"],
        country_code=country_code,
    )
    descriptor = os.open(CONFIG_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as file:
        json.dump(config, file, indent=4)
    print(f"Saved client credentials and customer id {setup.customer_id} to {CONFIG_FILE}")


if __name__ == "__main__":
    main()
