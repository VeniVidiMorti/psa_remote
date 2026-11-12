import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    /** Shown under a switch once PSA has refused that command for this car. */
    property string refusedText: qsTr("Does not seem to be supported by this car")
    /** Choices for the distance unit, as stored in app.settings.distanceUnit. */
    property var distanceUnits: ["system", "km", "mi"]
    /** Choices for the temperature unit, as stored in app.settings.temperatureUnit. */
    property var temperatureUnits: ["system", "C", "F", "K"]
    /** Names of the temperature units; proper names, the same in every language. */
    property var temperatureUnitNames: ({ "C": "Celsius", "F": "Fahrenheit", "K": "Kelvin" })
    /** Choices for the way energy use is shown, as stored in app.settings.consumptionFormat. */
    property var consumptionFormats: ["energyPerDistance", "distancePerEnergy"]

    function distanceUnitText(unit) {
        if (unit === "km") {
            return qsTr("kilometres")
        }
        if (unit === "mi") {
            return qsTr("miles")
        }
        return qsTr("as the system (%1)").arg(app.distanceUnit)
    }

    function statusModeText(mode) {
        var texts = {
            "always": qsTr("always"),
            "charging": qsTr("only while charging"),
            "notCharging": qsTr("not while charging"),
            "never": qsTr("never")
        }
        return texts[mode]
    }

    function consumptionFormatText(format) {
        return format === "distancePerEnergy" ? app.distanceUnit + "/kWh" : "kWh/100 " + app.distanceUnit
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Settings")
            }

            SectionHeader { text: qsTr("Units") }

            ComboBox {
                label: qsTr("Distance")
                currentIndex: Math.max(0, distanceUnits.indexOf(app.settings.distanceUnit))
                menu: ContextMenu {
                    Repeater {
                        model: distanceUnits
                        MenuItem {
                            text: distanceUnitText(modelData)
                            onClicked: app.settings.distanceUnit = modelData
                        }
                    }
                }
            }
            ComboBox {
                label: qsTr("Temperature")
                currentIndex: Math.max(0, temperatureUnits.indexOf(app.settings.temperatureUnit))
                menu: ContextMenu {
                    Repeater {
                        model: temperatureUnits
                        MenuItem {
                            text: modelData === "system" ? qsTr("as the system (%1)").arg(temperatureUnitNames[app.temperatureUnit])
                                                         : temperatureUnitNames[modelData]
                            onClicked: app.settings.temperatureUnit = modelData
                        }
                    }
                }
            }
            ComboBox {
                label: qsTr("Energy use")
                currentIndex: Math.max(0, consumptionFormats.indexOf(app.settings.consumptionFormat))
                menu: ContextMenu {
                    Repeater {
                        model: consumptionFormats
                        MenuItem {
                            text: consumptionFormatText(modelData)
                            onClicked: app.settings.consumptionFormat = modelData
                        }
                    }
                }
            }

            SectionHeader { text: qsTr("Trips") }

            TextField {
                label: qsTr("Usable battery capacity (kWh)")
                description: qsTr("For the energy a trip used, derived from the drop in battery level")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                text: app.settings.batteryCapacity.toLocaleString(Qt.locale(), "f", 1)
                // Both a comma and a point are accepted as the decimal separator.
                onTextChanged: {
                    var capacity = parseFloat(text.replace(",", "."))
                    if (capacity > 0 && capacity !== app.settings.batteryCapacity) {
                        app.settings.batteryCapacity = capacity
                    }
                }
            }

            SectionHeader { text: qsTr("Show in status") }

            Repeater {
                model: app.statusItems.items

                ComboBox {
                    property string key: modelData.key

                    label: modelData.label
                    description: modelData.value === null ? qsTr("Not reported by the car at the moment") : ""
                    currentIndex: Math.max(0, app.statusItems.modes.indexOf(app.statusItems.mode(key)))
                    menu: ContextMenu {
                        Repeater {
                            model: app.statusItems.modes
                            MenuItem {
                                text: statusModeText(modelData)
                                onClicked: app.statusItems.setMode(key, modelData)
                            }
                        }
                    }
                }
            }

            SectionHeader { text: qsTr("Show commands") }

            TextSwitch {
                text: qsTr("Lock and unlock")
                description: app.settings.doorsRefused ? refusedText : ""
                automaticCheck: false
                checked: app.settings.showDoors
                onClicked: app.settings.showDoors = !app.settings.showDoors
            }
            TextSwitch {
                text: qsTr("Flash lights")
                description: app.settings.lightsRefused ? refusedText : ""
                automaticCheck: false
                checked: app.settings.showLights
                onClicked: app.settings.showLights = !app.settings.showLights
            }
        }

        VerticalScrollDecorator {}
    }
}
