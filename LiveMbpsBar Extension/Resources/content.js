(() => {
    "use strict";

    const HOST_ID = "live-mbps-bar-host";
    const SAMPLE_DELAY_MS = 100;
    const BACKGROUND_REQUEST_TIMEOUT_MS = 2000;
    const BASE_RENDER_INTERVAL_MS = 250;
    const RELATIVE_INTERVAL_VARIATION = 1 / 3;
    const PINK_OCTAVE_COUNT = 8;
    const PINK_AMPLITUDE_GAIN = 2.5;
    const FAILURE_GRACE_MS = 500;
    const DEFAULT_MAXIMUM_MBPS = 20;
    const DEFAULT_COLOR_HEX = "58DE2F";

    let host = null;
    let bar = null;
    let label = null;
    let latestEvent = null;
    let lastRenderedSampleKey = null;
    let currentState = "baseline";
    let currentSpeedMbps = null;
    let currentMaximumMbps = DEFAULT_MAXIMUM_MBPS;
    let currentColorHex = DEFAULT_COLOR_HEX;
    let showSpeed = true;
    let expiryTimer = null;
    let expiryGeneration = 0;
    let pinkCounter = 0;
    let immersiveMode = false;
    let immersiveCheckTimer = null;
    const pinkOctaves = Array.from({ length: PINK_OCTAVE_COUNT }, randomSignedUnit);

    function finitePositiveNumber(value, fallback) {
        const number = Number(value);
        return Number.isFinite(number) && number > 0 ? number : fallback;
    }

    function finiteNonnegativeNumber(value, fallback = 0) {
        const number = Number(value);
        return Number.isFinite(number) && number >= 0 ? number : fallback;
    }

    function clamp(value, minimum, maximum) {
        return Math.min(maximum, Math.max(minimum, value));
    }

    function randomSignedUnit() {
        return (Math.random() * 2) - 1;
    }

    function normalizeColor(value) {
        const candidate = String(value || "").replace(/^#/, "").toUpperCase();
        return /^[0-9A-F]{6}$/.test(candidate) ? candidate : DEFAULT_COLOR_HEX;
    }

    function sampleKey(sample) {
        const processId = typeof sample?.processId === "string" ? sample.processId : "legacy";
        return `${processId}:${String(sample?.sampleId)}`;
    }

    function setImportantStyles(element, styles) {
        for (const [property, value] of Object.entries(styles)) {
            element.style.setProperty(property, value, "important");
        }
    }

    function installOverlay() {
        const root = document.documentElement;
        if (!root) return false;

        if (host && host.isConnected && bar && label) return true;

        const existing = document.getElementById(HOST_ID);
        if (existing) existing.remove();

        host = document.createElement("div");
        host.id = HOST_ID;
        host.setAttribute("aria-hidden", "true");
        setImportantStyles(host, {
            all: "initial",
            display: immersiveMode ? "none" : "block",
            position: "fixed",
            top: "0",
            right: "0",
            bottom: "auto",
            left: "0",
            width: "100vw",
            height: "32px",
            margin: "0",
            padding: "0",
            border: "0",
            overflow: "visible",
            "pointer-events": "none",
            "z-index": "2147483647",
            transition: "none",
            animation: "none",
            contain: "layout style paint"
        });

        const shadow = host.attachShadow({ mode: "closed" });
        const style = document.createElement("style");
        style.textContent = `
            :host { all: initial !important; }
            #bar {
                all: initial !important;
                position: fixed !important;
                top: 0 !important;
                left: 0 !important;
                width: 0 !important;
                height: 3px !important;
                box-sizing: border-box !important;
                pointer-events: none !important;
                z-index: 2147483647 !important;
                transition: none !important;
                animation: none !important;
            }
            #label {
                all: initial !important;
                position: fixed !important;
                top: 3px !important;
                left: 0 !important;
                box-sizing: border-box !important;
                padding: 2px 5px !important;
                color: #fff !important;
                background: rgba(0, 0, 0, 0.68) !important;
                font: 500 13px/18px -apple-system, BlinkMacSystemFont, sans-serif !important;
                white-space: nowrap !important;
                -webkit-text-size-adjust: none !important;
                pointer-events: none !important;
                z-index: 2147483647 !important;
                transition: none !important;
                animation: none !important;
            }
            @media (orientation: landscape) {
                #label {
                    left: max(52px, env(safe-area-inset-left, 0px)) !important;
                }
            }
        `;

        bar = document.createElement("div");
        bar.id = "bar";
        label = document.createElement("div");
        label.id = "label";
        shadow.append(style, bar, label);
        root.appendChild(host);
        paintCurrentState();
        return true;
    }

    function applySettings(sample) {
        if (!sample || typeof sample !== "object") return;
        currentMaximumMbps = finitePositiveNumber(sample.maximumMbps, DEFAULT_MAXIMUM_MBPS);
        currentColorHex = normalizeColor(sample.colorHex);
        showSpeed = sample.showSpeed !== false;
        paintCurrentState();
    }

    function paintCurrentState() {
        if (!installOverlay() || !bar || !label) return;

        bar.style.setProperty("background", `#${currentColorHex}`, "important");
        label.style.setProperty("display", showSpeed ? "block" : "none", "important");

        if (currentState === "live" && currentSpeedMbps !== null) {
            const widthPercent = Math.min(100, (currentSpeedMbps / currentMaximumMbps) * 100);
            bar.style.setProperty("width", `${widthPercent.toFixed(3)}%`, "important");
            bar.style.setProperty("visibility", "visible", "important");
            label.textContent = `${currentSpeedMbps.toFixed(1)} Mbps`;
            host.dataset.liveMbpsBarState = "live";
            host.dataset.liveMbpsBarSpeedMbps = currentSpeedMbps.toFixed(6);
            host.dataset.liveMbpsBarMaximumMbps = currentMaximumMbps.toFixed(1);
        } else {
            bar.style.setProperty("width", "0%", "important");
            bar.style.setProperty("visibility", "hidden", "important");
            label.textContent = currentState === "disconnected" || currentState === "counterReset"
                ? "-Mbps"
                : "— Mbps";
            host.dataset.liveMbpsBarState = currentState;
            delete host.dataset.liveMbpsBarSpeedMbps;
        }

        host.style.setProperty("display", immersiveMode ? "none" : "block", "important");
    }

    function cancelExpiry() {
        expiryGeneration += 1;
        if (expiryTimer !== null) {
            window.clearTimeout(expiryTimer);
            expiryTimer = null;
        }
    }

    function scheduleExpiry(renderIntervalMilliseconds) {
        cancelExpiry();
        const generation = expiryGeneration;
        const delay = renderIntervalMilliseconds + FAILURE_GRACE_MS;
        expiryTimer = window.setTimeout(() => {
            if (generation !== expiryGeneration || currentState !== "live") return;
            currentState = "baseline";
            currentSpeedMbps = null;
            paintCurrentState();
        }, delay);
    }

    function renderEvent(sample, renderIntervalMilliseconds) {
        const state = String(sample?.state || "error");
        if (state === "live") {
            currentState = "live";
            currentSpeedMbps = finiteNonnegativeNumber(sample.mbpsIn);
            paintCurrentState();
            scheduleExpiry(renderIntervalMilliseconds);
            return;
        }

        if (state === "baseline" || state === "disconnected" || state === "counterReset") {
            cancelExpiry();
            currentState = state;
            currentSpeedMbps = null;
            paintCurrentState();
        }
    }

    async function requestSampleFromBackground() {
        let timeoutIdentifier = null;
        try {
            const timeout = new Promise((_, reject) => {
                timeoutIdentifier = window.setTimeout(
                    () => reject(new Error("Background sample request timed out")),
                    BACKGROUND_REQUEST_TIMEOUT_MS
                );
            });
            return await Promise.race([
                browser.runtime.sendMessage({ type: "live-mbps-bar-sample" }),
                timeout
            ]);
        } finally {
            if (timeoutIdentifier !== null) window.clearTimeout(timeoutIdentifier);
        }
    }

    async function sampleLoop() {
        try {
            const sample = await requestSampleFromBackground();
            applySettings(sample);
            if (sample && ["live", "baseline", "disconnected", "counterReset"].includes(sample.state)) {
                latestEvent = sample;
            }
        } catch (error) {
            // A native acquisition failure is handled by the active display-expiry timer.
        } finally {
            window.setTimeout(sampleLoop, SAMPLE_DELAY_MS);
        }
    }

    function nextPinkValue() {
        pinkCounter = (pinkCounter + 1) % (1 << PINK_OCTAVE_COUNT);

        let octaveIndex = 0;
        let selector = pinkCounter;
        while ((selector & 1) === 0 && octaveIndex < PINK_OCTAVE_COUNT - 1) {
            octaveIndex += 1;
            selector >>>= 1;
        }
        pinkOctaves[octaveIndex] = randomSignedUnit();

        const octaveSum = pinkOctaves.reduce((sum, value) => sum + value, 0);
        const whiteComponent = randomSignedUnit();
        return clamp(
            ((octaveSum + whiteComponent) / (PINK_OCTAVE_COUNT + 1)) * PINK_AMPLITUDE_GAIN,
            -1,
            1
        );
    }

    function nextRenderIntervalMilliseconds() {
        const halfRange = BASE_RENDER_INTERVAL_MS * RELATIVE_INTERVAL_VARIATION;
        return clamp(
            BASE_RENDER_INTERVAL_MS + (nextPinkValue() * halfRange),
            BASE_RENDER_INTERVAL_MS - halfRange,
            BASE_RENDER_INTERVAL_MS + halfRange
        );
    }

    function renderLoop() {
        const nextInterval = nextRenderIntervalMilliseconds();
        installOverlay();

        const latestSampleKey = latestEvent ? sampleKey(latestEvent) : null;
        if (latestEvent && latestSampleKey !== lastRenderedSampleKey) {
            lastRenderedSampleKey = latestSampleKey;
            renderEvent(latestEvent, nextInterval);
        }

        if (host) {
            host.dataset.liveMbpsBarNextRenderIntervalMs = nextInterval.toFixed(3);
        }
        window.setTimeout(renderLoop, nextInterval);
    }

    function elementIsVisible(element) {
        if (!(element instanceof Element)) return false;
        const style = window.getComputedStyle(element);
        return style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) > 0;
    }

    function isDirectImageDocument() {
        if (String(document.contentType || "").toLowerCase().startsWith("image/")) return true;
        const body = document.body;
        if (!body) return false;

        const visibleChildren = Array.from(body.children).filter((child) => {
            if (child === host || child.tagName === "SCRIPT" || child.tagName === "STYLE") return false;
            return elementIsVisible(child);
        });
        return visibleChildren.length === 1 && ["IMG", "PICTURE"].includes(visibleChildren[0].tagName);
    }

    function hasFullscreenVideo() {
        return Array.from(document.querySelectorAll("video")).some((video) =>
            video.webkitPresentationMode === "fullscreen"
        );
    }

    function hasCustomMediaViewer() {
        const selectors = [
            "dialog[open]",
            "[aria-modal='true']",
            "[role='dialog']",
            "[class*='lightbox' i]",
            "[class*='image-viewer' i]",
            "[class*='photo-viewer' i]",
            "[class*='media-viewer' i]",
            "[class*='fullscreen-viewer' i]",
            "[class*='zoom-viewer' i]",
            "[class*='image-modal' i]",
            "[class*='photoswipe' i]",
            "[class*='pswp' i]",
            "[class*='fancybox' i]"
        ];
        const viewportWidth = Math.max(1, window.innerWidth);
        const viewportHeight = Math.max(1, window.innerHeight);
        const candidates = new Set(document.querySelectorAll(selectors.join(",")));
        const probePoints = [
            [viewportWidth * 0.5, viewportHeight * 0.5],
            [viewportWidth * 0.25, viewportHeight * 0.25],
            [viewportWidth * 0.75, viewportHeight * 0.75]
        ];

        for (const [x, y] of probePoints) {
            for (const element of document.elementsFromPoint(x, y)) {
                let candidate = element;
                for (let depth = 0; candidate && depth < 5; depth += 1) {
                    candidates.add(candidate);
                    candidate = candidate.parentElement;
                }
            }
        }

        for (const candidate of candidates) {
            if (!elementIsVisible(candidate) || candidate === host) continue;

            const style = window.getComputedStyle(candidate);
            if (style.position !== "fixed" && style.position !== "absolute") continue;

            const rect = candidate.getBoundingClientRect();
            if (rect.width < viewportWidth * 0.8 || rect.height < viewportHeight * 0.75) continue;

            const media = candidate.matches("img, picture, video, canvas, svg")
                ? candidate
                : candidate.querySelector("img, picture, video, canvas, svg");
            if (!media || !elementIsVisible(media)) continue;
            const mediaRect = media.getBoundingClientRect();
            const mediaArea = Math.max(0, mediaRect.width) * Math.max(0, mediaRect.height);
            if (mediaArea >= viewportWidth * viewportHeight * 0.3) return true;
        }
        return false;
    }

    function computeImmersiveMode() {
        return Boolean(
            document.fullscreenElement
            || document.webkitFullscreenElement
            || hasFullscreenVideo()
            || isDirectImageDocument()
            || hasCustomMediaViewer()
        );
    }

    function refreshImmersiveMode() {
        immersiveMode = computeImmersiveMode();
        if (host) {
            host.style.setProperty("display", immersiveMode ? "none" : "block", "important");
        }
    }

    function scheduleImmersiveCheck() {
        if (immersiveCheckTimer !== null) return;
        immersiveCheckTimer = window.setTimeout(() => {
            immersiveCheckTimer = null;
            refreshImmersiveMode();
        }, 80);
    }

    document.addEventListener("fullscreenchange", refreshImmersiveMode, true);
    document.addEventListener("webkitfullscreenchange", refreshImmersiveMode, true);
    document.addEventListener("webkitpresentationmodechanged", refreshImmersiveMode, true);
    window.addEventListener("resize", scheduleImmersiveCheck, { passive: true });
    window.addEventListener("orientationchange", scheduleImmersiveCheck, { passive: true });

    const documentObserver = new MutationObserver(scheduleImmersiveCheck);
    documentObserver.observe(document, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["class", "style", "open", "aria-modal"]
    });

    installOverlay();
    refreshImmersiveMode();
    window.setTimeout(sampleLoop, 0);
    window.setTimeout(renderLoop, 0);
})();
