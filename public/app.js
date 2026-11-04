const byId = (id, type) => {
  const element = document.getElementById(id);
  if (!(element instanceof type)) {
    throw new Error(`Element #${id} is not a ${type.name}`);
  }
  return element;
};

const errorBox = byId('error', HTMLParagraphElement);
const logoutButton = byId('logout', HTMLButtonElement);
const setupSection = byId('setup', HTMLElement);
const connectSection = byId('connect', HTMLElement);
const openLoginButton = byId('open-login', HTMLButtonElement);
const vehiclesSection = byId('vehicles', HTMLElement);
const vehicleList = byId('vehicle-list', HTMLUListElement);
const statusSection = byId('status', HTMLElement);
const refreshButton = byId('refresh', HTMLButtonElement);
const statusList = byId('status-list', HTMLDListElement);
const remoteSection = byId('remote', HTMLElement);
const remoteSetup = byId('remote-setup', HTMLParagraphElement);
const remoteActivate = byId('remote-activate', HTMLDivElement);
const requestSmsButton = byId('request-sms', HTMLButtonElement);
const activateForm = byId('activate-form', HTMLFormElement);
const remoteCommands = byId('remote-commands', HTMLDivElement);
const explorerSection = byId('explorer', HTMLElement);
const explorerForm = byId('explorer-form', HTMLFormElement);
const logSection = byId('log', HTMLElement);
const logList = byId('log-list', HTMLDivElement);

let session = null;
let vehicles = [];
let selectedVin = null;
let remoteMessageCount = 0;

const fetchJson = async (url, init) => {
  const response = await fetch(url, init);
  if (!response.ok) {
    throw new Error(await response.text());
  }
  return response.json();
};

const postJson = (url, body = {}) =>
  fetchJson(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

const run = async (action) => {
  errorBox.hidden = true;
  try {
    await action();
  } catch (error) {
    errorBox.textContent = error instanceof Error ? error.message : String(error);
    errorBox.hidden = false;
  }
};

/** Adds a response to the log, newest on top and opened. */
const addToLog = (title, body) => {
  const details = document.createElement('details');
  const summary = document.createElement('summary');
  const pre = document.createElement('pre');
  summary.textContent = title;
  pre.textContent = typeof body === 'string' ? body : JSON.stringify(body, null, 2);
  details.append(summary, pre);
  details.open = true;
  for (const previous of logList.querySelectorAll('details')) {
    previous.open = false;
  }
  logList.prepend(details);
  logSection.hidden = false;
};

/** Fetches the result of a psa_bridge function and logs it. */
const bridgeGet = async (call, url) => {
  const result = await fetchJson(url);
  addToLog(`psa_bridge.${call}`, result);
  return result;
};

const text = (value, unit = '') => (value === undefined || value === null ? '—' : `${value}${unit}`);

const yesNo = (value) => {
  if (value === undefined || value === null) {
    return '—';
  }
  return value ? 'ja' : 'nee';
};

const dateTime = (value) => (value === undefined || value === null ? '—' : new Date(value).toLocaleString('nl-NL'));

/** Formats an ISO 8601 duration such as PT2H15M. */
const duration = (value) => {
  const match = typeof value === 'string' ? value.match(/^PT(?:(\d+)H)?(?:(\d+)M)?/) : null;
  if (match === null) {
    return text(value);
  }
  return `${match[1] ?? 0} u ${match[2] ?? 0} min`;
};

/** GeoJSON coordinates are [longitude, latitude]. */
const positionLink = (coordinates) => {
  const [longitude, latitude] = Array.isArray(coordinates) ? coordinates : [];
  if (typeof longitude !== 'number' || typeof latitude !== 'number') {
    return '—';
  }
  const link = document.createElement('a');
  link.href = `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=17/${latitude}/${longitude}`;
  link.target = '_blank';
  link.textContent = `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`;
  return link;
};

const renderStatus = (status) => {
  const electric = status.energy?.find((energy) => energy.type === 'Electric');
  const charging = electric?.charging;
  const rows = [
    ['Batterij', 'energy[Electric].level', text(electric?.level, ' %')],
    ['Actieradius', 'energy[Electric].autonomy', text(electric?.autonomy, ' km')],
    ['Stekker erin', 'energy[Electric].charging.plugged', yesNo(charging?.plugged)],
    ['Laadstatus', 'energy[Electric].charging.status', text(charging?.status)],
    ['Resterende laadtijd', 'energy[Electric].charging.remainingTime', duration(charging?.remainingTime)],
    ['Laadsnelheid', 'energy[Electric].charging.chargingRate', text(charging?.chargingRate)],
    ['Laadmodus', 'energy[Electric].charging.chargingMode', text(charging?.chargingMode)],
    ['Uitgesteld laden', 'energy[Electric].charging.nextDelayedTime', text(charging?.nextDelayedTime)],
    ['Accugezondheid', 'energy[Electric].battery.health.capacity', text(electric?.battery?.health?.capacity)],
    ['Kilometerstand', 'odometer.mileage', text(status.odometer?.mileage, ' km')],
    ['Vergrendeling', 'doorsState.lockedState', text(status.doorsState?.lockedState?.join(', '))],
    ['Contact', 'ignition.type', text(status.ignition?.type)],
    ['Rijdt', 'kinetic.moving', yesNo(status.kinetic?.moving)],
    ['Voorverwarming', 'preconditioning.airConditioning.status', text(status.preconditioning?.airConditioning?.status)],
    ['Buitentemperatuur', 'environment.air.temp', text(status.environment?.air?.temp, ' °C')],
    ['Positie', 'lastPosition.geometry.coordinates', positionLink(status.lastPosition?.geometry?.coordinates)],
    ['Bijgewerkt', 'energy[Electric].updatedAt', dateTime(electric?.updatedAt)],
  ];
  statusList.replaceChildren(
    ...rows.flatMap(([label, field, value]) => {
      const term = document.createElement('dt');
      const fieldName = document.createElement('small');
      const description = document.createElement('dd');
      fieldName.textContent = field;
      term.append(label, fieldName);
      description.append(value);
      return [term, description];
    }),
  );
  statusSection.hidden = false;
};

const loadStatus = async () => {
  renderStatus(await bridgeGet(`get_status("${selectedVin}")`, `/api/vehicles/${selectedVin}/status`));
};

const selectVehicle = async (vin) => {
  selectedVin = vin;
  for (const button of vehicleList.querySelectorAll('button')) {
    button.setAttribute('aria-pressed', String(button.dataset.vin === vin));
  }
  remoteSection.hidden = false;
  remoteSetup.hidden = session.hasCustomerId;
  remoteActivate.hidden = !session.hasCustomerId || session.remoteActivated;
  remoteCommands.hidden = !session.hasCustomerId || !session.remoteActivated;
  explorerSection.hidden = false;
  await loadStatus();
};

const loadVehicles = async () => {
  vehicles = await bridgeGet('get_vehicles()', '/api/vehicles');
  vehicleList.replaceChildren(
    ...vehicles.map((vehicle) => {
      const item = document.createElement('li');
      const button = document.createElement('button');
      button.type = 'button';
      button.dataset.vin = vehicle.vin;
      button.textContent = `${vehicle.label ?? vehicle.brand ?? 'Auto'} · ${vehicle.vin}`;
      button.addEventListener('click', () => run(() => selectVehicle(vehicle.vin)));
      item.append(button);
      return item;
    }),
  );
  vehiclesSection.hidden = false;
  if (vehicles.length > 0) {
    await selectVehicle(selectedVin ?? vehicles[0].vin);
  }
};

const render = async () => {
  session = await fetchJson('/api/session');
  setupSection.hidden = session.configured;
  connectSection.hidden = !session.configured || session.connected;
  logoutButton.hidden = !session.connected;
  for (const section of [vehiclesSection, statusSection, remoteSection, explorerSection]) {
    section.hidden = true;
  }
  if (session.connected) {
    await loadVehicles();
  }
};

openLoginButton.addEventListener('click', () =>
  run(async () => {
    const { url } = await postJson('/api/login/start');
    window.open(url, '_blank');
  }),
);

logoutButton.addEventListener('click', () =>
  run(async () => {
    await postJson('/api/logout');
    selectedVin = null;
    await render();
  }),
);

refreshButton.addEventListener('click', () => run(loadStatus));

requestSmsButton.addEventListener('click', () =>
  run(async () => {
    await postJson('/api/remote/sms');
    addToLog('psa_bridge.request_sms()', 'Sms aangevraagd');
  }),
);

activateForm.addEventListener('submit', (event) => {
  event.preventDefault();
  run(async () => {
    const form = new FormData(activateForm);
    await postJson('/api/remote/activate', { smsCode: form.get('smsCode'), pin: form.get('pin') });
    activateForm.reset();
    addToLog('psa_bridge.activate_remote()', 'Geactiveerd');
    await render();
  });
});

for (const button of remoteCommands.querySelectorAll('button')) {
  button.addEventListener('click', () =>
    run(async () => {
      const { command, on } = button.dataset;
      await postJson(`/api/vehicles/${selectedVin}/${command}`, { on: on !== 'false' });
      addToLog(`${button.textContent}: verstuurd`, { vin: selectedVin, command, on: on !== 'false' });
    }),
  );
}

/** Picks up MQTT messages while remote control is available. */
setInterval(() => {
  if (remoteCommands.hidden) {
    return;
  }
  run(async () => {
    const messages = await fetchJson(`/api/remote/messages?since=${remoteMessageCount}`);
    remoteMessageCount += messages.length;
    for (const message of messages) {
      addToLog(`MQTT ${message.time} ${message.topic}`, message.payload);
    }
  });
}, 3000);

explorerForm.addEventListener('submit', (event) => {
  event.preventDefault();
  run(async () => {
    const vehicleId = vehicles.find((vehicle) => vehicle.vin === selectedVin)?.vehicle_id ?? '';
    const path = String(new FormData(explorerForm).get('path')).trim().replaceAll('{id}', vehicleId);
    const result = await fetchJson(`/api/psa${path.startsWith('/') ? path : `/${path}`}`);
    addToLog(`GET ${result.path} → ${result.status} (${result.durationMs} ms)`, result.body);
  });
});

run(render);
