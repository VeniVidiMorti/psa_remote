import QtQuick 2.0

/** Everything the car reports, as the lines of the status section; the settings page lets the user hide each of them. */
QtObject {
    /** The status lines in the order shown: key, label and value in words; value is null when the car does not report it. */
    property var items: {
        var charging = app.electric && app.electric.charging ? app.electric.charging : {}
        var health = app.electric && app.electric.battery && app.electric.battery.health ? app.electric.battery.health : {}
        var status = app.status || {}
        var environment = status.environment || {}
        var position = status.lastPosition && status.lastPosition.geometry ? status.lastPosition.geometry.coordinates : null
        return [
            { key: "battery", label: qsTr("Battery"), value: app.current && isNumber(app.current.level) ? app.current.level + " %" : null },
            { key: "range", label: qsTr("Range"), value: app.current && isNumber(app.current.range) ? app.distanceText(app.current.range, 0) : null },
            { key: "plugged", label: qsTr("Plugged in"), value: yesNo(charging.plugged) },
            { key: "chargingStatus", label: qsTr("Charging status"), value: charging.status || null },
            { key: "chargingMode", label: qsTr("Charging mode"), value: chargingModeText(charging.chargingMode) },
            // chargingRate is the range gained per hour of charging, in km/h.
            { key: "chargingRate", label: qsTr("Charging speed"), value: isNumber(charging.chargingRate) ? app.speedText(charging.chargingRate) : null },
            { key: "remainingTime", label: qsTr("Charging time remaining"), value: durationText(charging.remainingTime) },
            { key: "delayedStart", label: qsTr("Delayed charging starts at"), value: durationText(charging.nextDelayedTime) },
            { key: "preconditioning", label: qsTr("Preconditioning"), value: preconditioningText(app.preconditioning) },
            { key: "outsideTemperature", label: qsTr("Outside temperature"),
              value: environment.air && isNumber(environment.air.temp) ? app.temperatureText(environment.air.temp) : null },
            { key: "daylight", label: qsTr("Daylight"), value: environment.luminosity ? yesNo(environment.luminosity.day) : null },
            { key: "odometer", label: qsTr("Odometer"),
              value: status.odometer && isNumber(status.odometer.mileage) ? app.distanceText(status.odometer.mileage, 0) : null },
            { key: "ignition", label: qsTr("Ignition"), value: status.ignition ? ignitionText(status.ignition.type) : null },
            { key: "batteryHealth", label: qsTr("Battery health (resistance)"), value: isNumber(health.resistance) ? health.resistance + " %" : null },
            { key: "auxiliaryBattery", label: qsTr("12 V battery"), value: status.battery && isNumber(status.battery.voltage) ? status.battery.voltage + " %" : null },
            { key: "privacy", label: qsTr("Privacy mode"), value: status.privacy ? privacyText(status.privacy.state) : null },
            // GeoJSON order: longitude, latitude.
            { key: "position", label: qsTr("Position"),
              value: position && isNumber(position[0]) && isNumber(position[1]) ? position[1].toFixed(5) + ", " + position[0].toFixed(5) : null },
            { key: "updated", label: qsTr("Updated"),
              value: app.current && app.current.time
                     ? new Date(app.current.time).toLocaleString(Qt.locale(), Locale.ShortFormat) + " (" + app.current.source + ")" : null }
        ]
    }

    /** When a status line can be shown: "always", "charging" (only while charging), "notCharging" or "never". */
    property var modes: ["always", "charging", "notCharging", "never"]
    /** The mode of the lines that are not shown always, unless the user chooses otherwise. */
    property var defaultModes: ({ "chargingMode": "charging", "chargingRate": "charging", "remainingTime": "charging" })
    /** The user's choices that differ from the default, by key; kept in app.settings.statusItemModes as "key=mode,key=mode". */
    property var chosenModes: {
        var chosen = {}
        app.settings.statusItemModes.split(",").forEach(function(entry) {
            var parts = entry.split("=")
            if (parts.length === 2) {
                chosen[parts[0]] = parts[1]
            }
        })
        return chosen
    }

    function mode(key) {
        return chosenModes[key] || defaultModes[key] || "always"
    }

    function setMode(key, mode) {
        var chosen = chosenModes
        chosen[key] = mode
        app.settings.statusItemModes = Object.keys(chosen).filter(function(other) {
            return chosen[other] !== (defaultModes[other] || "always")
        }).map(function(other) { return other + "=" + chosen[other] }).join(",")
    }

    /** True when the user's choice for this status line lets it show now. */
    function isShown(key) {
        var chosen = mode(key)
        return chosen === "always" || (chosen === "charging" && app.charging) || (chosen === "notCharging" && !app.charging)
    }

    // Until 0.3.0-13 the hidden lines were kept as a list of keys; those become "never".
    Component.onCompleted: {
        var hidden = app.settings.hiddenStatusItems.split(",").filter(function(key) { return key !== "" })
        hidden.forEach(function(key) { setMode(key, "never") })
        app.settings.hiddenStatusItems = ""
    }

    function isNumber(value) {
        return typeof value === "number"
    }

    function yesNo(value) {
        return value === true ? qsTr("yes") : (value === false ? qsTr("no") : null)
    }

    /** An ISO 8601 duration of hours and minutes, such as "PT4H1M", as "04:01"; null when missing. */
    function durationText(duration) {
        var parts = /^PT(?:(\d+)H)?(?:(\d+)M)?/.exec(duration || "")
        if (!parts || (parts[1] === undefined && parts[2] === undefined)) {
            return null
        }
        var hours = parts[1] || "0"
        var minutes = parts[2] || "0"
        return (hours.length < 2 ? "0" : "") + hours + ":" + (minutes.length < 2 ? "0" : "") + minutes
    }

    function chargingModeText(mode) {
        var modes = { "No": qsTr("none"), "Slow": qsTr("slow"), "Quick": qsTr("fast") }
        return mode ? (modes[mode] || mode) : null
    }

    function ignitionText(type) {
        var types = { "Stop": qsTr("off"), "StartUp": qsTr("starting"), "Start": qsTr("on") }
        return type ? (types[type] || type) : null
    }

    function privacyText(state) {
        var states = { "None": qsTr("off"), "Geolocation": qsTr("location hidden"), "Full": qsTr("everything hidden") }
        return state ? (states[state] || state) : null
    }

    /** Preconditioning state in words, with the reason when it failed. */
    function preconditioningText(preconditioning) {
        if (!preconditioning || !preconditioning.status) {
            return null
        }
        var states = { "Enabled": qsTr("on"), "Disabled": qsTr("off"), "Finished": qsTr("finished"), "Failure": qsTr("failed") }
        var causes = {
            "Defect": qsTr("defect"),
            "DoorOpened": qsTr("door open"),
            "LowBattery": qsTr("battery too low"),
            "LowFuelLevel": qsTr("fuel level too low"),
            "TooManyUnusedProg": qsTr("too many unused programmes"),
            "WindowsRoofOpened": qsTr("window or roof open")
        }
        var text = states[preconditioning.status] || preconditioning.status
        if (preconditioning.status === "Failure" && preconditioning.failureCause) {
            text += " (" + (causes[preconditioning.failureCause] || preconditioning.failureCause) + ")"
        }
        if (preconditioning.updatedAt) {
            text += ", " + new Date(preconditioning.updatedAt).toLocaleTimeString(Qt.locale(), "HH:mm")
        }
        return text
    }
}
