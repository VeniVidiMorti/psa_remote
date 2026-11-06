import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import Nemo.KeepAlive 1.2
import io.thp.pyotherside 1.5
import "pages"

ApplicationWindow {
    id: app

    /** Data directory handed to psa_bridge; holds config.json, cars.json and otp.bin. */
    property string dataDir: StandardPaths.data
    /** True once psa_bridge has been imported and initialised. Default false. */
    property bool ready: false
    /** Result of psa_bridge.get_session(): configured, connected, hasCustomerId, remoteActivated. Default null. */
    property var session: null
    /** VIN of the car shown; the first one of get_vehicles(). Default empty. */
    property string vin: ""
    /** Last result of psa_bridge.get_status(vin). Default null. */
    property var status: null
    /** The "Electric" entry of status.energy. Default null. */
    property var electric: {
        var energies = status && status.energy ? status.energy : []
        for (var i = 0; i < energies.length; i++) {
            if (energies[i].type === "Electric") {
                return energies[i]
            }
        }
        return null
    }
    /** charging_state of the last MQTT state message of the car. Default null. */
    property var liveCharging: null
    /** Time the car reported liveCharging (ISO, UTC). Default empty. */
    property string liveDate: ""
    /** Battery level, range, time and source ("auto" or "server") of the newest of the car's state message and the server status. Default null. */
    property var current: {
        var fromCar = liveCharging ? { level: liveCharging.soc_batt, range: liveCharging.autonomy_zev, time: liveDate, source: "auto" } : null
        var fromServer = electric ? { level: electric.level, range: electric.autonomy, time: electric.updatedAt, source: "server" } : null
        if (fromCar && (!fromServer || Date.parse(fromCar.time) >= Date.parse(fromServer.time))) {
            return fromCar
        }
        return fromServer
    }
    /** Last Python error, shown on the main page. Default empty. */
    property string error: ""
    /** True while a call to psa_bridge is running. Default false. */
    property bool busy: false
    /** True when starting up failed: psa_bridge, the session or (when logged in) the car could not be loaded. Default false. */
    property bool startupFailed: error !== "" && !busy && (!ready || session === null || (session.connected && vin === ""))
    /** Number of MQTT messages already fetched from get_remote_messages(). Default 0. */
    property int remoteMessageCount: 0
    /** Name of the last command sent, e.g. "Status opvragen". Default empty. */
    property string commandLabel: ""
    /** Progress or outcome of that command in words. Default empty. */
    property string commandProgress: ""
    /** True from sending a command until the car has answered, an error occurred or the wait timed out. Default false. */
    property bool commandActive: false
    /** Time the last command was sent, in milliseconds since 1970. Default 0. */
    property double commandSentAt: 0
    /** True when commands can be sent: logged in, customer id known and remote control activated. Default false. */
    property bool remoteReady: session !== null && session.connected && session.hasCustomerId && session.remoteActivated
    /** Charge limit in percent; 100 means no limit (charge full). Remembered in dconf. Default 100. */
    property int chargeLimit: chargeLimitSetting.value
    /** True while the server reports that the car is charging. Default false. */
    property bool charging: electric !== null && electric.charging !== undefined && electric.charging.status === "InProgress"
    /** Time (HH:mm) of the last charge limit check. Default empty. */
    property string chargeLimitChecked: ""

    function setChargeLimit(percentage) {
        chargeLimitSetting.value = percentage
    }

    /** Preconditioning programs from the car's last MQTT state message: program1…program4 with hour, minute, on, day. Default null. */
    property var preconditioningPrograms: null
    /** Time the car reported preconditioningPrograms (ISO, UTC). Default empty. */
    property string preconditioningProgramsDate: ""
    /** status.preconditioning.airConditioning: status (Enabled, Disabled, Finished, Failure), failureCause, updatedAt. Default null. */
    property var preconditioning: status && status.preconditioning ? status.preconditioning.airConditioning : null

    /** Sends a remote command for the current car and follows its progress through the MQTT messages. */
    function sendCommand(label, name, args) {
        startCommand(label, "verbinden…", Date.now())
        bridge(name, [vin].concat(args || []), function() {
            if (commandActive) {
                commandProgress = "verstuurd, wachten op de auto…"
            }
        })
    }

    function startCommand(label, progress, sentAt) {
        commandLabel = label
        commandProgress = progress
        commandActive = true
        commandSentAt = sentAt
        commandTimeout.restart()
    }

    function finishCommand(outcome) {
        commandProgress = outcome
        commandActive = false
        commandTimeout.stop()
    }

    /** Progress messages of PSA's remote services, by process_code. */
    function processText(code, message) {
        var texts = {
            "900": "verzoek aangenomen…",
            "901": "auto slaapt, wordt gewekt…",
            "903": "doorgestuurd naar de auto…"
        }
        return texts[code] || message || ("code " + code)
    }

    function handleRemoteMessage(message) {
        var payload = message.payload
        if (!payload) {
            return
        }
        if (message.outgoing) {
            // psa_car_controller also wakes the car of its own accord: when the MQTT connection starts, every 8 hours,
            // and from the charge limit. Followed like the user's own request, unless it is older than the wait.
            if (!commandActive && payload.vin === vin && /\/VehCharge\/state$/.test(message.topic)
                    && Date.now() - message.sentAt < commandTimeout.interval) {
                startCommand("Status opvragen (automatisch)", "verstuurd, wachten op de auto…", message.sentAt)
            }
        } else if (payload.charging_state && payload.vin === vin) {
            liveCharging = payload.charging_state
            liveDate = payload.date || message.time
            if (payload.precond_state && payload.precond_state.programs) {
                preconditioningPrograms = payload.precond_state.programs
                preconditioningProgramsDate = liveDate
            }
            // Only a state the car measured after the command (10 s margin for clock differences) answers it;
            // psa_car_controller also requests states of its own, and those can be older.
            if (commandActive && Date.parse(liveDate) >= commandSentAt - 10000) {
                finishCommand("klaar, status ontvangen om " + message.time.substring(11, 16))
                loadStatus()
            }
        } else if (payload.process_code && commandActive) {
            commandProgress = processText(payload.process_code, payload.process_message)
        } else if (payload.return_code === "0" && commandActive) {
            finishCommand("klaar, bevestigd door de auto om " + message.time.substring(11, 16))
            loadStatus()
        } else if (payload.return_code && payload.return_code !== "0" && payload.return_code !== "400" && commandActive) {
            // 400 means an expired token, which psa_car_controller handles by sending the request again.
            finishCommand("fout " + payload.return_code + (payload.reason ? ": " + payload.reason : ""))
        }
    }

    /** Calls a psa_bridge function and passes its result to callback; PyOtherSide also calls back after a Python error, with undefined. */
    function bridge(name, args, callback) {
        busy = true
        error = ""
        python.call("psa_bridge." + name, args, function(result) {
            busy = false
            if (callback) {
                callback(result)
            }
        })
    }

    function loadStatus() {
        bridge("get_status", [vin], function(result) {
            if (result) {
                status = result
            }
        })
    }

    function loadVehicles() {
        bridge("get_vehicles", [], function(vehicles) {
            if (vehicles && vehicles.length > 0) {
                vin = vehicles[0].vin
                loadStatus()
            }
        })
    }

    /** The last line of a Python traceback as a message for the user: psa_bridge raises RuntimeError with Dutch text;
        the errors of psa_car_controller and the network that occur most get a Dutch text here. */
    function errorText(line) {
        if (/^RuntimeError: /.test(line)) {
            return line.replace(/^RuntimeError: /, "")
        }
        if (/RateLimitException/.test(line)) {
            return "Te veel verzoeken achter elkaar (limiet van psa_car_controller); probeer het over een kwartier opnieuw"
        }
        if (/(ConnectionError|ConnectTimeout|ReadTimeout|NewConnectionError|MaxRetryError)/.test(line)) {
            return "Geen verbinding met de server van PSA; controleer de internetverbinding en probeer het opnieuw"
        }
        return line
    }

    /** Imports and initialises psa_bridge, then loads the session and the car. */
    function start() {
        busy = true
        error = ""
        python.importModule("psa_bridge", function() {
            python.call("psa_bridge.init", [dataDir, "stellamaris.log"], function() {
                busy = false
                if (error === "") {
                    ready = true
                    loadSession()
                }
            })
        })
    }

    /** Repeats the start-up step that failed. */
    function retryStartup() {
        if (!ready) {
            start()
        } else if (session === null) {
            loadSession()
        } else {
            loadVehicles()
        }
    }

    function loadSession() {
        bridge("get_session", [], function(result) {
            session = result
            if (session && session.connected && vin === "") {
                loadVehicles()
            }
        })
    }

    /** Completes the login with the mymacsdk:// redirect caught by the login page. */
    function finishLogin(url) {
        var match = /[?&]code=([^&#]+)/.exec(url)
        if (!match) {
            error = "Geen code in " + url
            return
        }
        if (pageStack.currentPage.objectName === "loginPage") {
            pageStack.pop()
        }
        bridge("finish_login", [decodeURIComponent(match[1])], loadSession)
    }

    Python {
        id: python

        Component.onCompleted: {
            addImportPath(Qt.resolvedUrl("../python"))
            addImportPath(Qt.resolvedUrl("../lib"))
            start()
        }

        // traceback is PyOtherSide's "Return value of PyObject call is NULL: Traceback…"; its last line holds the actual error.
        onError: {
            busy = false
            var lines = traceback.trim().split("\n")
            app.error = errorText(lines[lines.length - 1])
            console.warn(traceback)
            if (commandActive) {
                finishCommand("mislukt")
            }
        }
    }

    // Refreshes the server status every 5 minutes while the app is in front, and when it comes back to the front.
    // This only asks PSA's server, not the car, so it does not count towards the wake-up limit.
    Timer {
        interval: 300000
        repeat: true
        running: app.vin !== "" && Qt.application.active
        onTriggered: loadStatus()
    }

    Connections {
        target: Qt.application
        onActiveChanged: {
            if (Qt.application.active && app.vin !== "" && !app.busy) {
                loadStatus()
            }
        }
    }

    ConfigurationValue {
        id: chargeLimitSetting
        key: "/nl/stellamaris/stellamaris/chargeLimit"
        defaultValue: 100
    }

    // The charge limit only works while the app runs: with a limit set, this wakes the phone to let
    // psa_car_controller's ChargeControl check the battery, every 2.5 minutes while charging and else every 15.
    BackgroundJob {
        id: chargeLimitJob
        enabled: app.ready && app.vin !== "" && app.remoteReady && app.chargeLimit < 100
        triggeredOnEnable: true
        frequency: app.charging ? BackgroundJob.TwoAndHalfMinutes : BackgroundJob.FifteenMinutes
        onTriggered: python.call("psa_bridge.check_charge_limit", [app.vin, app.chargeLimit], function(result) {
            if (result) {
                app.status = result
                app.chargeLimitChecked = new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
            }
            chargeLimitJob.finished()
        })
    }

    Timer {
        id: commandTimeout
        interval: 180000
        onTriggered: finishCommand("geen antwoord van de auto")
    }

    // Picks up MQTT messages: command progress, and state messages with the freshest battery level and range.
    // Keeps running in the background while a command is under way, so the cover shows its progress.
    Timer {
        interval: 3000
        repeat: true
        running: app.ready && app.vin !== "" && (Qt.application.active || app.commandActive)
        onTriggered: python.call("psa_bridge.get_remote_messages", [remoteMessageCount], function(messages) {
            if (!messages) {
                return
            }
            remoteMessageCount += messages.length
            for (var i = 0; i < messages.length; i++) {
                handleRemoteMessage(messages[i])
            }
        })
    }

    initialPage: Component { MainPage {} }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
}
