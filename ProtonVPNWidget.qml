import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services
import QtQuick.Controls
import QtQuick.Effects

PluginComponent {
    id: root
    
    popoutWidth: 350
    popoutHeight: 0

    // --- CC Support ---
    ccWidgetIcon: "vpn_key"
    ccWidgetPrimaryText: "Proton VPN"
    ccWidgetSecondaryText: root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : (root.isConnecting ? "Connecting..." : (root.isDisconnecting ? "Disconnecting..." : "Disconnected"))
    ccWidgetIsActive: root.vpnStatus === "Connected"
    ccDetailHeight: 540
    onCcWidgetExpanded: root.refresh()
    
    ccDetailContent: Component {
        Item {
            implicitWidth: 350
            implicitHeight: 540
            width: parent ? parent.width : 350
            height: parent ? parent.height : 540

            ScrollView {
                anchors.fill: parent
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                
                Loader {
                    width: 350
                    height: item ? item.implicitHeight : 540
                    sourceComponent: vpnWidgetContent
                    readonly property bool inCC: true
                }
            }
        }
    }

    Component.onCompleted: {
        console.log("Proton VPN Plugin (pVPN CLI) Loaded");
        root.refresh();
        root.fetchServers();
    }

    // --- State Management ---
    property string vpnStatus: "Disconnected" // "Connected", "Connecting...", "Disconnected", "Daemon Stopped"
    property string connectedServer: ""
    property string connectedCountry: ""
    property string connectedCountryName: ""
    property string connectedIp: ""
    property string connectedProtocol: ""
    property string connectionTypeLabel: "Disconnected"
    
    property bool isConnecting: false
    property bool isDisconnecting: false
    property bool loading: statusScanner.running || connectProc.running || disconnectProc.running
    property string expandedCountryCode: "" // Currently expanded country code
    property string _lastServersJson: ""

    // Country Name Map with fallbacks
    property var countryNameMap: ({
        "US": "United States", "NL": "Netherlands", "JP": "Japan", "CH": "Switzerland",
        "GB": "United Kingdom", "DE": "Germany", "CA": "Canada", "FR": "France",
        "SE": "Sweden", "NO": "Norway", "ES": "Spain", "IT": "Italy",
        "AU": "Australia", "IN": "India", "BR": "Brazil", "PL": "Poland",
        "FI": "Finland", "DK": "Denmark", "AT": "Austria", "BE": "Belgium",
        "IE": "Ireland", "NZ": "New Zealand", "SG": "Singapore", "KR": "South Korea",
        "MX": "Mexico", "RO": "Romania", "CZ": "Czechia", "HK": "Hong Kong",
        "TW": "Taiwan", "ZA": "South Africa", "IS": "Iceland", "PT": "Portugal"
    })

    property var countriesList: [
        { name: "United States", code: "US", flag: "🇺🇸", target: "US", servers: [ { name: "US-NY#1", target: "US-NY#1", load: "18%" }, { name: "US-CA#1", target: "US-CA#1", load: "24%" } ] },
        { name: "Netherlands", code: "NL", flag: "🇳🇱", target: "NL", servers: [ { name: "NL-FREE#1", target: "NL-FREE#1", load: "14%" }, { name: "NL-FREE#2", target: "NL-FREE#2", load: "28%" } ] },
        { name: "Japan", code: "JP", flag: "🇯🇵", target: "JP", servers: [ { name: "JP-TY#1", target: "JP-TY#1", load: "22%" }, { name: "JP-TY#2", target: "JP-TY#2", load: "35%" } ] },
        { name: "Switzerland", code: "CH", flag: "🇨🇭", target: "CH", servers: [ { name: "CH-ZH#1", target: "CH-ZH#1", load: "15%" } ] },
        { name: "United Kingdom", code: "GB", flag: "🇬🇧", target: "GB", servers: [ { name: "GB-LON#1", target: "GB-LON#1", load: "24%" } ] },
        { name: "Germany", code: "DE", flag: "🇩🇪", target: "DE", servers: [ { name: "DE-FRA#1", target: "DE-FRA#1", load: "17%" } ] },
        { name: "Canada", code: "CA", flag: "🇨🇦", target: "CA", servers: [ { name: "CA-TR#1", target: "CA-TR#1", load: "21%" } ] }
    ]

    // --- Settings & Reactivity ---
    property string _defaultProtocol: PluginService.loadPluginData("protonVPN", "defaultProtocol", "smart")
    property string _defaultConnectTarget: PluginService.loadPluginData("protonVPN", "defaultConnectTarget", "fastest")

    PluginGlobalVar { varName: "defaultProtocol"; onValueChanged: function(val) { root._defaultProtocol = val; } }
    PluginGlobalVar { varName: "defaultConnectTarget"; onValueChanged: function(val) { root._defaultConnectTarget = val; } }

    // --- Country Flag & Name Helpers ---
    function getCountryFlag(code) {
        if (!code || code.length !== 2) return "🌐";
        let c = code.toUpperCase();
        let codePoints = [c.charCodeAt(0) + 127397, c.charCodeAt(1) + 127397];
        return String.fromCodePoint(...codePoints);
    }

    function getCountryName(code) {
        if (!code) return "Unknown";
        let c = code.toUpperCase();
        if (root.countryNameMap[c]) return root.countryNameMap[c];
        try {
            if (typeof Intl !== "undefined" && Intl.DisplayNames) {
                let dn = new Intl.DisplayNames(['en'], { type: 'region' });
                let name = dn.of(c);
                if (name && name !== c) return name;
            }
        } catch(e) {}
        return c;
    }

    // --- Scanners & Process Execution ---
    Process {
        id: statusScanner
        command: ["bash", "-c", "pvpnctl status --format waybar 2>/dev/null || echo '{\"class\":\"disconnected\"}'; echo '---'; pvpnctl status 2>/dev/null || echo 'Disconnected'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let raw = text.trim();
                    if (!raw) return;
                    
                    if (raw.includes("Cannot connect to pvpnd")) {
                        root.vpnStatus = "Daemon Stopped";
                        root.isConnecting = false;
                        root.isDisconnecting = false;
                        root.connectionTypeLabel = "pvpnd Daemon Stopped";
                        return;
                    }

                    let parts = raw.split('---');
                    let waybarStr = parts[0].trim();
                    let rawStatusStr = parts.length > 1 ? parts[1].trim() : "";
                    
                    let data = { "class": "disconnected", "text": "" };
                    try { data = JSON.parse(waybarStr); } catch(e) {}
                    
                    let isConnected = (data.class === "connected") || rawStatusStr.toLowerCase().includes("status: connected") || rawStatusStr.toLowerCase().includes("connected to");
                    let isDaemonConnecting = (data.class === "connecting") || rawStatusStr.toLowerCase().includes("connecting");

                    if (isConnected) {
                        root.vpnStatus = "Connected";
                        root.isConnecting = false;
                        root.isDisconnecting = false;
                        connectTimeoutTimer.stop();
                        
                        let fullServer = "";
                        let country = "";
                        let protocol = "";
                        
                        let lines = rawStatusStr.split('\n');
                        for (let i = 0; i < lines.length; i++) {
                            let l = lines[i].trim();
                            let low = l.toLowerCase();
                            
                            if (low.startsWith("server")) {
                                let val = l.substring(6).trim();
                                if (val.startsWith(":")) val = val.substring(1).trim();
                                if (val) fullServer = val;
                            } else if (low.startsWith("country")) {
                                let val = l.substring(7).trim();
                                if (val.startsWith(":")) val = val.substring(1).trim();
                                if (val) country = val;
                            } else if (low.startsWith("protocol")) {
                                let val = l.substring(8).trim();
                                if (val.startsWith(":")) val = val.substring(1).trim();
                                if (val) protocol = val;
                            } else if (low.includes("connected to ")) {
                                if (!fullServer) fullServer = l.replace(/.*connected to\s+/i, "").trim();
                            }
                        }
                        
                        if (!fullServer && data.tooltip) {
                            let ttLines = data.tooltip.split('\n');
                            for (let j = 0; j < ttLines.length; j++) {
                                let tl = ttLines[j].toLowerCase();
                                if (tl.includes("server:")) fullServer = ttLines[j].split(':')[1].trim();
                                if (tl.includes("protocol:")) protocol = ttLines[j].split(':')[1].trim();
                                if (tl.includes("country:")) country = ttLines[j].split(':')[1].trim();
                            }
                        }

                        if (!fullServer && data.text) {
                            fullServer = data.text.replace(/^[^a-zA-Z0-9]+/, "").trim();
                        }
                        
                        root.connectedServer = fullServer || "Connected";
                        root.connectedProtocol = protocol || "SMART";
                        
                        if (root.connectedServer.length >= 2) {
                            let cc = root.connectedServer.substring(0, 2).toUpperCase();
                            if (cc.match(/^[A-Z]{2}$/)) {
                                root.connectedCountry = cc;
                                root.connectedCountryName = root.getCountryName(cc);
                            } else {
                                root.connectedCountry = "";
                                root.connectedCountryName = country || "Global";
                            }
                        } else {
                            root.connectedCountry = "";
                            root.connectedCountryName = country || "Global";
                        }

                        root.connectionTypeLabel = root.connectedServer || "Connected";
                        
                    } else if (isDaemonConnecting || (root.isConnecting && !root.isDisconnecting)) {
                        root.vpnStatus = "Connecting...";
                        root.isConnecting = true;
                        root.isDisconnecting = false;
                    } else {
                        root.vpnStatus = "Disconnected";
                        root.isConnecting = false;
                        root.isDisconnecting = false;
                        connectTimeoutTimer.stop();
                        root.connectedServer = "";
                        root.connectedIp = "";
                        root.connectedCountry = "";
                        root.connectedCountryName = "";
                        root.connectedProtocol = "";
                        root.connectionTypeLabel = "Disconnected";
                    }
                } catch(e) {
                    if (!root.isConnecting && !root.isDisconnecting) {
                        root.vpnStatus = "Disconnected";
                        root.isConnecting = false;
                        root.isDisconnecting = false;
                    }
                }
            }
        }
    }

    property bool _paidServersOnly: PluginService.loadPluginData("protonVPN", "paidServersOnly", false)
    PluginGlobalVar { varName: "paidServersOnly"; onValueChanged: function(val) { root._paidServersOnly = val; } }

    Process {
        id: serversScanner
        command: ["bash", "-c", "pvpnctl servers || echo ''"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = text.trim();
                if (!raw || raw.includes("Cannot connect to pvpnd")) return;
                
                let lines = raw.split('\n');
                let parsedByCountry = {};
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line || line.toUpperCase().startsWith("NAME") || line.startsWith("---")) continue;
                    
                    let parts = line.split(/\s+/);
                    if (parts.length >= 2) {
                        let name = parts[0];
                        
                        let isFree = name.toUpperCase().includes("FREE") || line.toUpperCase().includes("FREE");
                        if (root._paidServersOnly && isFree) continue;

                        let loadStrMatch = line.match(/\b\d+%/);
                        let load = loadStrMatch ? loadStrMatch[0] : parts[parts.length - 1]; 
                        if (!load.endsWith("%")) load = load + "%";
                        
                        let countryCode = name.substring(0, 2).toUpperCase();
                        if (countryCode.length === 2 && countryCode.match(/^[A-Z]{2}$/)) {
                            if (!parsedByCountry[countryCode]) parsedByCountry[countryCode] = [];
                            parsedByCountry[countryCode].push({ name: name, target: name, load: load });
                        }
                    }
                }
                
                let newCountriesList = [];
                for (let code in parsedByCountry) {
                    newCountriesList.push({
                        name: root.getCountryName(code),
                        code: code,
                        flag: root.getCountryFlag(code),
                        target: code,
                        servers: parsedByCountry[code]
                    });
                }
                
                if (newCountriesList.length > 0) {
                    newCountriesList.sort((a, b) => a.name.localeCompare(b.name));
                    let newJson = JSON.stringify(newCountriesList);
                    if (root._lastServersJson !== newJson) {
                        root._lastServersJson = newJson;
                        root.countriesList = newCountriesList;
                    }
                }
            }
        }
    }

    Process {
        id: connectProc
        running: false
        onExited: {
            if (exitCode !== 0) {
                root.isConnecting = false;
                root.isDisconnecting = false;
                root.vpnStatus = "Disconnected";
                root.connectionTypeLabel = "Connection Failed";
                connectTimeoutTimer.stop();
            }
            root.refresh();
            statusTimer.restart();
        }
    }

    Process {
        id: disconnectProc
        running: false
        onExited: {
            if (exitCode !== 0) {
                root.isDisconnecting = false;
                connectTimeoutTimer.stop();
            }
            root.refresh();
            statusTimer.restart();
        }
    }

    Timer {
        id: connectTimeoutTimer
        interval: 20000
        running: false; repeat: false
        onTriggered: {
            root.isConnecting = false;
            root.isDisconnecting = false;
            root.refresh();
        }
    }

    function refresh() {
        if (!statusScanner.running) {
            statusScanner.running = true;
        }
    }

    function fetchServers() {
        if (root.expandedCountryCode !== "") return; 
        if (!serversScanner.running) {
            serversScanner.running = true;
        }
    }

    Timer {
        id: statusTimer
        interval: (root.isConnecting || root.isDisconnecting) ? 1000 : 3000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.refresh();
            if (root.vpnStatus === "Disconnected" || root.popoutOpen) {
                root.fetchServers();
            }
        }
    }

    function connectVpn(target) {
        root.isConnecting = true;
        root.isDisconnecting = false;
        root.vpnStatus = "Connecting...";
        let tgt = target || root._defaultConnectTarget || "fastest";
        root.connectionTypeLabel = "Connecting to " + tgt + "...";
        connectTimeoutTimer.restart();
        
        let proto = root._defaultProtocol || "smart";
        let cmd = "pvpnctl connect \"" + tgt + "\"";
        if (proto !== "smart") {
            cmd += " --protocol " + proto;
        }
        connectProc.command = ["bash", "-c", cmd];
        connectProc.running = true;
        statusTimer.restart();
    }

    function disconnectVpn() {
        root.isDisconnecting = true;
        root.isConnecting = false;
        root.vpnStatus = "Disconnecting...";
        root.connectionTypeLabel = "Disconnecting...";
        connectTimeoutTimer.restart();
        
        disconnectProc.command = ["bash", "-c", "pvpnctl disconnect"];
        disconnectProc.running = true;
        statusTimer.restart();
    }

    // --- Bar Pill ---
    horizontalBarPill: Component {
        RowLayout {
            id: pillRowH; spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Item {
                width: Theme.iconSize - 4; height: Theme.iconSize - 4
                Layout.alignment: Qt.AlignVCenter
                Loader {
                    id: pillIconLoaderH
                    anchors.fill: parent
                    asynchronous: true
                    sourceComponent: (root.loading || root.isConnecting || root.isDisconnecting) ? refreshingIconComp : standardPillIconH
                    
                    Component {
                        id: standardPillIconH
                        DankIcon {
                            name: root.vpnStatus === "Connected" ? "vpn_key" : "vpn_key_off"
                            size: Theme.iconSize - 4
                            color: root.vpnStatus === "Connected" ? Theme.primary : (Theme.widgetIconColor || Theme.surfaceText)
                            anchors.centerIn: parent
                        }
                    }
                }
            }
            Item {
                height: 20; Layout.fillWidth: false; Layout.preferredWidth: Math.max(pillTextH.implicitWidth, 60); Layout.alignment: Qt.AlignVCenter
                StyledText { 
                    id: pillTextH
                    text: root.isConnecting ? "Connecting..." : (root.isDisconnecting ? "Disconnecting..." : (root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : "Disconnected"))
                    font.pixelSize: Theme.fontSizeSmall - 1; font.weight: Font.Medium
                    color: root.vpnStatus === "Connected" ? Theme.primary : (Theme.widgetTextColor || Theme.surfaceText)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            width: 18; height: 18
            anchors.horizontalCenter: parent.horizontalCenter
            Loader {
                id: pillIconLoaderV
                anchors.fill: parent
                asynchronous: true
                sourceComponent: (root.loading || root.isConnecting || root.isDisconnecting) ? refreshingIconComp : standardPillIconV
                
                Component {
                    id: standardPillIconV
                    DankIcon {
                        name: root.vpnStatus === "Connected" ? "vpn_key" : "vpn_key_off"
                        size: 18
                        color: root.vpnStatus === "Connected" ? Theme.primary : (Theme.widgetIconColor || Theme.surfaceText)
                        anchors.centerIn: parent
                    }
                }
            }
        }
    }

    Component {
        id: refreshingIconComp
        DankIcon {
            name: "cached"; size: parent.width; color: Theme.primary
            anchors.centerIn: parent
            RotationAnimation on rotation { from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
        }
    }

    property bool popoutOpen: false

    onPopoutOpenChanged: {
        if (popoutOpen) {
            root.refresh();
            root.fetchServers();
        }
    }

    // --- Shared Components ---
    Component {
        id: sectionHeaderComponent
        RowLayout {
            spacing: Theme.spacingXS
            Item {
                width: 16; height: 16
                visible: typeof sectionSvg !== "undefined" && sectionSvg !== ""
                Layout.alignment: Qt.AlignVCenter
                Image {
                    source: (typeof sectionSvg !== "undefined" && sectionSvg !== "") ? Qt.resolvedUrl(sectionSvg) : ""
                    anchors.fill: parent
                    sourceSize.width: 16; sourceSize.height: 16
                    smooth: true
                }
            }
            DankIcon {
                name: typeof sectionIcon !== "undefined" ? sectionIcon : "info"
                size: 16
                color: Theme.primary
                visible: typeof sectionSvg === "undefined" || sectionSvg === ""
            }
            StyledText { text: sectionTitle; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText; Layout.fillWidth: true }
        }
    }

    // --- Content Component ---
    Component {
        id: vpnWidgetContent
        Column {
            id: mainCol; width: parent ? parent.width : 350; spacing: Theme.spacingM
            property bool inCC: false

            padding: inCC ? 16 : 0
            topPadding: 0
            bottomPadding: inCC ? 16 : 2

            // 1. Header Card
            StyledRect {
                width: parent.width; anchors.horizontalCenter: parent.horizontalCenter; height: 84
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1
                border.color: root.vpnStatus === "Connected" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                RowLayout {
                    anchors.fill: parent; anchors.margins: Theme.spacingM; spacing: Theme.spacingM
                    
                    Rectangle {
                        width: 48; height: 48; radius: 10
                        color: root.vpnStatus === "Connected" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.6)
                        border.color: root.vpnStatus === "Connected" ? Theme.primary : Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.15)
                        border.width: 1

                        Item {
                            anchors.fill: parent
                            DankIcon {
                                name: (root.isConnecting || root.isDisconnecting) ? "cached" : (root.vpnStatus === "Connected" ? "vpn_key" : "vpn_key_off")
                                size: 24
                                color: (root.vpnStatus === "Connected" || root.isConnecting || root.isDisconnecting) ? Theme.primary : Theme.surfaceText
                                anchors.centerIn: parent
                                visible: !(root.vpnStatus === "Connected" && root.connectedCountry)
                                RotationAnimation on rotation {
                                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: root.isConnecting || root.isDisconnecting
                                    onRunningChanged: { if (!running) rotation = 0; }
                                }
                            }
                            StyledText {
                                text: (root.vpnStatus === "Connected" && root.connectedCountry) ? root.getCountryFlag(root.connectedCountry) : ""
                                font.pixelSize: 30
                                anchors.centerIn: parent
                                visible: text !== ""
                            }
                        }
                    }

                    Column {
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 2
                        StyledText { 
                            text: "Proton VPN"
                            font.bold: true; font.pixelSize: Theme.fontSizeLarge; color: Theme.surfaceText 
                        }
                        
                        RowLayout {
                            spacing: 4
                            visible: root.isConnecting || root.isDisconnecting
                            DankIcon {
                                name: "cached"
                                size: 12
                                color: Theme.primary
                                RotationAnimation on rotation { 
                                    from: 0; to: 360; duration: 800; loops: Animation.Infinite; running: root.isConnecting || root.isDisconnecting
                                    onRunningChanged: { if (!running) rotation = 0; }
                                }
                            }
                            StyledText {
                                text: root.isConnecting ? "Connecting..." : "Disconnecting..."
                                font.pixelSize: Theme.fontSizeSmall - 1
                                font.weight: Font.Bold
                                color: Theme.primary
                            }
                        }

                        Item {
                            width: statusText.implicitWidth; height: statusText.implicitHeight; clip: true
                            visible: !root.isConnecting && !root.isDisconnecting
                            StyledText { 
                                id: statusText
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: root.vpnStatus === "Connected" ? Theme.primary : Theme.surfaceVariantText
                                elide: Text.ElideRight
                                property string targetText: root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : "Disconnected"
                                Component.onCompleted: text = targetText
                                onTargetTextChanged: { if (text !== targetText) flipAnim.restart(); }
                                SequentialAnimation {
                                    id: flipAnim
                                    ParallelAnimation {
                                        NumberAnimation { target: statusText; property: "opacity"; to: 0; duration: 75 }
                                        NumberAnimation { target: statusText; property: "y"; to: 8; duration: 75; easing.type: Easing.InQuad }
                                    }
                                    PropertyAction { target: statusText; property: "text"; value: statusText.targetText }
                                    ParallelAnimation {
                                        NumberAnimation { target: statusText; property: "opacity"; to: 1.0; duration: 75 }
                                        NumberAnimation { target: statusText; property: "y"; to: 0; duration: 75; easing.type: Easing.OutQuad }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: headerActionBtn
                        width: 106; height: 42; radius: Theme.cornerRadius
                        color: root.vpnStatus === "Connected" ? Theme.error : Theme.primary
                        opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                        scale: maHeaderBtn.pressed ? 0.95 : (maHeaderBtn.containsMouse ? 1.03 : 1.0)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        DankRipple {
                            id: headerBtnRipple
                            anchors.fill: parent
                            cornerRadius: Theme.cornerRadius
                            rippleColor: Theme.surface
                        }

                        RowLayout {
                            anchors.centerIn: parent; spacing: 6
                            DankIcon {
                                id: connBtnIcon
                                name: (root.isConnecting || root.isDisconnecting) ? "cached" : (root.vpnStatus === "Connected" ? "power_settings_new" : "link")
                                size: 18
                                color: Theme.surface
                                RotationAnimation on rotation {
                                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: root.isConnecting || root.isDisconnecting
                                    onRunningChanged: { if (!running) rotation = 0; }
                                }
                            }
                            StyledText {
                                text: root.isConnecting ? "Connecting" : (root.isDisconnecting ? "Disconnecting" : (root.vpnStatus === "Connected" ? "Disconnect" : "Connect"))
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                                color: Theme.surface
                            }
                        }

                        MouseArea {
                            id: maHeaderBtn
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.isConnecting && !root.isDisconnecting
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: mouse => headerBtnRipple.trigger(mouse.x, mouse.y)
                            onClicked: {
                                if (root.vpnStatus === "Connected") {
                                    root.disconnectVpn();
                                } else {
                                    root.connectVpn(root._defaultConnectTarget);
                                }
                            }
                        }
                    }
                }
            }

            // 2. Connection Details Container
            StyledRect {
                width: parent.width; anchors.horizontalCenter: parent.horizontalCenter
                height: connDetailsCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius; color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                Column {
                    id: connDetailsCol
                    anchors.fill: parent; anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    Loader {
                        width: parent.width
                        asynchronous: true
                        property string sectionIcon: "info"
                        property string sectionTitle: "Connection Details"
                        sourceComponent: sectionHeaderComponent
                    }

                    Column {
                        id: connDetailsListCol
                        width: parent.width
                        spacing: 2

                        Item {
                            id: srvDetailItem
                            width: parent.width; height: 38
                            Shape {
                                id: srvDetailBg
                                anchors.fill: parent
                                property real tlr: 12; property real trr: 12; property real blr: 6; property real brr: 6
                                property color paintColor: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)
                                property color paintBorder: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                                ShapePath {
                                    fillColor: srvDetailBg.paintColor
                                    strokeColor: srvDetailBg.paintBorder
                                    strokeWidth: 1

                                    startX: srvDetailBg.tlr; startY: 0
                                    PathLine { x: srvDetailBg.width - srvDetailBg.trr; y: 0 }
                                    PathArc { x: srvDetailBg.width; y: srvDetailBg.trr; radiusX: srvDetailBg.trr; radiusY: srvDetailBg.trr; direction: PathArc.Clockwise }
                                    PathLine { x: srvDetailBg.width; y: srvDetailBg.height - srvDetailBg.brr }
                                    PathArc { x: srvDetailBg.width - srvDetailBg.brr; y: srvDetailBg.height; radiusX: srvDetailBg.brr; radiusY: srvDetailBg.brr; direction: PathArc.Clockwise }
                                    PathLine { x: srvDetailBg.blr; y: srvDetailBg.height }
                                    PathArc { x: 0; y: srvDetailBg.height - srvDetailBg.blr; radiusX: srvDetailBg.blr; radiusY: srvDetailBg.blr; direction: PathArc.Clockwise }
                                    PathLine { x: 0; y: srvDetailBg.tlr }
                                    PathArc { x: srvDetailBg.tlr; y: 0; radiusX: srvDetailBg.tlr; radiusY: srvDetailBg.tlr; direction: PathArc.Clockwise }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                                DankIcon { name: "dns"; size: 16; color: Theme.primary }
                                StyledText { text: "Server"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText; Layout.fillWidth: true }
                                StyledText { text: root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : "Disconnected"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText }
                            }
                        }

                        Item {
                            id: regionDetailItem
                            width: parent.width; height: 38
                            Shape {
                                id: regionDetailBg
                                anchors.fill: parent
                                property real tlr: 6; property real trr: 6; property real blr: 6; property real brr: 6
                                property color paintColor: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)
                                property color paintBorder: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                                ShapePath {
                                    fillColor: regionDetailBg.paintColor
                                    strokeColor: regionDetailBg.paintBorder
                                    strokeWidth: 1

                                    startX: regionDetailBg.tlr; startY: 0
                                    PathLine { x: regionDetailBg.width - regionDetailBg.trr; y: 0 }
                                    PathArc { x: regionDetailBg.width; y: regionDetailBg.trr; radiusX: regionDetailBg.trr; radiusY: regionDetailBg.trr; direction: PathArc.Clockwise }
                                    PathLine { x: regionDetailBg.width; y: regionDetailBg.height - regionDetailBg.brr }
                                    PathArc { x: regionDetailBg.width - regionDetailBg.brr; y: regionDetailBg.height; radiusX: regionDetailBg.brr; radiusY: regionDetailBg.brr; direction: PathArc.Clockwise }
                                    PathLine { x: regionDetailBg.blr; y: regionDetailBg.height }
                                    PathArc { x: 0; y: regionDetailBg.height - regionDetailBg.blr; radiusX: regionDetailBg.blr; radiusY: regionDetailBg.blr; direction: PathArc.Clockwise }
                                    PathLine { x: 0; y: regionDetailBg.tlr }
                                    PathArc { x: regionDetailBg.tlr; y: 0; radiusX: regionDetailBg.tlr; radiusY: regionDetailBg.tlr; direction: PathArc.Clockwise }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                                DankIcon { name: "public"; size: 16; color: Theme.primary }
                                StyledText { text: "Region"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText; Layout.fillWidth: true }
                                StyledText { 
                                    text: root.vpnStatus === "Connected" ? (root.connectedCountryName || root.getCountryName(root.connectedCountry) || "Global") : "Not Connected"
                                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Item {
                            id: protoDetailItem
                            width: parent.width; height: 38
                            Shape {
                                id: protoDetailBg
                                anchors.fill: parent
                                property real tlr: 6; property real trr: 6; property real blr: 12; property real brr: 12
                                property color paintColor: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)
                                property color paintBorder: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                                ShapePath {
                                    fillColor: protoDetailBg.paintColor
                                    strokeColor: protoDetailBg.paintBorder
                                    strokeWidth: 1

                                    startX: protoDetailBg.tlr; startY: 0
                                    PathLine { x: protoDetailBg.width - protoDetailBg.trr; y: 0 }
                                    PathArc { x: protoDetailBg.width; y: protoDetailBg.trr; radiusX: protoDetailBg.trr; radiusY: protoDetailBg.trr; direction: PathArc.Clockwise }
                                    PathLine { x: protoDetailBg.width; y: protoDetailBg.height - protoDetailBg.brr }
                                    PathArc { x: protoDetailBg.width - protoDetailBg.brr; y: protoDetailBg.height; radiusX: protoDetailBg.brr; radiusY: protoDetailBg.brr; direction: PathArc.Clockwise }
                                    PathLine { x: protoDetailBg.blr; y: protoDetailBg.height }
                                    PathArc { x: 0; y: protoDetailBg.height - protoDetailBg.blr; radiusX: protoDetailBg.blr; radiusY: protoDetailBg.blr; direction: PathArc.Clockwise }
                                    PathLine { x: 0; y: protoDetailBg.tlr }
                                    PathArc { x: protoDetailBg.tlr; y: 0; radiusX: protoDetailBg.tlr; radiusY: protoDetailBg.tlr; direction: PathArc.Clockwise }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                                DankIcon { name: "security"; size: 16; color: Theme.primary }
                                StyledText { text: "Protocol"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText; Layout.fillWidth: true }
                                StyledText { 
                                    text: (root.connectedProtocol || root._defaultProtocol || "smart").toUpperCase()
                                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.primary
                                    font.family: "Monospace"
                                }
                            }
                        }
                    }
                }
            }

            // 3. Connect (Main Quick Connect Action Bar + Countries List)
            StyledRect {
                id: connectSection
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                height: connectSectionCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius; color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Column {
                    id: connectSectionCol
                    anchors.fill: parent; anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS
                    Loader {
                        width: parent.width
                        asynchronous: true
                        property string sectionSvg: "assets/icons/Connect.svg"
                        property string sectionTitle: "Connect"
                        sourceComponent: sectionHeaderComponent
                    }

                    Rectangle {
                        id: quickConnBtn
                        width: parent.width; height: 44; radius: Theme.cornerRadius
                        color: maQuickConn.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                        border.color: Theme.primary; border.width: 1
                        opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                        scale: maQuickConn.pressed ? 0.98 : (maQuickConn.containsMouse ? 1.01 : 1.0)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        DankRipple {
                            id: quickConnRipple
                            anchors.fill: parent
                            cornerRadius: Theme.cornerRadius
                            rippleColor: Theme.primary
                        }

                        MouseArea {
                            id: maQuickConn
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.isConnecting && !root.isDisconnecting
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: mouse => quickConnRipple.trigger(mouse.x, mouse.y)
                            onClicked: root.connectVpn("fastest")
                        }

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                            DankIcon { name: "bolt"; size: 18; color: Theme.primary; Layout.alignment: Qt.AlignVCenter }
                            StyledText { text: "Quick Connect (Fastest)"; Layout.fillWidth: true; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.primary }
                        }
                    }

                    Column {
                        id: countriesListCol; width: parent.width; spacing: 2

                        Repeater {
                            model: root.countriesList
                            delegate: Column {
                                width: countriesListCol.width
                                property bool isExpanded: root.expandedCountryCode === modelData.code
                                spacing: isExpanded ? 2 : 0

                                Item {
                                    id: countryItemWrap
                                    width: parent.width; height: 42
                                    opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                                    scale: maCountry.pressed ? 0.98 : (maCountry.containsMouse ? 1.01 : 1.0)
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                    Shape {
                                        id: countryBg
                                        anchors.fill: parent

                                        property real innerRadius: 6
                                        property real outerRadius: 12
                                        property bool isFirstRow: index === 0
                                        property bool isLastRow: index === root.countriesList.length - 1
                                        
                                        property real tlr: (isExpanded || maCountry.containsMouse) ? (height / 2) : (isFirstRow ? outerRadius : innerRadius)
                                        property real trr: (isExpanded || maCountry.containsMouse) ? (height / 2) : (isFirstRow ? outerRadius : innerRadius)
                                        property real blr: (isExpanded || maCountry.containsMouse) ? (height / 2) : (isLastRow ? outerRadius : innerRadius)
                                        property real brr: (isExpanded || maCountry.containsMouse) ? (height / 2) : (isLastRow ? outerRadius : innerRadius)

                                        property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                        property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                        property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                        property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                                        property color paintColor: isExpanded 
                                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) 
                                                : (maCountry.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04))
                                        
                                        property color paintBorder: isExpanded 
                                                ? Theme.primary 
                                                : (maCountry.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15))

                                        Behavior on paintColor { ColorAnimation { duration: 150 } }
                                        Behavior on paintBorder { ColorAnimation { duration: 150 } }

                                        ShapePath {
                                            fillColor: countryBg.paintColor
                                            strokeColor: countryBg.paintBorder
                                            strokeWidth: 1
                                            
                                            startX: countryBg.tlrAnim; startY: 0
                                            PathLine { x: countryBg.width - countryBg.trrAnim; y: 0 }
                                            PathArc { x: countryBg.width; y: countryBg.trrAnim; radiusX: countryBg.trrAnim; radiusY: countryBg.trrAnim; direction: PathArc.Clockwise }
                                            PathLine { x: countryBg.width; y: countryBg.height - countryBg.brrAnim }
                                            PathArc { x: countryBg.width - countryBg.brrAnim; y: countryBg.height; radiusX: countryBg.brrAnim; radiusY: countryBg.brrAnim; direction: PathArc.Clockwise }
                                            PathLine { x: countryBg.blrAnim; y: countryBg.height }
                                            PathArc { x: 0; y: countryBg.height - countryBg.blrAnim; radiusX: countryBg.blrAnim; radiusY: countryBg.blrAnim; direction: PathArc.Clockwise }
                                            PathLine { x: 0; y: countryBg.tlrAnim }
                                            PathArc { x: countryBg.tlrAnim; y: 0; radiusX: countryBg.tlrAnim; radiusY: countryBg.tlrAnim; direction: PathArc.Clockwise }
                                        }
                                    }

                                    DankRipple {
                                        id: countryRipple
                                        anchors.fill: parent
                                        cornerRadius: countryBg.tlrAnim
                                        rippleColor: Theme.primary
                                    }

                                    MouseArea {
                                        id: maCountry; anchors.fill: parent; hoverEnabled: true
                                        enabled: !root.isConnecting && !root.isDisconnecting
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onPressed: mouse => countryRipple.trigger(mouse.x, mouse.y)
                                        onClicked: {
                                            if (root.expandedCountryCode === modelData.code) {
                                                root.expandedCountryCode = "";
                                            } else {
                                                root.expandedCountryCode = modelData.code;
                                            }
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                                        
                                        Item {
                                            width: 24; height: 24
                                            Layout.alignment: Qt.AlignVCenter
                                            StyledText {
                                                text: modelData.flag
                                                font.pixelSize: 22
                                                anchors.centerIn: parent
                                            }
                                        }

                                        StyledText { text: modelData.name; Layout.fillWidth: true; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText; Layout.alignment: Qt.AlignVCenter }
                                        
                                        DankIcon { 
                                            name: "expand_more"
                                            size: 18
                                            color: Theme.surfaceVariantText
                                            Layout.alignment: Qt.AlignVCenter
                                            rotation: isExpanded ? 180 : 0
                                            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                                        }
                                    }
                                }

                                Item {
                                    id: expContainer
                                    width: parent.width
                                    height: isExpanded ? Math.min(serverSubCol.implicitHeight, 184) : 0
                                    clip: true
                                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    opacity: isExpanded ? 1.0 : 0.0

                                    Flickable {
                                        anchors.fill: parent
                                        contentWidth: expContainer.width
                                        contentHeight: serverSubCol.implicitHeight
                                        boundsBehavior: Flickable.StopAtBounds
                                        clip: true

                                        Column {
                                            id: serverSubCol
                                            width: expContainer.width
                                            spacing: 2
                                            padding: 2

                                            Item {
                                                id: fastestServerItem
                                                width: parent.width; height: 38
                                                opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                                                scale: maFastestServer.pressed ? 0.98 : (maFastestServer.containsMouse ? 1.01 : 1.0)
                                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                                Shape {
                                                    id: fastestBg
                                                    anchors.fill: parent
                                                    property real tlr: maFastestServer.containsMouse ? (height / 2) : 8
                                                    property real trr: maFastestServer.containsMouse ? (height / 2) : 8
                                                    property real blr: maFastestServer.containsMouse ? (height / 2) : 4
                                                    property real brr: maFastestServer.containsMouse ? (height / 2) : 4

                                                    property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                                                    property color paintColor: maFastestServer.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                                    property color paintBorder: Theme.primary
                                                    Behavior on paintColor { ColorAnimation { duration: 150 } }

                                                    ShapePath {
                                                        fillColor: fastestBg.paintColor
                                                        strokeColor: fastestBg.paintBorder
                                                        strokeWidth: 1

                                                        startX: fastestBg.tlrAnim; startY: 0
                                                        PathLine { x: fastestBg.width - fastestBg.trrAnim; y: 0 }
                                                        PathArc { x: fastestBg.width; y: fastestBg.trrAnim; radiusX: fastestBg.trrAnim; radiusY: fastestBg.trrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: fastestBg.width; y: fastestBg.height - fastestBg.brrAnim }
                                                        PathArc { x: fastestBg.width - fastestBg.brrAnim; y: fastestBg.height; radiusX: fastestBg.brrAnim; radiusY: fastestBg.brrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: fastestBg.blrAnim; y: fastestBg.height }
                                                        PathArc { x: 0; y: fastestBg.height - fastestBg.blrAnim; radiusX: fastestBg.blrAnim; radiusY: fastestBg.blrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: 0; y: fastestBg.tlrAnim }
                                                        PathArc { x: fastestBg.tlrAnim; y: 0; radiusX: fastestBg.tlrAnim; radiusY: fastestBg.tlrAnim; direction: PathArc.Clockwise }
                                                    }
                                                }

                                                DankRipple {
                                                    id: fastestServerRipple
                                                    anchors.fill: parent
                                                    cornerRadius: fastestBg.tlrAnim
                                                    rippleColor: Theme.primary
                                                }

                                                MouseArea {
                                                    id: maFastestServer
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: !root.isConnecting && !root.isDisconnecting
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onPressed: mouse => fastestServerRipple.trigger(mouse.x, mouse.y)
                                                    onClicked: root.connectVpn(modelData.target)
                                                }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                                                    DankIcon { name: "bolt"; size: 16; color: Theme.primary }
                                                    StyledText { text: "Fastest " + modelData.name + " Server"; font.pixelSize: Theme.fontSizeSmall - 1; font.weight: Font.Bold; color: Theme.primary; Layout.fillWidth: true }
                                                    StyledText { text: "Connect"; font.pixelSize: Theme.fontSizeSmall - 2; font.weight: Font.Bold; color: Theme.primary }
                                                }
                                            }

                                            Repeater {
                                                model: modelData.servers
                                                delegate: Item {
                                                    id: serverItemRect
                                                    width: parent.width; height: 34
                                                    opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                                                    scale: maSrv.pressed ? 0.98 : (maSrv.containsMouse ? 1.01 : 1.0)
                                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                                    Shape {
                                                        id: srvBg
                                                        anchors.fill: parent
                                                        property bool isLastSrv: index === modelData.servers.length - 1
                                                        property real tlr: maSrv.containsMouse ? (height / 2) : 4
                                                        property real trr: maSrv.containsMouse ? (height / 2) : 4
                                                        property real blr: maSrv.containsMouse ? (height / 2) : (isLastSrv ? 8 : 4)
                                                        property real brr: maSrv.containsMouse ? (height / 2) : (isLastSrv ? 8 : 4)

                                                        property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                        property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                        property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                        property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                                                        property color paintColor: maSrv.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)
                                                        property color paintBorder: maSrv.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                                                        Behavior on paintColor { ColorAnimation { duration: 150 } }
                                                        Behavior on paintBorder { ColorAnimation { duration: 150 } }

                                                        ShapePath {
                                                            fillColor: srvBg.paintColor
                                                            strokeColor: srvBg.paintBorder
                                                            strokeWidth: 1

                                                            startX: srvBg.tlrAnim; startY: 0
                                                            PathLine { x: srvBg.width - srvBg.trrAnim; y: 0 }
                                                            PathArc { x: srvBg.width; y: srvBg.trrAnim; radiusX: srvBg.trrAnim; radiusY: srvBg.trrAnim; direction: PathArc.Clockwise }
                                                            PathLine { x: srvBg.width; y: srvBg.height - srvBg.brrAnim }
                                                            PathArc { x: srvBg.width - srvBg.brrAnim; y: srvBg.height; radiusX: srvBg.brrAnim; radiusY: srvBg.brrAnim; direction: PathArc.Clockwise }
                                                            PathLine { x: srvBg.blrAnim; y: srvBg.height }
                                                            PathArc { x: 0; y: srvBg.height - srvBg.blrAnim; radiusX: srvBg.blrAnim; radiusY: srvBg.blrAnim; direction: PathArc.Clockwise }
                                                            PathLine { x: 0; y: srvBg.tlrAnim }
                                                            PathArc { x: srvBg.tlrAnim; y: 0; radiusX: srvBg.tlrAnim; radiusY: srvBg.tlrAnim; direction: PathArc.Clockwise }
                                                        }
                                                    }

                                                    DankRipple {
                                                        id: srvRipple
                                                        anchors.fill: parent
                                                        cornerRadius: srvBg.tlrAnim
                                                        rippleColor: Theme.primary
                                                    }

                                                    MouseArea {
                                                        id: maSrv; anchors.fill: parent; hoverEnabled: true
                                                        enabled: !root.isConnecting && !root.isDisconnecting
                                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onPressed: mouse => srvRipple.trigger(mouse.x, mouse.y)
                                                        onClicked: root.connectVpn(modelData.target)
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                                                        DankIcon { name: "dns"; size: 14; color: Theme.surfaceText; opacity: 0.7 }
                                                        StyledText { text: modelData.name; font.pixelSize: Theme.fontSizeSmall - 1; color: Theme.surfaceText; Layout.fillWidth: true }
                                                        StyledText { text: "Load: " + modelData.load; font.pixelSize: Theme.fontSizeSmall - 2; font.family: "Monospace"; color: Theme.primary }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutContainer
            
            Component.onCompleted: root.popoutOpen = true
            Component.onDestruction: root.popoutOpen = false

            headerText: ""
            detailsText: ""
            showCloseButton: false

            Loader {
                width: parent.width
                sourceComponent: vpnWidgetContent
                readonly property bool inCC: false
            }
        }
    }
}
