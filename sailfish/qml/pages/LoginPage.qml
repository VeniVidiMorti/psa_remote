import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0

WebViewPage {
    id: page
    objectName: "loginPage"

    /** Login page of the brand's identity provider, from psa_bridge.start_login(). Required. */
    property string loginUrl

    WebView {
        id: webView
        anchors.fill: parent
        url: page.loginUrl

        onViewInitialized: {
            addMessageListener("stellamaris:redirect")
            loadFrameScript(Qt.resolvedUrl("RedirectCatcher.js"))
        }

        onRecvAsyncMessage: {
            if (message === "stellamaris:redirect") {
                app.finishLogin(data.url)
            }
        }
    }
}
