// Gecko frame script for the login page. The identity provider ends with a 302 to the official app's scheme
// (mymacsdk://…?code=…), which Gecko cannot follow; this passes that Location on to QML before it is dropped.
(function() {
    "use strict";

    const services = typeof Services !== "undefined"
        ? Services
        : ChromeUtils.import("resource://gre/modules/Services.jsm").Services;
    const topic = "http-on-examine-response";
    const observer = {
        observe(subject) {
            try {
                const channel = subject.QueryInterface(Ci.nsIHttpChannel);
                if (channel.responseStatus >= 300 && channel.responseStatus < 400) {
                    const location = channel.getResponseHeader("Location");
                    if (location.startsWith("mymacsdk:")) {
                        sendAsyncMessage("stellamaris:redirect", { url: location });
                    }
                }
            } catch (e) {
                // Not an HTTP channel, or no Location header.
            }
        }
    };

    services.obs.addObserver(observer, topic);
    addEventListener("unload", function() { services.obs.removeObserver(observer, topic); });
})();
