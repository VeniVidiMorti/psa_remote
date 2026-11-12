import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    /** True when logged in. Default false until the session is loaded. */
    property bool connected: app.session !== null && app.session.connected
    /** Battery level in percent, from app.current. Default null. */
    property var level: app.current ? app.current.level : null
    /** Range in km, from app.current. Default null. */
    property var range: app.current ? app.current.range : null
    /** Time (HH:mm) of the values shown. Default empty. */
    property string updated: app.current && app.current.time
                             ? new Date(app.current.time).toLocaleTimeString(Qt.locale(), "HH:mm")
                             : ""
    /** True once there is a battery level to show. Default false. */
    property bool hasData: level !== null && level !== undefined

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: !hasData
            text: "PSA Remote"
            font.pixelSize: Theme.fontSizeLarge
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: !hasData
            text: !app.ready ? qsTr("Loading…") : (connected ? qsTr("No data yet") : qsTr("Not logged in"))
            color: Theme.secondaryColor
            wrapMode: Text.Wrap
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: hasData
            text: level + " %"
            font.pixelSize: Theme.fontSizeHuge
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: hasData && range !== null && range !== undefined
            text: visible ? app.distanceText(range, 0) : ""
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: hasData && updated !== ""
            text: updated
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: hasData && app.chargeLimit < 100
            text: qsTr("charges to %1 %").arg(app.chargeLimit)
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeExtraSmall
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: app.commandActive
            text: app.commandProgress
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraSmall
            wrapMode: Text.Wrap
        }
    }

    CoverActionList {
        enabled: connected

        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: app.loadStatus()
        }
    }
}
