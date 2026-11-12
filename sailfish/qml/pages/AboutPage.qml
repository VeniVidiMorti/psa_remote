import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0

Page {
    id: page

    /** True once psa_bridge has answered whether a newer release of the app exists. Default false. */
    property bool updateChecked: false
    /** Version of the newer release of the app on GitHub, e.g. "0.3.0-8". Default empty: none, or not checked yet. */
    property string updateVersion: ""
    /** True while the RPM of the newer release is downloading. Default false. */
    property bool downloading: false

    /** Downloads the newer release and hands the RPM to the system's installation dialog. */
    function update() {
        downloading = true
        app.bridge("download_update", [app.version], function(fileUrl) {
            downloading = false
            if (fileUrl) {
                installer.typedCall("installFiles", [{ type: "as", value: [fileUrl] }])
            }
        })
    }

    // Needs the Sailjail permission ApplicationInstallation.
    DBusInterface {
        id: installer
        service: "org.sailfishos.installationhandler"
        path: "/org/sailfishos/installationhandler"
        iface: "org.sailfishos.installationhandler"
    }

    /** Version of the bundled psa_car_controller release. Default empty until psa_bridge has answered. */
    property string controllerVersion: ""
    /** Newest psa_car_controller release on PyPI. Default empty until PyPI has answered, and when it cannot be reached. */
    property string latestControllerVersion: ""

    function controllerText() {
        if (controllerVersion === "") {
            return "psa_car_controller"
        }
        if (latestControllerVersion === "") {
            return "psa_car_controller " + controllerVersion
        }
        return "psa_car_controller " + controllerVersion
            + (latestControllerVersion === controllerVersion ? " (de nieuwste)" : " (nieuwste is " + latestControllerVersion + ")")
    }

    function loadLatestControllerVersion() {
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE && request.status === 200) {
                latestControllerVersion = JSON.parse(request.responseText).info.version
            }
        }
        request.open("GET", "https://pypi.org/pypi/psa-car-controller/json")
        request.send()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: "Over"
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "/usr/share/icons/hicolor/172x172/apps/stellamaris.png"
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "PSA Remote"
                font.pixelSize: Theme.fontSizeExtraLarge
                color: Theme.highlightColor
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Versie " + app.version + (updateChecked && updateVersion === "" ? " (de nieuwste)" : "")
                color: Theme.secondaryHighlightColor
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: updateVersion !== ""
                enabled: !downloading
                text: downloading ? "Downloaden…" : "Bijwerken naar " + updateVersion
                onClicked: page.update()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: app.error !== ""
                text: app.error
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: "Status en bediening op afstand van een auto van de PSA-merken van Stellantis."
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                linkColor: Theme.primaryColor
                textFormat: Text.StyledText
                text: "Gebruikt een ongewijzigde release van flobz:<br>" + controllerText() + "<br>"
                    + "<a href=\"https://github.com/flobz/psa_car_controller\">github.com/flobz/psa_car_controller</a><br><br>"
                    + "Licentie: GPL-3.0<br>"
                    + "Broncode: <a href=\"https://github.com/VeniVidiMorti/psa_remote\">github.com/VeniVidiMorti/psa_remote</a>"
                onLinkActivated: Qt.openUrlExternally(link)
            }
        }

        VerticalScrollDecorator {}
    }

    Component.onCompleted: {
        loadLatestControllerVersion()
        if (app.ready) {
            app.bridge("get_controller_version", [], function(result) {
                if (result) {
                    controllerVersion = result
                }
            })
            // PyOtherSide passes None as null, and undefined after a Python error.
            app.bridge("check_update", [app.version], function(result) {
                updateChecked = result !== undefined
                updateVersion = result || ""
            })
        }
    }
}
