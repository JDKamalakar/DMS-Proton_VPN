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
    
    popoutWidth: 320
    popoutHeight: 0

    // --- CC Support ---
    ccWidgetIcon: "vpn_key"
    ccWidgetPrimaryText: "Proton VPN"
    ccWidgetSecondaryText: root.connectionTypeLabel.startsWith("Error:") ? root.connectionTypeLabel : (root.isConnecting ? "Connecting..." : (root.isDisconnecting ? "Disconnecting..." : (root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : "Disconnected")))
    ccWidgetIsActive: root.vpnStatus === "Connected" || root.isConnecting || root.isDisconnecting
    ccDetailHeight: 480
    onCcWidgetExpanded: root.refresh()
    onCcWidgetToggled: root.quickConnect()
    
    ccDetailContent: Component {
        ScrollView {
            id: ccScrollView
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            
            Loader {
                width: ccScrollView.availableWidth
                asynchronous: true
                sourceComponent: vpnWidgetContent
                readonly property bool inCC: true
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
    property string downloadSpeed: "0 B/s"
    property string uploadSpeed: "0 B/s"

    function getShortServerName(srv) {
        if (!srv || srv === "Connected") return "VPN";
        let s = srv.replace("-FREE", "").replace("FREE", "").trim();
        return s;
    }
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

    property string _quickConnectType: PluginService.loadPluginData("protonVPN", "quickConnectType", "fastest")
    property string _quickConnectCountry: PluginService.loadPluginData("protonVPN", "quickConnectCountry", "US")
    property string _quickConnectCustom: PluginService.loadPluginData("protonVPN", "quickConnectCustom", "")

    PluginGlobalVar { varName: "defaultProtocol"; onValueChanged: function(val) { if (val !== undefined && val !== null) root._defaultProtocol = val; } }
    PluginGlobalVar { varName: "quickConnectType"; onValueChanged: function(val) { if (val !== undefined && val !== null) root._quickConnectType = val; } }
    PluginGlobalVar { varName: "quickConnectCountry"; onValueChanged: function(val) { if (val !== undefined && val !== null) root._quickConnectCountry = val; } }
    PluginGlobalVar { varName: "quickConnectCustom"; onValueChanged: function(val) { if (val !== undefined && val !== null) root._quickConnectCustom = val; } }

    function quickConnect() {
        if (root.isConnecting || root.isDisconnecting || connectProc.running || disconnectProc.running) return;

        if (root.vpnStatus === "Connected") {
            root.disconnectVpn();
            return;
        }
        
        let type = PluginService.loadPluginData("protonVPN", "quickConnectType", root._quickConnectType || "fastest");
        if (type === "country_fastest") {
            let target = PluginService.loadPluginData("protonVPN", "quickConnectCountry", root._quickConnectCountry || "US");
            root.connectVpn(target);
        } else if (type === "country_random") {
            if (root.countriesList && root.countriesList.length > 0) {
                let randomIndex = Math.floor(Math.random() * root.countriesList.length);
                let target = root.countriesList[randomIndex].code;
                root.connectVpn(target);
            } else {
                root.connectVpn("fastest");
            }
        } else if (type === "custom") {
            let target = (PluginService.loadPluginData("protonVPN", "quickConnectCustom", root._quickConnectCustom || "") || "").trim();
            if (!target) {
                root.vpnStatus = "Disconnected";
                root.connectionTypeLabel = "Error: Custom server not specified";
                return;
            }
            root.connectVpn(target);
        } else {
            root.connectVpn("fastest");
        }
    }

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

    function toTitleCase(str) {
        if (!str) return "";
        return str.charAt(0).toUpperCase() + str.slice(1).toLowerCase();
    }

    // --- Scanners & Process Execution ---
    Process {
        id: statusScanner
        command: ["bash", "-c", "timeout 2 pvpnctl status --format waybar 2>/dev/null || echo '{\"class\":\"disconnected\"}'; echo '---'; timeout 2 pvpnctl status 2>/dev/null || echo 'Disconnected'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let raw = text.trim();
                    if (!raw) return;
                    
                    if (raw.includes("Cannot connect to pvpnd")) {
                        if (!root.isConnecting && !root.isDisconnecting && !connectProc.running && !disconnectProc.running) {
                            root.vpnStatus = "Daemon Stopped";
                            root.isConnecting = false;
                            root.isDisconnecting = false;
                            root.connectionTypeLabel = "pvpnd Daemon Stopped";
                        }
                        return;
                    }

                    let parts = raw.split('---');
                    let waybarStr = parts[0].trim();
                    let rawStatusStr = parts.length > 1 ? parts[1].trim() : "";
                    
                    let data = { "class": "disconnected", "text": "" };
                    try { data = JSON.parse(waybarStr); } catch(e) {}
                    
                    let isConnected = (data.class === "connected") || rawStatusStr.toLowerCase().includes("status: connected") || rawStatusStr.toLowerCase().includes("connected to");
                    let isDaemonConnecting = (data.class === "connecting") || rawStatusStr.toLowerCase().includes("connecting");

                    if (root.isDisconnecting || disconnectProc.running) {
                        root.vpnStatus = "Disconnecting...";
                        root.isDisconnecting = true;
                        root.isConnecting = false;
                    } else if (isConnected) {
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

                        let dl = "";
                        let ul = "";
                        let combinedText = rawStatusStr + "\n" + (data.tooltip || "") + "\n" + (data.text || "");
                        let stLines = combinedText.split('\n');
                        for (let k = 0; k < stLines.length; k++) {
                            let sl = stLines[k].trim();
                            let slow = sl.toLowerCase();
                            if (slow.includes("download") || slow.includes("down:") || slow.includes("dl:")) {
                                let parts = sl.split(':');
                                if (parts.length > 1) dl = parts.slice(1).join(':').trim();
                            }
                            if (slow.includes("upload") || slow.includes("up:") || slow.includes("ul:")) {
                                let parts = sl.split(':');
                                if (parts.length > 1) ul = parts.slice(1).join(':').trim();
                            }
                        }
                        root.downloadSpeed = dl || "0 B/s";
                        root.uploadSpeed = ul || "0 B/s";
                    } else if (root.isConnecting || connectProc.running || connectTimeoutTimer.running || isDaemonConnecting) {
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
                        root.downloadSpeed = "0 B/s";
                        root.uploadSpeed = "0 B/s";
                        if (!root.connectionTypeLabel.startsWith("Error:")) {
                            root.connectionTypeLabel = "Disconnected";
                        }
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
    property bool _showConnectContainer: PluginService.loadPluginData("protonVPN", "showConnectContainer", true)
    property bool _showSpeedContainer: PluginService.loadPluginData("protonVPN", "showSpeedContainer", true)

    PluginGlobalVar { 
        varName: "paidServersOnly"
        onValueChanged: function(val) { 
            if (val !== undefined && val !== null) {
                root._paidServersOnly = val; 
                root._lastServersJson = "";
                root.fetchServers();
            }
        } 
    }
    PluginGlobalVar { varName: "showConnectContainer"; onValueChanged: function(val) { if (val !== undefined && val !== null) root._showConnectContainer = val; } }
    PluginGlobalVar { varName: "showSpeedContainer"; onValueChanged: function(val) { if (val !== undefined && val !== null) root._showSpeedContainer = val; } }

    Process {
        id: serversScanner
        command: ["bash", "-c", "timeout 3 pvpnctl servers 2>/dev/null || echo ''"]
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
                    let srvList = parsedByCountry[code];
                    srvList.sort((a, b) => (parseInt(a.load, 10) || 0) - (parseInt(b.load, 10) || 0));
                    newCountriesList.push({
                        name: root.getCountryName(code),
                        code: code,
                        flag: root.getCountryFlag(code),
                        target: code,
                        servers: srvList
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
        stdout: StdioCollector { id: connectStdout }
        stderr: StdioCollector { id: connectStderr }
        onExited: {
            if (exitCode !== 0) {
                root.isConnecting = false;
                root.isDisconnecting = false;
                root.vpnStatus = "Disconnected";
                let errText = connectStderr.text ? connectStderr.text.trim() : (connectStdout.text ? connectStdout.text.trim() : "");
                if (errText) {
                    errText = errText.split('\n')[0].trim();
                }
                root.connectionTypeLabel = errText ? ("Error: " + errText) : "Connection Failed";
                connectTimeoutTimer.stop();
            } else {
                root.isConnecting = true; // keep connecting true until statusScanner confirms connected
            }
            root.refresh();
            statusTimer.restart();
        }
    }

    Process {
        id: disconnectProc
        running: false
        onExited: {
            root.isDisconnecting = false;
            root.isConnecting = false;
            if (exitCode === 0) {
                root.vpnStatus = "Disconnected";
                root.connectedServer = "";
                root.connectedIp = "";
                root.connectedCountry = "";
                root.connectedCountryName = "";
                root.connectedProtocol = "";
                root.connectionTypeLabel = "Disconnected";
            }
            connectTimeoutTimer.stop();
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
            connectProc.running = false;
            disconnectProc.running = false;
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
        if (connectProc.running || disconnectProc.running) return;
        root.isConnecting = true;
        root.isDisconnecting = false;
        root.vpnStatus = "Connecting...";
        let tgt = target || root._defaultConnectTarget || "fastest";
        root.connectionTypeLabel = "Connecting to " + tgt + "...";
        connectTimeoutTimer.restart();
        
        let proto = root._defaultProtocol || "smart";
        let cmd = "timeout 15 pvpnctl connect \"" + tgt + "\"";
        if (proto !== "smart") {
            cmd += " --protocol " + proto;
        }
        connectProc.command = ["bash", "-c", cmd];
        connectProc.running = true;
        statusTimer.restart();
    }

    function disconnectVpn() {
        if (connectProc.running || disconnectProc.running) return;
        root.isDisconnecting = true;
        root.isConnecting = false;
        root.vpnStatus = "Disconnecting...";
        root.connectionTypeLabel = "Disconnecting...";
        connectTimeoutTimer.restart();
        
        disconnectProc.command = ["bash", "-c", "timeout 10 pvpnctl disconnect"];
        disconnectProc.running = true;
        statusTimer.restart();
    }

    function reconnectVpn() {
        if (connectProc.running || disconnectProc.running) return;
        
        let target = root.connectedServer || root.connectedCountry || root._quickConnectCountry || "fastest";
        
        root.isConnecting = true;
        root.isDisconnecting = false;
        root.vpnStatus = "Connecting...";
        root.connectionTypeLabel = "Reconnecting to " + target + "...";
        connectTimeoutTimer.restart();
        
        let proto = root._defaultProtocol || "smart";
        let cmd = "pvpnctl disconnect 2>/dev/null; sleep 0.5; pvpnctl connect \"" + target + "\"";
        if (proto !== "smart") {
            cmd += " --protocol " + proto;
        }
        connectProc.command = ["timeout", "15", "bash", "-c", cmd];
        connectProc.running = true;
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
                        Item {
                            anchors.fill: parent
                            Image {
                                id: pillMonoImgH
                                source: Qt.resolvedUrl(Theme.isLightMode ? "assets/icons/Proton-VPN_Mono_Dark.svg" : "assets/icons/Proton-VPN_Mono.svg")
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                        }
                    }
                }
            }
            Item {
                height: 20; Layout.fillWidth: false; Layout.preferredWidth: Math.max(pillTextH.implicitWidth, 60); Layout.alignment: Qt.AlignVCenter
                StyledText { 
                    id: pillTextH
                    text: root.connectionTypeLabel.startsWith("Error:") ? root.connectionTypeLabel : (root.isConnecting ? "Connecting..." : (root.isDisconnecting ? "Disconnecting..." : (root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : "Disconnected")))
                    font.pixelSize: Theme.fontSizeSmall - 1; font.weight: Font.Medium
                    color: root.vpnStatus === "Connected" ? Theme.primary : (root.connectionTypeLabel.startsWith("Error:") ? "#ff5555" : (Theme.widgetTextColor || Theme.surfaceText))
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        ColumnLayout {
            spacing: 2
            anchors.horizontalCenter: parent.horizontalCenter

            Item {
                width: 18; height: 18
                Layout.alignment: Qt.AlignHCenter
                Loader {
                    id: pillIconLoaderV
                    anchors.fill: parent
                    asynchronous: true
                    sourceComponent: (root.loading || root.isConnecting || root.isDisconnecting) ? refreshingIconComp : standardPillIconV
                    
                    Component {
                        id: standardPillIconV
                        Item {
                            anchors.fill: parent
                            Image {
                                id: pillMonoImgV
                                source: Qt.resolvedUrl(Theme.isLightMode ? "assets/icons/Proton-VPN_Mono_Dark.svg" : "assets/icons/Proton-VPN_Mono.svg")
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                        }
                    }
                }
            }

            Item {
                width: 26; height: 12
                clip: true
                Layout.alignment: Qt.AlignHCenter

                StyledText {
                    id: pillTextV
                    text: root.isConnecting || root.isDisconnecting ? "..." : (root.vpnStatus === "Connected" ? root.getShortServerName(root.connectedServer) : "...")
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: root.vpnStatus === "Connected" ? Theme.primary : (Theme.widgetTextColor || Theme.surfaceText)
                    anchors.horizontalCenter: parent.horizontalCenter
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


    // --- Content Component ---
    Component {
        id: vpnWidgetContent
        Column {
            id: mainCol; width: parent.width; spacing: Theme.spacingM
            property bool inCC: (parent && parent.inCC) || false

            padding: inCC ? 16 : 0
            topPadding: 0
            bottomPadding: inCC ? 16 : 2

            // 1. Header Card
            StyledRect {
                width: Math.max(0, parent.width - (mainCol.inCC ? 32 : 0)); anchors.horizontalCenter: parent.horizontalCenter; height: 72
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                RowLayout {
                    anchors.fill: parent; anchors.margins: Theme.spacingM;
                    Rectangle {
                        width: 42; height: 42; radius: 21
                        color: root.vpnStatus === "Connected" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4)
                        border.color: root.vpnStatus === "Connected" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) : Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.15)
                        border.width: 1

                        Item {
                            width: 24; height: 24
                            anchors.centerIn: parent
                            Image {
                                id: defaultIcon
                                source: Qt.resolvedUrl("assets/icons/Proton-VPN.svg")
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                visible: !(root.vpnStatus === "Connected" && root.connectedCountry)
                            }
                            Text {
                                text: (root.vpnStatus === "Connected" && root.connectedCountry) ? root.getCountryFlag(root.connectedCountry) : ""
                                font.pixelSize: 22
                                font.family: "Noto Color Emoji, Apple Color Emoji, Segoe UI Emoji, EmojiOne Color, Twemoji, sans-serif"
                                color: Theme.surfaceText
                                anchors.centerIn: parent
                                visible: text !== ""
                            }
                        }
                    }

                    Column {
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 0
                        StyledText { 
                            text: "Proton VPN"
                            font.bold: true; font.pixelSize: Theme.fontSizeLarge; color: Theme.surfaceText 
                            elide: Text.ElideRight
                        }
                        
                        StyledText { 
                            id: statusLabelText
                            Layout.fillWidth: true
                            text: root.connectionTypeLabel.startsWith("Error:") 
                                ? root.connectionTypeLabel 
                                : (root.isConnecting 
                                    ? (root.connectionTypeLabel.startsWith("Reconnecting") || root.connectionTypeLabel.startsWith("Connecting") ? root.connectionTypeLabel : "Connecting...") 
                                    : (root.isDisconnecting 
                                        ? "Disconnecting..." 
                                        : (root.vpnStatus === "Connected" ? (root.connectedCountryName || root.connectedServer || "Connected") : "Disconnected")))
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: (root.vpnStatus === "Connected" || root.isConnecting) ? Theme.primary : (root.connectionTypeLabel.startsWith("Error:") ? "#ff5555" : Theme.surfaceVariantText)
                            font.family: "Monospace"
                            opacity: 0.8
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: headerActionBtnContainer
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4

                        // Main Button (Connect / Disconnect icon-only when connected)
                        Item {
                            id: mainActionBtn
                            width: (root.isConnecting || root.isDisconnecting || root.vpnStatus === "Connected") ? 38 : 106
                            height: 38

                            Behavior on width { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                            scale: maMainBtn.pressed ? 0.92 : (maMainBtn.containsMouse ? 1.05 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                            Rectangle {
                                id: mainActionBg
                                anchors.fill: parent
                                readonly property bool showReconnect: root.vpnStatus === "Connected" && !root.isConnecting && !root.isDisconnecting
                                topLeftRadius: (root.isConnecting || root.isDisconnecting || maMainBtn.pressed) ? height / 2 : Theme.cornerRadius
                                bottomLeftRadius: (root.isConnecting || root.isDisconnecting || maMainBtn.pressed) ? height / 2 : Theme.cornerRadius
                                topRightRadius: (root.isConnecting || root.isDisconnecting || maMainBtn.pressed) ? height / 2 : (showReconnect ? 4 : Theme.cornerRadius)
                                bottomRightRadius: (root.isConnecting || root.isDisconnecting || maMainBtn.pressed) ? height / 2 : (showReconnect ? 4 : Theme.cornerRadius)

                                color: maMainBtn.pressed 
                                    ? Theme.withAlpha(Theme.primary, 0.2) 
                                    : (maMainBtn.containsMouse 
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) 
                                        : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4))
                                border.width: 1
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, maMainBtn.containsMouse ? 0.3 : 0.15)

                                Behavior on color { ColorAnimation { duration: Theme.popoutAnimationDuration } }
                                Behavior on border.color { ColorAnimation { duration: Theme.popoutAnimationDuration } }
                                Behavior on topLeftRadius { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                                Behavior on bottomLeftRadius { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                                Behavior on topRightRadius { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                                Behavior on bottomRightRadius { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: (root.isConnecting || root.isDisconnecting || root.vpnStatus === "Connected") ? 0 : 6

                                DankIcon {
                                    id: connBtnIcon
                                    name: (root.isConnecting || root.isDisconnecting) ? "cached" : (root.vpnStatus === "Connected" ? "link_off" : "link")
                                    size: (root.isConnecting || root.isDisconnecting) ? 20 : 18
                                    color: Theme.primary
                                    Layout.alignment: Qt.AlignVCenter

                                    RotationAnimation on rotation {
                                        from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: root.isConnecting || root.isDisconnecting
                                        onRunningChanged: { if (!running) rotation = 0; }
                                    }
                                }

                                StyledText {
                                    text: "Connect"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Normal
                                    color: Theme.primary
                                    visible: opacity > 0
                                    opacity: (root.isConnecting || root.isDisconnecting || root.vpnStatus === "Connected") ? 0.0 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            DankRipple {
                                id: mainBtnRipple
                                anchors.fill: parent
                                cornerRadius: mainActionBg.topLeftRadius
                                rippleColor: Theme.primary
                            }

                            MouseArea {
                                id: maMainBtn
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !root.isConnecting && !root.isDisconnecting
                                cursorShape: Qt.PointingHandCursor
                                onPressed: mouse => mainBtnRipple.trigger(mouse.x, mouse.y)
                                onClicked: {
                                    if (root.vpnStatus === "Connected") {
                                        root.disconnectVpn();
                                    } else {
                                        root.quickConnect();
                                    }
                                }
                            }
                        }

                        // Reconnect Button (smoothly animates width & opacity on enter/exit)
                        Item {
                            id: reconnectBtn
                            readonly property bool showReconnect: root.vpnStatus === "Connected" && !root.isConnecting && !root.isDisconnecting
                            width: showReconnect ? 38 : 0
                            height: 38
                            opacity: showReconnect ? 1.0 : 0.0
                            visible: width > 0 || opacity > 0
                            clip: true

                            Behavior on width { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                            Behavior on opacity { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }

                            scale: maReconnectBtn.pressed ? 0.92 : (maReconnectBtn.containsMouse ? 1.05 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                            Rectangle {
                                id: reconnectBg
                                anchors.fill: parent
                                topLeftRadius: maReconnectBtn.pressed ? height / 2 : 4
                                bottomLeftRadius: maReconnectBtn.pressed ? height / 2 : 4
                                topRightRadius: maReconnectBtn.pressed ? height / 2 : Theme.cornerRadius
                                bottomRightRadius: maReconnectBtn.pressed ? height / 2 : Theme.cornerRadius

                                color: maReconnectBtn.pressed 
                                    ? Theme.withAlpha(Theme.primary, 0.2) 
                                    : (maReconnectBtn.containsMouse 
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) 
                                        : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4))
                                border.width: 1
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, maReconnectBtn.containsMouse ? 0.3 : 0.15)

                                Behavior on color { ColorAnimation { duration: Theme.popoutAnimationDuration } }
                                Behavior on border.color { ColorAnimation { duration: Theme.popoutAnimationDuration } }
                                Behavior on topLeftRadius { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                                Behavior on bottomLeftRadius { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                                Behavior on topRightRadius { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                                Behavior on bottomRightRadius { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.InOutQuad } }
                            }

                            DankIcon {
                                name: "sync_alt"
                                size: 18
                                color: Theme.primary
                                anchors.centerIn: parent
                                rotation: maReconnectBtn.containsMouse ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Theme.popoutAnimationDuration; easing.type: Easing.OutBack } }
                            }

                            DankRipple {
                                id: reconnectBtnRipple
                                anchors.fill: parent
                                cornerRadius: reconnectBg.topLeftRadius
                                rippleColor: Theme.primary
                            }

                            MouseArea {
                                id: maReconnectBtn
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: mouse => reconnectBtnRipple.trigger(mouse.x, mouse.y)
                                onClicked: root.reconnectVpn()
                            }
                        }
                    }
                }
            }

            // 2. Connection Details Container
            StyledRect {
                width: Math.max(0, parent.width - (mainCol.inCC ? 32 : 0)); anchors.horizontalCenter: parent.horizontalCenter
                height: connDetailsCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius; color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                Column {
                    id: connDetailsCol
                    anchors.fill: parent; anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingXS
                        DankIcon {
                            name: "info"
                            size: 14
                            color: Theme.surfaceText
                            Layout.alignment: Qt.AlignVCenter
                        }
                        StyledText {
                            text: "Details"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    Column {
                        id: connDetailsListCol
                        width: parent.width
                        spacing: 4

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
                                DankIcon { name: "dns"; size: 16; color: Theme.surfaceText; opacity: 0.7; Layout.alignment: Qt.AlignVCenter }
                                StyledText { text: "Server"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                                Item { Layout.fillWidth: true }
                                StyledText { text: root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : "Disconnected"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Normal; color: root.vpnStatus === "Connected" ? Theme.primary : Theme.surfaceVariantText }
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
                                DankIcon { name: "location_on"; size: 16; color: Theme.surfaceText; opacity: 0.7; Layout.alignment: Qt.AlignVCenter }
                                StyledText { text: "Region"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                                Item { Layout.fillWidth: true }
                                StyledText { 
                                    text: root.vpnStatus === "Connected" ? (root.connectedCountryName || root.getCountryName(root.connectedCountry) || "Global") : "Not Connected"
                                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Normal; color: root.vpnStatus === "Connected" ? Theme.primary : Theme.surfaceVariantText
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
                                DankIcon { name: "security"; size: 16; color: Theme.surfaceText; opacity: 0.7; Layout.alignment: Qt.AlignVCenter }
                                StyledText { text: "Protocol"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                                Item { Layout.fillWidth: true }
                                StyledText { 
                                    text: root.toTitleCase(root.connectedProtocol || root._defaultProtocol || "smart")
                                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Normal; color: Theme.primary
                                }
                            }
                        }
                    }
                }
            }

            // 2b. Speed Container
            StyledRect {
                width: Math.max(0, parent.width - (mainCol.inCC ? 32 : 0)); anchors.horizontalCenter: parent.horizontalCenter
                height: 72
                radius: Theme.cornerRadius; color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                visible: root.vpnStatus === "Connected" && root._showSpeedContainer

                RowLayout {
                    anchors.fill: parent; anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    // Download Box
                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)
                            border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                            border.width: 1
                        }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 6
                            DankIcon { name: "arrow_downward"; size: 16; color: Theme.primary; Layout.alignment: Qt.AlignVCenter }
                            Column {
                                Layout.alignment: Qt.AlignVCenter; spacing: 0
                                StyledText { text: "Download"; font.pixelSize: Theme.fontSizeSmall - 2; color: Theme.surfaceVariantText }
                                StyledText { text: root.downloadSpeed; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText }
                            }
                        }
                    }

                    // Upload Box
                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)
                            border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                            border.width: 1
                        }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 6
                            DankIcon { name: "arrow_upward"; size: 16; color: Theme.primary; Layout.alignment: Qt.AlignVCenter }
                            Column {
                                Layout.alignment: Qt.AlignVCenter; spacing: 0
                                StyledText { text: "Upload"; font.pixelSize: Theme.fontSizeSmall - 2; color: Theme.surfaceVariantText }
                                StyledText { text: root.uploadSpeed; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText }
                            }
                        }
                    }
                }
            }

            // 3. Connect (Main Quick Connect Action Bar + Countries List)
            StyledRect {
                id: connectSection
                width: Math.max(0, parent.width - (mainCol.inCC ? 32 : 0))
                anchors.horizontalCenter: parent.horizontalCenter
                height: connectSectionCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius; color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                visible: root._showConnectContainer
                
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Column {
                    id: connectSectionCol
                    anchors.fill: parent; anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS
                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingXS
                        Item {
                            width: 14; height: 14
                            Layout.alignment: Qt.AlignVCenter
                            Image {
                                id: connectHeaderSvg
                                source: Qt.resolvedUrl("assets/icons/Connect.svg")
                                anchors.fill: parent
                                sourceSize.width: 14; sourceSize.height: 14
                                smooth: true
                            }
                            MultiEffect {
                                anchors.fill: connectHeaderSvg
                                source: connectHeaderSvg
                                colorization: 1.0
                                colorizationColor: Theme.surfaceText
                            }
                        }
                        StyledText {
                            text: "Connect"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    Item {
                        id: quickConnBtn
                        width: parent.width; height: 44
                        opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                        scale: maQuickConn.pressed ? 0.98 : (maQuickConn.containsMouse ? 1.01 : 1.0)
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        Shape {
                            id: quickConnBg
                            anchors.fill: parent

                            property real outerRadius: 12
                            property real tlr: maQuickConn.containsMouse ? (height / 2) : outerRadius
                            property real trr: maQuickConn.containsMouse ? (height / 2) : outerRadius
                            property real blr: maQuickConn.containsMouse ? (height / 2) : outerRadius
                            property real brr: maQuickConn.containsMouse ? (height / 2) : outerRadius

                            property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                            property color paintColor: maQuickConn.containsMouse 
                                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) 
                                    : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                            property color paintBorder: Theme.primary

                            Behavior on paintColor { ColorAnimation { duration: 150 } }

                            ShapePath {
                                fillColor: quickConnBg.paintColor
                                strokeColor: quickConnBg.paintBorder
                                strokeWidth: 1

                                startX: quickConnBg.tlrAnim; startY: 0
                                PathLine { x: quickConnBg.width - quickConnBg.trrAnim; y: 0 }
                                PathArc { x: quickConnBg.width; y: quickConnBg.trrAnim; radiusX: quickConnBg.trrAnim; radiusY: quickConnBg.trrAnim; direction: PathArc.Clockwise }
                                PathLine { x: quickConnBg.width; y: quickConnBg.height - quickConnBg.brrAnim }
                                PathArc { x: quickConnBg.width - quickConnBg.brrAnim; y: quickConnBg.height; radiusX: quickConnBg.brrAnim; radiusY: quickConnBg.brrAnim; direction: PathArc.Clockwise }
                                PathLine { x: quickConnBg.blrAnim; y: quickConnBg.height }
                                PathArc { x: 0; y: quickConnBg.height - quickConnBg.blrAnim; radiusX: quickConnBg.blrAnim; radiusY: quickConnBg.blrAnim; direction: PathArc.Clockwise }
                                PathLine { x: 0; y: quickConnBg.tlrAnim }
                                PathArc { x: quickConnBg.tlrAnim; y: 0; radiusX: quickConnBg.tlrAnim; radiusY: quickConnBg.tlrAnim; direction: PathArc.Clockwise }
                            }
                        }

                        DankRipple {
                            id: quickConnRipple
                            anchors.fill: parent
                            clip: true
                            cornerRadius: quickConnBg.tlrAnim
                            rippleColor: Theme.primary
                        }

                        MouseArea {
                            id: maQuickConn
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.isDisconnecting
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: mouse => quickConnRipple.trigger(mouse.x, mouse.y)
                            onClicked: root.quickConnect()
                        }

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                            DankIcon { name: "bolt"; size: 18; color: Theme.isDarkMode ? "#ffffff" : "#000000"; Layout.alignment: Qt.AlignVCenter }
                            StyledText { 
                                text: {
                                    let t = PluginService.loadPluginData("protonVPN", "quickConnectType", root._quickConnectType || "fastest");
                                    let c = PluginService.loadPluginData("protonVPN", "quickConnectCountry", root._quickConnectCountry || "US");
                                    let cust = PluginService.loadPluginData("protonVPN", "quickConnectCustom", root._quickConnectCustom || "");
                                    if (t === "country_fastest") return "Quick Connect (" + (root.getCountryName(c) || c) + ")";
                                    if (t === "country_random") return "Quick Connect (Random Country)";
                                    if (t === "custom") return "Quick Connect (" + (cust || "Custom") + ")";
                                    return "Quick Connect (Fastest)";
                                }
                                Layout.fillWidth: true; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.primary 
                            }
                        }
                    }

                    Column {
                        id: countriesListCol; width: parent.width; spacing: 4

                        Repeater {
                            model: root.countriesList
                            delegate: Item {
                                id: countryDelegateCard
                                width: countriesListCol.width
                                property bool isExpanded: root.expandedCountryCode === modelData.code
                                height: 42 + (isExpanded ? (expContainer.height + 12) : 0)
                                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                                scale: maCountryHeader.pressed ? 0.98 : (maCountryHeader.containsMouse ? 1.005 : 1.0)
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                Shape {
                                    id: countryBg
                                    anchors.fill: parent

                                    property real innerRadius: 6
                                    property real outerRadius: 12
                                    property bool isFirstRow: index === 0
                                    property bool isLastRow: index === root.countriesList.length - 1
                                    
                                    property real tlr: (isExpanded || maCountryHeader.containsMouse) ? 21 : (isFirstRow ? outerRadius : innerRadius)
                                    property real trr: (isExpanded || maCountryHeader.containsMouse) ? 21 : (isFirstRow ? outerRadius : innerRadius)
                                    property real blr: (isExpanded || maCountryHeader.containsMouse) ? 21 : (isLastRow ? outerRadius : innerRadius)
                                    property real brr: (isExpanded || maCountryHeader.containsMouse) ? 21 : (isLastRow ? outerRadius : innerRadius)

                                    property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                    property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                    property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                    property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                                    property color paintColor: isExpanded 
                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) 
                                            : (maCountryHeader.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04))
                                    
                                    property color paintBorder: isExpanded 
                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.50) 
                                            : (maCountryHeader.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15))

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
                                    clip: true
                                    cornerRadius: countryBg.tlrAnim
                                    rippleColor: Theme.primary
                                }

                                Item {
                                    id: countryHeaderArea
                                    width: parent.width; height: 42
                                    anchors.top: parent.top

                                    MouseArea {
                                        id: maCountryHeader; anchors.fill: parent; hoverEnabled: true
                                        enabled: !root.isDisconnecting
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
                                            width: 16; height: 16
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            Layout.alignment: Qt.AlignVCenter
                                            Text {
                                                text: modelData.flag
                                                font.pixelSize: 20
                                                font.family: "Noto Color Emoji, Apple Color Emoji, Segoe UI Emoji, EmojiOne Color, Twemoji, sans-serif"
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        StyledText { text: modelData.name; Layout.fillWidth: true; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Normal; color: Theme.surfaceText; Layout.alignment: Qt.AlignVCenter }

                                        DankIcon {
                                            name: "expand_more"
                                            size: 16
                                            color: Theme.surfaceVariantText
                                            opacity: 0.7
                                            Layout.alignment: Qt.AlignVCenter
                                            rotation: isExpanded ? 180 : 0
                                            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                                        }
                                    }
                                }

                                Item {
                                    id: expContainer
                                    anchors.top: countryHeaderArea.bottom
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.leftMargin: 4; anchors.rightMargin: 4; anchors.bottomMargin: 6
                                    height: isExpanded ? Math.min(serverSubCol.implicitHeight + 8, 192) : 0
                                    clip: true
                                    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    opacity: isExpanded ? 1.0 : 0.0

                                    Flickable {
                                        id: serverFlickable
                                        anchors.fill: parent
                                        anchors.leftMargin: 2
                                        anchors.rightMargin: 10
                                        contentWidth: width
                                        contentHeight: serverSubCol.implicitHeight + 4
                                        boundsBehavior: Flickable.StopAtBounds
                                        clip: true

                                        Column {
                                            id: serverSubCol
                                            width: Math.max(0, parent.width - 2)
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            spacing: 4
                                            topPadding: 4
                                            bottomPadding: 6

                                            Item {
                                                id: fastestServerItem
                                                width: parent.width; height: 38
                                                opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                                                scale: maFastestServer.pressed ? 0.98 : 1.0
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
                                                    enabled: !root.isDisconnecting
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onPressed: mouse => fastestServerRipple.trigger(mouse.x, mouse.y)
                                                    onClicked: root.connectVpn(modelData.target)
                                                }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                                                    DankIcon { name: "bolt"; size: 16; color: Theme.primary; opacity: 0.85 }
                                                    StyledText { text: "Fastest " + modelData.name + " Server"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Normal; color: Theme.primary; Layout.fillWidth: true }
                                                    StyledText { text: "Connect"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Normal; color: Theme.primary }
                                                }
                                            }

                                            Repeater {
                                                model: modelData.servers
                                                delegate: Item {
                                                    id: serverItemRect
                                                    width: parent.width; height: 34
                                                    opacity: (root.isConnecting || root.isDisconnecting) ? 0.4 : 1.0
                                                    scale: maSrv.pressed ? 0.98 : 1.0
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
                                                        enabled: !root.isDisconnecting
                                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onPressed: mouse => srvRipple.trigger(mouse.x, mouse.y)
                                                        onClicked: root.connectVpn(modelData.target)
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                                                        DankIcon { name: "dns"; size: 16; color: Theme.surfaceText; opacity: 0.7; Layout.alignment: Qt.AlignVCenter }
                                                        StyledText { text: modelData.name; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText; Layout.fillWidth: true }
                                                        StyledText { text: modelData.load; font.pixelSize: Theme.fontSizeSmall; font.family: "Monospace"; color: Theme.primary }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: srvScrollBar
                                        anchors.right: parent.right
                                        anchors.rightMargin: 1
                                        anchors.top: parent.top
                                        anchors.topMargin: 4
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 4
                                        width: 3
                                        radius: 1.5
                                        color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.12)
                                        visible: serverFlickable.contentHeight > serverFlickable.height

                                        Rectangle {
                                            width: parent.width
                                            height: Math.max(16, (serverFlickable.visibleArea.heightRatio) * parent.height)
                                            y: serverFlickable.visibleArea.yPosition * parent.height
                                            radius: 1.5
                                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
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
