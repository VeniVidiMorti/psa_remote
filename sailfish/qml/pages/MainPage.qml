import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    /** True when logged in. Default false until the session is loaded. */
    property bool connected: app.session !== null && app.session.connected
    /** True when commands can be sent; see app.remoteReady. */
    property bool remoteReady: app.remoteReady
    /** Choices for the charge limit, in percent; 100 means no limit. */
    property var chargeLimits: [100, 70, 75, 80, 85, 90, 95]

    function formatValue(value, unit) {
        return value === undefined || value === null ? "—" : value + (unit || "")
    }

    /** Preconditioning state in words, with the reason when it failed. */
    function preconditioningText(preconditioning) {
        if (!preconditioning || !preconditioning.status) {
            return "—"
        }
        var states = { "Enabled": "aan", "Disabled": "uit", "Finished": "klaar", "Failure": "mislukt" }
        var causes = {
            "Defect": "defect",
            "DoorOpened": "deur open",
            "LowBattery": "accu te leeg",
            "LowFuelLevel": "brandstof te laag",
            "TooManyUnusedProg": "te veel ongebruikte programma's",
            "WindowsRoofOpened": "raam of dak open"
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

    function login() {
        app.bridge("start_login", [], function(url) {
            if (url) {
                pageStack.push(Qt.resolvedUrl("LoginPage.qml"), { loginUrl: url })
            }
        })
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: app.busy
            visible: page.connected

            MenuItem {
                text: "Uitloggen"
                onClicked: app.bridge("logout", [], function() {
                    app.vin = ""
                    app.status = null
                    app.loadSession()
                })
            }
            MenuItem {
                text: app.session && app.session.remoteActivated ? "Opnieuw activeren" : "Activeren voor commando's"
                visible: app.session !== null && app.session.hasCustomerId
                onClicked: pageStack.push(Qt.resolvedUrl("ActivatePage.qml"))
            }
            MenuItem {
                text: "Voorverwarmschema's"
                onClicked: pageStack.push(Qt.resolvedUrl("ProgramsPage.qml"))
            }
            MenuItem {
                text: "Ritten"
                onClicked: pageStack.push(Qt.resolvedUrl("TripsPage.qml"))
            }
            MenuItem {
                text: "Status opvragen bij de auto"
                visible: page.remoteReady
                enabled: !app.commandActive
                onClicked: app.sendCommand("Status opvragen", "wakeup")
            }
            MenuItem {
                text: "Verversen"
                // Without a car (loading it failed), load the car first.
                onClicked: app.vin === "" ? app.loadVehicles() : app.loadStatus()
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: "Auto"
                description: app.vin
            }

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium
                visible: app.commandProgress !== ""

                BusyIndicator {
                    id: commandBusy
                    size: BusyIndicatorSize.ExtraSmall
                    running: app.commandActive
                    visible: running
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width - (commandBusy.visible ? commandBusy.width + parent.spacing : 0)
                    text: app.commandLabel + ": " + app.commandProgress
                    color: Theme.highlightColor
                    wrapMode: Text.Wrap
                }
            }

            Column {
                width: parent.width
                spacing: Theme.paddingLarge
                visible: app.session !== null && !page.connected

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    text: app.session && app.session.configured
                          ? "Log in met je MyCitroën-account."
                          : "Nog niet ingesteld: zet config.json (van tools/setup.py) in " + app.dataDir + " en start de app opnieuw."
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: app.session !== null && app.session.configured
                    text: "Inloggen"
                    enabled: !app.busy
                    onClicked: page.login()
                }
            }

            Column {
                width: parent.width
                visible: page.connected && !app.startupFailed

                SectionHeader { text: "Status" }
                DetailItem {
                    label: "Batterij"
                    value: formatValue(app.current ? app.current.level : null, " %")
                }
                DetailItem {
                    label: "Actieradius"
                    value: formatValue(app.current ? app.current.range : null, " km")
                }
                DetailItem {
                    label: "Stekker erin"
                    value: app.electric && app.electric.charging ? (app.electric.charging.plugged ? "ja" : "nee") : "—"
                }
                DetailItem {
                    label: "Voorverwarmen"
                    value: preconditioningText(app.preconditioning)
                }
                DetailItem {
                    label: "Laadstatus"
                    value: formatValue(app.electric && app.electric.charging ? app.electric.charging.status : null)
                }
                DetailItem {
                    label: "Bijgewerkt"
                    value: app.current && app.current.time
                           ? new Date(app.current.time).toLocaleString(Qt.locale(), Locale.ShortFormat) + " (" + app.current.source + ")"
                           : "—"
                }

                SectionHeader { text: "Commando's" }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: !page.remoteReady
                    wrapMode: Text.Wrap
                    color: Theme.secondaryHighlightColor
                    text: app.session && app.session.hasCustomerId
                          ? "Activeer deze installatie eerst via het menu."
                          : "De customer id ontbreekt in config.json; draai tools/setup.py op de desktop."
                }
                ButtonLayout {
                    visible: page.remoteReady

                    Button {
                        text: "Voorverwarmen aan"
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "preconditioning", [true])
                    }
                    Button {
                        text: "Voorverwarmen uit"
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "preconditioning", [false])
                    }
                    Button {
                        text: "Nu laden"
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "charge_now", [true])
                    }
                    Button {
                        text: "Uitgesteld laden"
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "charge_now", [false])
                    }
                    Button {
                        text: "Vergrendelen"
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "lock_door", [true])
                    }
                    Button {
                        text: "Ontgrendelen"
                        enabled: !app.commandActive
                        // Unlocking by mistake has consequences, so it can be cancelled for a few seconds.
                        onClicked: remorse.execute("Auto ontgrendelen", function() {
                            app.sendCommand("Ontgrendelen", "lock_door", [false])
                        })
                    }
                    Button {
                        text: "Lichten knipperen"
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "lights")
                    }
                }

                ComboBox {
                    visible: page.remoteReady
                    label: "Laadlimiet"
                    currentIndex: Math.max(0, page.chargeLimits.indexOf(app.chargeLimit))
                    menu: ContextMenu {
                        Repeater {
                            model: page.chargeLimits
                            MenuItem {
                                text: modelData === 100 ? "geen (helemaal vol)" : modelData + " %"
                                onClicked: app.setChargeLimit(modelData)
                            }
                        }
                    }
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: page.remoteReady && app.chargeLimit < 100
                    wrapMode: Text.Wrap
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: "Laadt tot " + app.chargeLimit + " %. Laat de app open (op de achtergrond mag), anders laadt de auto vol."
                          + (app.chargeLimitChecked !== "" ? " Laatst gecontroleerd om " + app.chargeLimitChecked + "." : "")
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: app.error !== "" && !app.startupFailed
                text: app.error
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: app.busy && (!app.ready || app.session === null || (page.connected && app.vin === ""))
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingLarge
        visible: app.startupFailed

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraLarge
            text: "Opstarten mislukt"
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeSmall
            text: app.error
        }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Opnieuw proberen"
            onClicked: app.retryStartup()
        }
    }
}
