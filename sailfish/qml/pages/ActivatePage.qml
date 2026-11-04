import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    canAccept: smsCode.text.length > 0 && pin.text.length > 0

    onAccepted: app.bridge("activate_remote", [smsCode.text, pin.text], app.loadSession)

    Column {
        width: parent.width
        spacing: Theme.paddingMedium

        DialogHeader {
            acceptText: "Activeren"
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            color: Theme.highlightColor
            text: "Voor commando's moet deze installatie eenmalig geactiveerd worden met een sms-code en de pincode van de MyCitroën-app. PSA staat maar ongeveer 6 codes per dag toe."
        }

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Sms aanvragen"
            enabled: !app.busy
            onClicked: app.bridge("request_sms", [])
        }

        TextField {
            id: smsCode
            label: "Sms-code"
            inputMethodHints: Qt.ImhDigitsOnly
            EnterKey.onClicked: pin.focus = true
        }

        PasswordField {
            id: pin
            label: "Pincode"
            inputMethodHints: Qt.ImhDigitsOnly
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
    }
}
