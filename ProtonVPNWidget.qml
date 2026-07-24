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
    ccWidgetSecondaryText: root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : (root.isConnecting ? "Connecting..." : "Disconnected")
    ccWidgetIsActive: root.vpnStatus === "Connected"
    ccDetailHeight: 540
    onCcWidgetExpanded: root.refresh()
    
    ccDetailContent: Component {
        ScrollView {
            anchors.fill: parent
            clip: false
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            
            Loader {
                width: Math.max(0, parent.width)
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
    property string connectedCountryName: ""
    property string connectedIp: ""
    property string connectedProtocol: ""
    property string connectionTypeLabel: "Disconnected"
    
    property bool isConnecting: false
    property bool loading: statusScanner.running || connectProc.running || disconnectProc.running
    property string expandedCountryCode: "" // Currently expanded country code

    // Supported Countries Map for standard country name mapping
    property var countryNameMap: ({
        "US": "United States",
        "NL": "Netherlands",
        "JP": "Japan",
        "CH": "Switzerland",
        "GB": "United Kingdom",
        "DE": "Germany",
        "CA": "Canada",
        "FR": "France",
        "SE": "Sweden",
        "NO": "Norway",
        "ES": "Spain",
        "IT": "Italy",
        "AU": "Australia"
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

    // --- Country Flag Helper ---
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
        return c;
    }

    // --- Scanners & Process Execution ---
    Process {
        id: statusScanner
        command: ["bash", "-c", "pvpnctl status --format waybar"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let raw = text.trim();
                    if (!raw) return;
                    let data = JSON.parse(raw);
                    if (data.class === "connected" || (data.text && data.text.includes("Connected"))) {
                        root.vpnStatus = "Connected";
                        root.isConnecting = false;
                        
                        // Parse full server name (e.g. CA-Free#32) from tooltip or text
                        let fullServerName = "";
                        if (data.tooltip) {
                            let lines = data.tooltip.split('\n');
                            for (let i = 0; i < lines.length; i++) {
                                let l = lines[i];
                                let low = l.toLowerCase();
                                if (low.includes("server:")) fullServerName = l.split(':')[1].trim();
                                if (low.includes("ip:")) root.connectedIp = l.split(':')[1].trim();
                                if (low.includes("protocol:")) root.connectedProtocol = l.split(':')[1].trim();
                                if (low.includes("country:")) {
                                    root.connectedCountry = l.split(':')[1].trim();
                                    root.connectedCountryName = root.getCountryName(root.connectedCountry);
                                }
                            }
                        }

                        if (!fullServerName && data.text) {
                            fullServerName = data.text.replace("🔒", "").trim();
                        }
                        root.connectedServer = fullServerName || "Connected";

                        if (root.connectedServer.toLowerCase().includes("fastest") || root.connectedServer.toLowerCase() === "fastest") {
                            root.connectionTypeLabel = "Connected via Status (Fastest Server)";
                        } else if (root.connectedServer) {
                            root.connectionTypeLabel = "Connected via Manual Connection (" + root.connectedServer + ")";
                        } else {
                            root.connectionTypeLabel = "Connected via Status";
                        }
                    } else if (data.class === "connecting") {
                        root.vpnStatus = "Connecting...";
                        root.isConnecting = true;
                        root.connectionTypeLabel = "Connecting to VPN...";
                    } else {
                        if (!root.isConnecting) {
                            root.vpnStatus = "Disconnected";
                            root.connectedServer = "";
                            root.connectedIp = "";
                            root.connectedCountry = "";
                            root.connectedCountryName = "";
                            root.connectionTypeLabel = "Disconnected";
                        }
                    }
                } catch(e) {
                    if (text.includes("Cannot connect to pvpnd")) {
                        root.vpnStatus = "Daemon Stopped";
                        root.isConnecting = false;
                        root.connectionTypeLabel = "pvpnd Daemon Stopped";
                    } else {
                        if (!root.isConnecting) {
                            root.vpnStatus = "Disconnected";
                            root.connectionTypeLabel = "Disconnected";
                        }
                    }
                }
            }
        }
    }

    // Real-Time Server & Load Fetcher
    Process {
        id: serversScanner
        command: ["bash", "-c", "pvpnctl servers"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = text.trim();
                if (!raw) return;
                let lines = raw.split('\n');
                let parsedByCountry = {};
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line || line.startsWith("Name") || line.startsWith("---")) continue;
                    let parts = line.split(/\s+/);
                    if (parts.length >= 2) {
                        let name = parts[0];
                        let load = parts[parts.length - 1];
                        if (!load.endsWith("%")) load = load + "%";
                        let countryCode = name.substring(0, 2).toUpperCase();
                        if (!parsedByCountry[countryCode]) parsedByCountry[countryCode] = [];
                        parsedByCountry[countryCode].push({ name: name, target: name, load: load });
                    }
                }
                
                let updated = Array.from(root.countriesList);
                for (let j = 0; j < updated.length; j++) {
                    let code = updated[j].code;
                    if (parsedByCountry[code] && parsedByCountry[code].length > 0) {
                        updated[j].servers = parsedByCountry[code];
                    }
                }
                root.countriesList = updated;
            }
        }
    }

    Process {
        id: connectProc
        running: false
        stdout: StdioCollector { onStreamFinished: { statusTimer.restart(); } }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) console.log("pVPN Connect Error: " + text.trim()); statusTimer.restart(); } }
    }

    Process {
        id: disconnectProc
        running: false
        stdout: StdioCollector { onStreamFinished: { statusTimer.restart(); } }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) console.log("pVPN Disconnect Error: " + text.trim()); statusTimer.restart(); } }
    }

    function refresh() {
        statusScanner.running = false;
        statusScanner.running = true;
    }

    function fetchServers() {
        serversScanner.running = false;
        serversScanner.running = true;
    }

    // High frequency status polling timer (1s when connecting, 2.5s otherwise)
    Timer {
        id: statusTimer
        interval: root.isConnecting ? 1000 : 2500
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
        root.vpnStatus = "Connecting...";
        root.connectionTypeLabel = "Connecting to " + (target || "VPN") + "...";
        let tgt = target || root._defaultConnectTarget || "fastest";
        let proto = root._defaultProtocol || "smart";
        let cmd = "pvpnctl connect \"" + tgt + "\" --protocol " + proto;
        connectProc.command = ["bash", "-c", cmd];
        connectProc.running = true;
        statusTimer.restart();
    }

    function disconnectVpn() {
        root.isConnecting = false;
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
                    sourceComponent: (root.loading || root.isConnecting) ? refreshingIconComp : standardPillIconH
                    
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
                    text: root.isConnecting ? "Connecting..." : (root.vpnStatus === "Connected" ? (root.connectedServer || "Connected") : "Disconnected")
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
                sourceComponent: (root.loading || root.isConnecting) ? refreshingIconComp : standardPillIconV
                
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

    // --- Content Component ---
    Component {
        id: vpnWidgetContent
        Column {
            id: mainCol; width: parent.width; spacing: Theme.spacingM
            property bool inCC: false

            padding: inCC ? 16 : 0
            topPadding: 0
            bottomPadding: inCC ? 16 : 2

            // 1. Header Card: Proton VPN Title + Connection Status + Flat Square Connect Button
            StyledRect {
                width: Math.max(0, parent.width - (mainCol.inCC ? 32 : 0)); anchors.horizontalCenter: parent.horizontalCenter; height: 84
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1
                border.color: root.vpnStatus === "Connected" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                RowLayout {
                    anchors.fill: parent; anchors.margins: Theme.spacingM; spacing: Theme.spacingM
                    
                    // Header Left Icon: Proton VPN key icon & Country Flag if connected
                    Rectangle {
                        width: 48; height: 48; radius: 10
                        color: root.vpnStatus === "Connected" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.6)
                        border.color: root.vpnStatus === "Connected" ? Theme.primary : Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.15)
                        border.width: 1

                        Item {
                            anchors.fill: parent
                            DankIcon {
                                name: "vpn_key"
                                size: 24
                                color: root.vpnStatus === "Connected" ? Theme.primary : Theme.surfaceText
                                anchors.centerIn: parent
                            }
                            StyledText {
                                text: root.vpnStatus === "Connected" && root.connectedCountry ? root.getCountryFlag(root.connectedCountry) : ""
                                font.pixelSize: 16
                                anchors.bottom: parent.bottom; anchors.right: parent.right
                                anchors.margins: 2
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
                        
                        // Dynamic Banner / Status Indicator
                        RowLayout {
                            spacing: 4
                            visible: root.isConnecting
                            DankIcon {
                                name: "cached"
                                size: 12
                                color: Theme.primary
                                RotationAnimation on rotation { from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                            }
                            StyledText {
                                text: "Connecting..."
                                font.pixelSize: Theme.fontSizeSmall - 1
                                font.weight: Font.Bold
                                color: Theme.primary
                            }
                        }

                        StyledText { 
                            text: root.connectionTypeLabel
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: root.vpnStatus === "Connected" ? Theme.primary : Theme.surfaceVariantText
                            elide: Text.ElideRight
                            visible: !root.isConnecting
                        }
                    }

                    // Squarical Button with "Connect" / "Disconnect" Text
                    Rectangle {
                        width: 106; height: 42; radius: 8
                        color: root.vpnStatus === "Connected" ? Theme.error : Theme.primary
                        opacity: root.isConnecting ? 0.8 : 1.0
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.centerIn: parent; spacing: 6
                            DankIcon {
                                id: connBtnIcon
                                name: (root.loading || root.isConnecting) ? "cached" : (root.vpnStatus === "Connected" ? "power_settings_new" : "link")
                                size: 18
                                color: Theme.surface
                                RotationAnimation on rotation {
                                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: root.loading || root.isConnecting
                                }
                            }
                            StyledText {
                                text: root.isConnecting ? "Connecting" : (root.vpnStatus === "Connected" ? "Disconnect" : "Connect")
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                                color: Theme.surface
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
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

            // 2. Connection Details Container (Full Server Name & Full Country Name)
            StyledRect {
                id: connDetailsSection
                width: Math.max(0, parent.width - (mainCol.inCC ? 32 : 0))
                anchors.horizontalCenter: parent.horizontalCenter
                height: connDetailsCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius; color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                Column {
                    id: connDetailsCol
                    anchors.fill: parent; anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    // Section Title Header
                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingXS
                        DankIcon { name: "info"; size: 16; color: Theme.primary }
                        StyledText { text: "Connection Details"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText; Layout.fillWidth: true }
                    }

                    // Vertical List Item 1: Full Server Name (e.g. CA-Free#32)
                    Rectangle {
                        width: parent.width; height: 38; radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15); border.width: 1

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                            DankIcon { name: "dns"; size: 16; color: Theme.primary }
                            StyledText { text: "Server"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText; Layout.fillWidth: true }
                            StyledText { 
                                text: root.vpnStatus === "Connected" ? (root.connectedServer || "Default") : "Not Connected"
                                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Vertical List Item 2: Region / Country Name (Full Name e.g. Canada & Country Flag Badge)
                    Rectangle {
                        width: parent.width; height: 38; radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15); border.width: 1

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                            
                            // Flag / Public Icon aligned at 16px
                            Item {
                                width: 16; height: 16
                                Layout.alignment: Qt.AlignVCenter
                                DankIcon {
                                    name: "public"
                                    size: 16
                                    color: Theme.primary
                                    anchors.centerIn: parent
                                    visible: !(root.vpnStatus === "Connected" && root.connectedCountry)
                                }
                                StyledText {
                                    text: root.vpnStatus === "Connected" && root.connectedCountry ? root.getCountryFlag(root.connectedCountry) : ""
                                    font.pixelSize: 16
                                    anchors.centerIn: parent
                                    visible: text !== ""
                                }
                            }

                            StyledText { text: "Region"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText; Layout.fillWidth: true }
                            StyledText { 
                                text: root.vpnStatus === "Connected" ? (root.connectedCountryName || root.getCountryName(root.connectedCountry) || "Global") : "Not Connected"
                                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Vertical List Item 3: Connection Protocol
                    Rectangle {
                        width: parent.width; height: 38; radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15); border.width: 1

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

            // 3. Connect (Main Quick Connect Action Bar + Countries List with Real-time Loads & Smooth Expand Animation)
            StyledRect {
                id: connectSection
                width: Math.max(0, parent.width - (mainCol.inCC ? 32 : 0))
                anchors.horizontalCenter: parent.horizontalCenter
                height: connectSectionCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius; color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Column {
                    id: connectSectionCol
                    anchors.fill: parent; anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingXS
                        DankIcon { name: "public"; size: 16; color: Theme.primary }
                        StyledText { text: "Connect"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText; Layout.fillWidth: true }
                    }

                    // Main Quick Connect Bar (Direct Action)
                    Rectangle {
                        width: parent.width; height: 44; radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                        border.color: Theme.primary; border.width: 1

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.connectVpn("fastest")
                        }

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: Theme.spacingS
                            DankIcon { name: "bolt"; size: 18; color: Theme.primary; Layout.alignment: Qt.AlignVCenter }
                            StyledText { text: "Quick Connect (Fastest Server)"; Layout.fillWidth: true; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.primary }
                            StyledText { text: "12% Load"; font.pixelSize: Theme.fontSizeSmall - 2; font.family: "Monospace"; color: Theme.primary }
                        }
                    }

                    // Available Countries List with Expand/Collapse Animation
                    Column {
                        id: countriesListCol; width: parent.width; spacing: 6

                        Repeater {
                            model: root.countriesList
                            delegate: Column {
                                width: countriesListCol.width; spacing: 4
                                property bool isExpanded: root.expandedCountryCode === modelData.code

                                Rectangle {
                                    width: parent.width; height: 42; radius: 8
                                    color: isExpanded ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (maCountry.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Theme.surfaceContainer)
                                    border.color: isExpanded ? Theme.primary : (maCountry.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Theme.outline)
                                    border.width: 1

                                    MouseArea {
                                        id: maCountry; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
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
                                        
                                        // Perfectly Aligned 16px Country Flag Badge
                                        Item {
                                            width: 20; height: 20
                                            Layout.alignment: Qt.AlignVCenter
                                            StyledText {
                                                text: modelData.flag
                                                font.pixelSize: 16
                                                anchors.centerIn: parent
                                            }
                                        }

                                        StyledText { text: modelData.name; Layout.fillWidth: true; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText; Layout.alignment: Qt.AlignVCenter }
                                        
                                        // Expand Icon with Smooth Rotation Animation
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

                                // Animated Server Selection Container Below Country
                                Item {
                                    width: parent.width
                                    height: isExpanded ? serverSubCol.implicitHeight : 0
                                    clip: true
                                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    opacity: isExpanded ? 1.0 : 0.0

                                    Column {
                                        id: serverSubCol
                                        width: parent.width
                                        spacing: 4
                                        padding: 4

                                        // Fastest Connect Option for this country
                                        Rectangle {
                                            width: parent.width; height: 38; radius: 6
                                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                            border.color: Theme.primary; border.width: 1

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.connectVpn(modelData.target)
                                            }

                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                                                DankIcon { name: "bolt"; size: 16; color: Theme.primary }
                                                StyledText { text: "Fastest " + modelData.name + " Server"; font.pixelSize: Theme.fontSizeSmall - 1; font.weight: Font.Bold; color: Theme.primary; Layout.fillWidth: true }
                                                StyledText { text: "Connect"; font.pixelSize: Theme.fontSizeSmall - 2; font.weight: Font.Bold; color: Theme.primary }
                                            }
                                        }

                                        // Detailed Servers List with Loads
                                        Repeater {
                                            model: modelData.servers
                                            delegate: Rectangle {
                                                width: parent.width; height: 34; radius: 6
                                                color: maSrv.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Theme.surfaceContainerHigh
                                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15); border.width: 1

                                                MouseArea {
                                                    id: maSrv; anchors.fill: parent; hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
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

    // --- Popout Content ---
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
            }
        }
    }
}
