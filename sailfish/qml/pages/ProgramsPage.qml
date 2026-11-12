import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    /** Short names of the days in the system language, in the order of a program's "day" list, Monday first;
        Qt numbers the days from Sunday (0). */
    property var dayNames: [1, 2, 3, 4, 5, 6, 0].map(function(day) { return Qt.locale().dayName(day, Locale.ShortFormat) })
    /** Program keys in the order they are shown. */
    property var programKeys: ["program1", "program2", "program3", "program4"]
    /** True when commands can be sent; see app.remoteReady. */
    property bool remoteReady: app.remoteReady

    /** psa_car_controller and the car use hour 34 (minute 7) for a program that is not set. */
    function isSet(program) {
        return program.hour < 24
    }

    function timeText(program) {
        return program.hour + ":" + (program.minute < 10 ? "0" : "") + program.minute
    }

    /** Opens the editor for one program and sends all four programs to the car when it is accepted. */
    function edit(key, number) {
        var dialog = pageStack.push(Qt.resolvedUrl("ProgramDialog.qml"), {
            number: number,
            program: app.preconditioningPrograms[key]
        })
        dialog.accepted.connect(function() {
            var programs = {}
            for (var i = 0; i < programKeys.length; i++) {
                var other = programKeys[i]
                if (app.preconditioningPrograms[other] !== undefined) {
                    programs[other] = app.preconditioningPrograms[other]
                }
            }
            programs[key] = dialog.result
            // The command always carries "asap" too; keep preconditioning as the server last reported it.
            var running = app.preconditioning !== null && app.preconditioning.status === "Enabled"
            app.sendCommand(qsTr("Save programmes"), "set_preconditioning_programs", [programs, running])
        })
    }

    function daysText(program) {
        var names = []
        for (var i = 0; i < program.day.length && i < dayNames.length; i++) {
            if (program.day[i]) {
                names.push(dayNames[i])
            }
        }
        return names.length > 0 ? names.join(", ") : qsTr("no days")
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: app.commandActive
            visible: page.remoteReady

            MenuItem {
                text: qsTr("Request status from the car")
                enabled: !app.commandActive
                onClicked: app.sendCommand(qsTr("Request status"), "wakeup")
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Preconditioning programmes")
                description: app.preconditioningProgramsDate !== ""
                             ? qsTr("according to the car, %1").arg(new Date(app.preconditioningProgramsDate).toLocaleString(Qt.locale(), Locale.ShortFormat))
                             : ""
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.remoteReady && app.preconditioningPrograms !== null
                text: qsTr("Tap a programme to change it.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: app.commandProgress !== ""
                text: app.commandLabel + ": " + app.commandProgress
                color: Theme.highlightColor
                wrapMode: Text.Wrap
            }

            Repeater {
                model: app.preconditioningPrograms ? page.programKeys : []

                ListItem {
                    property var program: app.preconditioningPrograms[modelData]

                    visible: program !== undefined
                    contentHeight: Theme.itemSizeMedium
                    enabled: page.remoteReady && !app.commandActive
                    onClicked: page.edit(modelData, index + 1)

                    Column {
                        anchors {
                            left: parent.left
                            right: onOffLabel.left
                            leftMargin: Theme.horizontalPageMargin
                            rightMargin: Theme.paddingMedium
                            verticalCenter: parent.verticalCenter
                        }

                        Label {
                            width: parent.width
                            text: qsTr("Programme %1").arg(index + 1)
                        }
                        Label {
                            width: parent.width
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryColor
                            truncationMode: TruncationMode.Fade
                            text: program && page.isSet(program) ? page.timeText(program) + "  ·  " + page.daysText(program) : qsTr("not set")
                        }
                    }

                    Label {
                        id: onOffLabel
                        anchors {
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        visible: program !== undefined && page.isSet(program)
                        text: program && program.on ? qsTr("on") : qsTr("off")
                        color: program && program.on ? Theme.highlightColor : Theme.secondaryColor
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: app.preconditioningPrograms === null
            text: qsTr("Not known yet")
            hintText: page.remoteReady
                      ? qsTr("The programmes come with a status message from the car. Pull down and choose Request status from the car.")
                      : qsTr("The programmes come with a status message from the car; activate the commands first.")
        }

        VerticalScrollDecorator {}
    }
}
