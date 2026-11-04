import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    /** Number of the program shown in the header, 1 to 4. Required. */
    property int number
    /** The program as the car reports it: hour, minute, on, day (7 values, Monday first). Required. */
    property var program
    /** Names of the days, Monday first. */
    property var dayNames: ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"]

    /** Hour of the edited program; 34 means not set. */
    property int hour: program.hour
    /** Minute of the edited program. */
    property int minute: program.minute
    /** Days of the edited program, Monday first, 1 for the days it runs. */
    property var days: program.day.slice()
    /** Whether the edited program is switched on. */
    property bool on: program.on === 1

    /** The edited program in the car's format. */
    property var result: ({ hour: hour, minute: minute, on: on ? 1 : 0, day: days })

    function clear() {
        hour = 34
        minute = 7
        on = false
        days = [0, 0, 0, 0, 0, 0, 0]
    }

    Component {
        id: timePicker

        TimePickerDialog {
            hourMode: DateTime.TwentyFourHours
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                title: "Programma " + dialog.number
                acceptText: "Opslaan"
            }

            TextSwitch {
                text: "Ingeschakeld"
                checked: dialog.on
                enabled: dialog.hour < 24
                onClicked: dialog.on = checked
            }

            ValueButton {
                label: "Tijd"
                value: dialog.hour < 24
                       ? dialog.hour + ":" + (dialog.minute < 10 ? "0" : "") + dialog.minute
                       : "niet ingesteld"
                onClicked: {
                    var picker = pageStack.push(timePicker, {
                        hour: dialog.hour < 24 ? dialog.hour : 7,
                        minute: dialog.hour < 24 ? dialog.minute : 30
                    })
                    picker.accepted.connect(function() {
                        dialog.hour = picker.hour
                        dialog.minute = picker.minute
                    })
                }
            }

            SectionHeader { text: "Dagen" }

            Repeater {
                model: dialog.dayNames

                TextSwitch {
                    text: modelData
                    checked: dialog.days[index] === 1
                    enabled: dialog.hour < 24
                    onClicked: {
                        var days = dialog.days.slice()
                        days[index] = checked ? 1 : 0
                        dialog.days = days
                    }
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Programma leegmaken"
                visible: dialog.hour < 24
                onClicked: dialog.clear()
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Opslaan stuurt alle vier de programma's naar de auto, samen met de huidige stand van het voorverwarmen."
            }
        }

        VerticalScrollDecorator {}
    }
}
