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
            acceptText: qsTr("Activate")
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            color: Theme.highlightColor
            text: qsTr("For commands, this installation has to be activated once with an SMS code and the PIN of the MyCitroën app. PSA allows only about 6 codes a day.")
        }

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Request SMS")
            enabled: !app.busy
            onClicked: app.bridge("request_sms", [])
        }

        TextField {
            id: smsCode
            label: qsTr("SMS code")
            inputMethodHints: Qt.ImhDigitsOnly
            EnterKey.onClicked: pin.focus = true
        }

        PasswordField {
            id: pin
            label: qsTr("PIN")
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
