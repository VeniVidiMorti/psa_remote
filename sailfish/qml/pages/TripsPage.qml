import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

Page {
    id: page

    /** Page to pass to get_trips() for the trips before the ones shown; null at the oldest. Default null. */
    property var older: null
    /** True while a page of trips is loading. Default false. */
    property bool loading: false
    /** Trips loaded so far, newest first, as returned by get_trips(). Default empty. */
    property var trips: []
    /** The loaded trips that last at least minMinutes. */
    property var shownTrips: trips.filter(function(trip) { return trip.duration >= minMinutes.value * 60 })
    /** Choices for the minimum duration, in minutes; 0 shows all trips. */
    property var minuteChoices: [0, 2, 5, 10]
    /** True when the last attempt to load a page of trips failed. Default false. */
    property bool loadFailed: false

    ConfigurationValue {
        id: minMinutes
        key: "/nl/stellamaris/stellamaris/minTripMinutes"
        defaultValue: 0
    }

    function load(pageUrl) {
        loading = true
        app.bridge("get_trips", pageUrl ? [app.vin, pageUrl] : [app.vin], function(result) {
            loading = false
            loadFailed = !result
            if (!result) {
                return
            }
            var lastShown = shownTrips.length - 1
            trips = trips.concat(result.trips)
            older = result.older
            // A new model sends the list back to the top; keep the last trip seen at the bottom instead.
            if (lastShown >= 0) {
                list.positionViewAtIndex(lastShown, ListView.End)
            }
        })
    }

    function electricEnergy(energies) {
        for (var i = 0; energies && i < energies.length; i++) {
            if (energies[i].type === "Electric") {
                return energies[i]
            }
        }
        return null
    }

    function minutes(seconds) {
        return qsTr("%1 min").arg(Math.round(seconds / 60))
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.shownTrips

        header: Column {
            width: parent.width

            PageHeader {
                title: qsTr("Trips")
            }
            ComboBox {
                label: qsTr("Minimum duration")
                currentIndex: Math.max(0, page.minuteChoices.indexOf(minMinutes.value))
                menu: ContextMenu {
                    Repeater {
                        model: page.minuteChoices
                        MenuItem {
                            text: modelData === 0 ? qsTr("all trips") : qsTr("%1 min").arg(modelData)
                            onClicked: minMinutes.value = modelData
                        }
                    }
                }
            }
        }

        delegate: ListItem {
            contentHeight: column.height + 2 * Theme.paddingMedium

            property var trip: modelData
            property var start: electricEnergy(trip.startEnergies)
            property var end: electricEnergy(trip.endEnergies)
            // Energy used in kWh, from the drop in battery level; 0 when the levels are missing or did not drop.
            // PSA's own energyConsumptions is not shown: it is well below what the car itself reports.
            property real usedEnergy: start && end && start.level > end.level
                                      ? (start.level - end.level) / 100 * app.settings.batteryCapacity : 0

            Column {
                id: column
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    text: new Date(trip.startedAt).toLocaleString(Qt.locale(), Locale.ShortFormat)
                          + "  ·  " + app.distanceText(trip.distance, 1)
                          + "  ·  " + minutes(trip.duration)
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    wrapMode: Text.Wrap
                    text: [
                        usedEnergy > 0 ? "≈ " + usedEnergy.toLocaleString(Qt.locale(), "f", 1) + " kWh"
                                         + (trip.distance > 0 ? " (" + app.consumptionText(usedEnergy, trip.distance) + ")" : "") : "",
                        start && end ? start.level + " → " + end.level + " %" : "",
                        // kinetic.avgSpeed is not usable: it was in m/s for one trip and in km/h for another.
                        trip.duration > 0 ? qsTr("%1 avg.").arg(app.speedText(trip.distance / (trip.duration / 3600))) : ""
                    ].filter(function(part) { return part !== "" }).join("  ·  ")
                }
            }
        }

        footer: Column {
            width: parent.width
            spacing: Theme.paddingMedium

            Item {
                width: 1
                height: Theme.paddingSmall
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.loadFailed && page.trips.length > 0
                text: app.error
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.older !== null && !page.loading
                text: page.loadFailed ? qsTr("Try again") : qsTr("Older trips")
                onClicked: page.load(page.older)
            }
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: page.loading
                visible: running
            }
            Item {
                width: 1
                height: Theme.paddingLarge
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && !page.loadFailed && page.shownTrips.length === 0
            text: qsTr("No trips")
            hintText: page.trips.length > 0 ? qsTr("Only shorter trips loaded; try Older trips or a shorter minimum duration") : ""
        }

        VerticalScrollDecorator {}
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingLarge
        visible: page.loadFailed && page.trips.length === 0 && !page.loading

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraLarge
            text: qsTr("Loading trips failed")
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
            onClicked: page.load(null)
        }
    }

    Component.onCompleted: load(null)
}
