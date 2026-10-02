"use strict";

const MINIMUM_NATIVE_INTERVAL_MS = 80;
const NATIVE_REQUEST_TIMEOUT_MS = 1500;
let inFlightSample = null;
let lastSampleStartedAt = 0;
let lastSampleResult = null;

function requestNativeSample() {
    if (inFlightSample) return inFlightSample;

    const now = performance.now();
    if (lastSampleResult && now - lastSampleStartedAt < MINIMUM_NATIVE_INTERVAL_MS) {
        return Promise.resolve(lastSampleResult);
    }

    lastSampleStartedAt = now;
    let timeoutIdentifier = null;
    const nativeRequest = browser.runtime.sendNativeMessage({
        command: "sample"
    }).catch((error) => ({
        state: "error",
        error: String(error)
    }));
    const timeout = new Promise((resolve) => {
        timeoutIdentifier = setTimeout(() => resolve({
            state: "error",
            error: "Native sample request timed out"
        }), NATIVE_REQUEST_TIMEOUT_MS);
    });

    inFlightSample = Promise.race([nativeRequest, timeout]).then((result) => {
        if (result && result.state !== "error") {
            lastSampleResult = result;
        }
        return result;
    }).finally(() => {
        if (timeoutIdentifier !== null) clearTimeout(timeoutIdentifier);
        inFlightSample = null;
    });

    return inFlightSample;
}

browser.runtime.onMessage.addListener((message) => {
    if (!message || message.type !== "live-mbps-bar-sample") return undefined;
    return requestNativeSample();
});
