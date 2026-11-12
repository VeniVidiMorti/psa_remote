import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    /** True when logged in. Default false until the session is loaded. */
    property bool connected: app.session !== null && app.session.connected
    /** True when commands can be sent; see app.remoteReady. */
    property bool remoteReady: app.remoteReady
    /** True while the server reports preconditioning as running. Default false. */
    property bool preconditioningOn: app.preconditioning !== null && app.preconditioning !== undefined
                                     && app.preconditioning.status === "Enabled"
    /** Charging status the server reports: Disconnected, InProgress, Finished, Stopped or Failure. Default empty. */
    property string chargingStatus: app.electric && app.electric.charging && app.electric.charging.status
                                    ? app.electric.charging.status : ""
    /** True when the server reports the charging cable as plugged in. Default false. */
    property bool plugged: app.electric !== null && app.electric.charging !== undefined && app.electric.charging.plugged === true
    /** Choices for the charge limit, in percent; 100 means no limit. */
    property var chargeLimits: [100, 70, 75, 80, 85, 90, 95]

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

            MenuItem {
                text: qsTr("About")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: qsTr("Log out")
                visible: page.connected
                onClicked: app.bridge("logout", [], function() {
                    app.vin = ""
                    app.status = null
                    app.loadSession()
                })
            }
            MenuItem {
                text: app.session && app.session.remoteActivated ? qsTr("Activate again") : qsTr("Activate for commands")
                visible: page.connected && app.session.hasCustomerId
                onClicked: pageStack.push(Qt.resolvedUrl("ActivatePage.qml"))
            }
            MenuItem {
                text: qsTr("Preconditioning programmes")
                visible: page.connected
                onClicked: pageStack.push(Qt.resolvedUrl("ProgramsPage.qml"))
            }
            MenuItem {
                text: qsTr("Trips")
                visible: page.connected
                onClicked: pageStack.push(Qt.resolvedUrl("TripsPage.qml"))
            }
            MenuItem {
                text: qsTr("Request status from the car")
                visible: page.remoteReady
                enabled: !app.commandActive
                onClicked: app.sendCommand(qsTr("Request status"), "wakeup")
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Car")
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
                          ? qsTr("Log in with your MyCitroën account.")
                          : qsTr("Not set up yet: put config.json (from tools/setup.py) in %1 and restart the app.").arg(app.dataDir)
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: app.session !== null && app.session.configured
                    text: qsTr("Log in")
                    enabled: !app.busy
                    onClicked: page.login()
                }
            }

            Column {
                width: parent.width
                visible: page.connected && !app.startupFailed

                SectionHeader { text: qsTr("Status") }
                // Only what the car reports and the user has not hidden on the settings page.
                Repeater {
                    model: app.statusItems.items

                    DetailItem {
                        visible: modelData.value !== null && app.statusItems.isShown(modelData.key)
                        label: modelData.label
                        value: modelData.value !== null ? modelData.value : ""
                    }
                }

                SectionHeader { text: qsTr("Commands") }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: !page.remoteReady
                    wrapMode: Text.Wrap
                    color: Theme.secondaryHighlightColor
                    text: app.session && app.session.hasCustomerId
                          ? qsTr("Activate this installation first via the menu.")
                          : qsTr("The customer id is missing from config.json; run tools/setup.py on the desktop.")
                }
                ButtonLayout {
                    visible: page.remoteReady

                    Button {
                        text: page.preconditioningOn ? qsTr("Preconditioning off") : qsTr("Preconditioning on")
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "preconditioning", [!page.preconditioningOn])
                    }
                    Button {
                        text: qsTr("Charge now")
                        enabled: !app.commandActive && page.plugged && !app.charging && page.chargingStatus !== "Finished"
                        onClicked: app.sendCommand(text, "charge_now", [true])
                    }
                    Button {
                        text: qsTr("Delayed charging")
                        enabled: !app.commandActive && page.plugged && app.charging
                        onClicked: app.sendCommand(text, "charge_now", [false])
                    }
                    Button {
                        text: qsTr("Lock")
                        visible: app.settings.showDoors
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "lock_door", [true])
                    }
                    Button {
                        text: qsTr("Unlock")
                        visible: app.settings.showDoors
                        enabled: !app.commandActive
                        // Unlocking by mistake has consequences, so it can be cancelled for a few seconds.
                        onClicked: remorse.execute(qsTr("Unlocking the car"), function() {
                            app.sendCommand(qsTr("Unlock"), "lock_door", [false])
                        })
                    }
                    Button {
                        text: qsTr("Flash lights")
                        visible: app.settings.showLights
                        enabled: !app.commandActive
                        onClicked: app.sendCommand(text, "lights")
                    }
                }

                ComboBox {
                    visible: page.remoteReady
                    label: qsTr("Charge limit")
                    currentIndex: Math.max(0, page.chargeLimits.indexOf(app.chargeLimit))
                    menu: ContextMenu {
                        Repeater {
                            model: page.chargeLimits
                            MenuItem {
                                text: modelData === 100 ? qsTr("none (charge full)") : modelData + " %"
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
                    text: qsTr("Charges to %1 %. Leave the app open (in the background is fine), otherwise the car charges full.").arg(app.chargeLimit)
                          + (app.chargeLimitChecked !== "" ? " " + qsTr("Last checked at %1.").arg(app.chargeLimitChecked) : "")
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
            text: qsTr("Starting failed")
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
            text: qsTr("Try again")
            onClicked: app.retryStartup()
        }
    }
}
