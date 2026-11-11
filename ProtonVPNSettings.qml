import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Modules.Settings.Widgets
import qs.Services

PluginSettings {
    id: root

    pluginId: "protonVPN"

    // --- Settings State on Root ---
    property string defaultProtocol: "smart"
    property string quickConnectType: "fastest" // "fastest", "country_fastest", "custom"
    property string quickConnectCountry: "US"
    property string quickConnectCustom: ""
    property bool paidServersOnly: false
    property bool showConnectContainer: true
    property bool showSpeedContainer: true

    property var countryOptions: [
        { name: "United States", code: "US" },
        { name: "Netherlands", code: "NL" },
        { name: "Japan", code: "JP" },
        { name: "Switzerland", code: "CH" },
        { name: "United Kingdom", code: "GB" },
        { name: "Germany", code: "DE" },
        { name: "Canada", code: "CA" },
        { name: "France", code: "FR" },
        { name: "Sweden", code: "SE" },
        { name: "Norway", code: "NO" },
        { name: "Spain", code: "ES" },
        { name: "Italy", code: "IT" },
        { name: "Australia", code: "AU" },
        { name: "Poland", code: "PL" }
    ]

    property var countryNameMap: ({
        "US": "United States", "NL": "Netherlands", "JP": "Japan", "CH": "Switzerland",
        "GB": "United Kingdom", "DE": "Germany", "CA": "Canada", "FR": "France",
        "SE": "Sweden", "NO": "Norway", "ES": "Spain", "IT": "Italy",
        "AU": "Australia", "IN": "India", "BR": "Brazil", "PL": "Poland",
        "FI": "Finland", "DK": "Denmark", "AT": "Austria", "BE": "Belgium",
        "IE": "Ireland", "NZ": "New Zealand", "SG": "Singapore", "KR": "South Korea",
        "MX": "Mexico", "RO": "Romania", "CZ": "Czechia", "HK": "Hong Kong",
        "TW": "Taiwan", "ZA": "South Africa", "IS": "Iceland", "PT": "Portugal",
        "GR": "Greece", "HU": "Hungary", "SK": "Slovakia", "BG": "Bulgaria",
        "UA": "Ukraine", "EE": "Estonia", "LV": "Latvia", "LT": "Lithuania",
        "HR": "Croatia", "SI": "Slovenia", "LU": "Luxembourg", "CY": "Cyprus",
        "MT": "Malta", "IL": "Israel", "TR": "Turkey", "CL": "Chile",
        "AR": "Argentina", "CO": "Colombia", "CR": "Costa Rica", "PE": "Peru",
        "VN": "Vietnam", "TH": "Thailand", "MY": "Malaysia", "PH": "Philippines",
        "ID": "Indonesia", "EG": "Egypt", "AE": "United Arab Emirates"
    })

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

    onPaidServersOnlyChanged: if (settingsServersScanner) settingsServersScanner.running = true

    Process {
        id: settingsServersScanner
        command: ["bash", "-c", "timeout 3 pvpnctl servers 2>/dev/null || echo ''"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = text.trim();
                if (!raw || raw.includes("Cannot connect to pvpnd")) return;
                
                let lines = raw.split('\n');
                let foundCountries = {};
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line || line.toUpperCase().startsWith("NAME") || line.startsWith("---")) continue;
                    let parts = line.split(/\s+/);
                    if (parts.length >= 2) {
                        let name = parts[0];
                        let isFree = name.toUpperCase().includes("FREE") || line.toUpperCase().includes("FREE");
                        if (root.paidServersOnly && isFree) continue;

                        let countryCode = name.substring(0, 2).toUpperCase();
                        if (countryCode.length === 2 && countryCode.match(/^[A-Z]{2}$/)) {
                            foundCountries[countryCode] = root.getCountryName(countryCode);
                        }
                    }
                }
                let newList = [];
                for (let code in foundCountries) {
                    newList.push({ name: foundCountries[code], code: code });
                }
                if (newList.length > 0) {
                    newList.sort((a, b) => a.name.localeCompare(b.name));
                    root.countryOptions = newList;
                }
            }
        }
    }

    readonly property real outerR: Theme.cornerRadius || 12
    readonly property real innerR: 4

    function loadValue(key, def) {
        if (typeof PluginService !== "undefined" && PluginService && PluginService.loadPluginData) {
            return PluginService.loadPluginData(root.pluginId, key, def);
        }
        return def;
    }

    function saveValue(key, val) {
        if (typeof PluginService !== "undefined" && PluginService && PluginService.savePluginData) {
            PluginService.savePluginData(root.pluginId, key, val);
            if (PluginService.setGlobalVar) {
                PluginService.setGlobalVar(root.pluginId, key, val);
            }
        }
    }

    function loadAll() {
        defaultProtocol = loadValue("defaultProtocol", "smart");
        quickConnectType = loadValue("quickConnectType", "fastest");
        if (quickConnectType === "country_random") quickConnectType = "country_fastest";
        quickConnectCountry = loadValue("quickConnectCountry", "US");
        quickConnectCustom = loadValue("quickConnectCustom", "");
        paidServersOnly = (loadValue("paidServersOnly", false) === true || loadValue("paidServersOnly", false) === "true");
        showConnectContainer = (loadValue("showConnectContainer", true) === true || loadValue("showConnectContainer", true) === "true");
        showSpeedContainer = (loadValue("showSpeedContainer", true) === true || loadValue("showSpeedContainer", true) === "true");
    }

    Component.onCompleted: loadAll()

    onPluginServiceChanged: {
        if (pluginService) {
            loadAll();
        }
    }

    Connections {
        target: PluginService
        ignoreUnknownSignals: true
        function onPluginDataChanged(pId) {
            if (pId === root.pluginId) {
                root.loadAll();
            }
        }
        function onGlobalVarChanged(pId, varName) {
            if (pId === root.pluginId) {
                root.loadAll();
            }
        }
    }

    Column {
        id: mainSettingsCol
        width: parent.width
        spacing: Theme.spacingL

        // --- General Settings Section ---
        Column {
            width: parent.width
            spacing: Theme.spacingS

            Row {
                spacing: Theme.spacingXS
                leftPadding: Theme.spacingM
                DankIcon {
                    name: "tune"
                    size: 16
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: "General Preferences"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Column {
                id: prefColumn
                width: parent.width
                spacing: 2

                // 1. Connection Protocol (First)
                Rectangle {
                    width: parent.width
                    height: protoCol.implicitHeight + Theme.spacingM * 2

                    topLeftRadius: root.outerR
                    topRightRadius: root.outerR
                    bottomLeftRadius: root.innerR
                    bottomRightRadius: root.innerR

                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                    ColumnLayout {
                        id: protoCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingS

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                Layout.alignment: Qt.AlignVCenter

                                DankIcon {
                                    name: "vpn_key"
                                    size: 18
                                    color: Theme.primary
                                    anchors.centerIn: parent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: "Connection Protocol"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Preferred backend protocol passed directly via --protocol flag on connect."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        DankDropdown {
                            id: protoDropdown
                            readonly property var protoMap: ({
                                "Smart": "smart",
                                "WireGuard": "wireguard",
                                "Stealth": "stealth"
                            })

                            Layout.fillWidth: true
                            compactMode: true
                            dropdownWidth: parent.width
                            options: ["Smart", "WireGuard", "Stealth"]
                            currentValue: {
                                const p = root.defaultProtocol;
                                for (const label in protoMap) {
                                    if (protoMap[label] === p) return label;
                                }
                                return "Smart";
                            }
                            onValueChanged: value => {
                                for (const label in protoMap) {
                                    if (label === value) {
                                        root.defaultProtocol = protoMap[label];
                                        root.saveValue("defaultProtocol", protoMap[label]);
                                        return;
                                    }
                                }
                            }
                        }
                    }
                }

                // 2. Quick Connect Action Target (Middle)
                Rectangle {
                    width: parent.width
                    height: targetCol.implicitHeight + Theme.spacingM * 2

                    topLeftRadius: root.innerR
                    topRightRadius: root.innerR
                    bottomLeftRadius: root.innerR
                    bottomRightRadius: root.innerR

                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                    ColumnLayout {
                        id: targetCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingS

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                Layout.alignment: Qt.AlignVCenter

                                DankIcon {
                                    name: "flash_on"
                                    size: 18
                                    color: Theme.primary
                                    anchors.centerIn: parent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: "Quick Connect Action"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Action executed when clicking the Quick Connect button or the Control Center tile action."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        DankDropdown {
                            id: targetTypeDropdown
                            readonly property var targetMap: ({
                                "Fastest Server": "fastest",
                                "Fastest Selected Country's Server": "country_fastest",
                                "Custom Server": "custom"
                            })

                            Layout.fillWidth: true
                            compactMode: true
                            dropdownWidth: parent.width
                            options: ["Fastest Server", "Fastest Selected Country's Server", "Custom Server"]
                            currentValue: {
                                const t = root.quickConnectType;
                                for (const label in targetMap) {
                                    if (targetMap[label] === t) return label;
                                }
                                return "Fastest Server";
                            }
                            onValueChanged: value => {
                                for (const label in targetMap) {
                                    if (label === value) {
                                        root.quickConnectType = targetMap[label];
                                        root.saveValue("quickConnectType", targetMap[label]);
                                        return;
                                    }
                                }
                            }
                        }

                        // Sub-Option 1: Country selection for "country_fastest"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingS
                            visible: root.quickConnectType === "country_fastest"

                            StyledText {
                                text: "Country:"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                Layout.alignment: Qt.AlignVCenter
                            }

                            DankDropdown {
                                id: countryDropdown
                                Layout.fillWidth: true
                                compactMode: true
                                dropdownWidth: parent.width
                                options: root.countryOptions.map(c => c.name + " (" + c.code + ")")
                                currentValue: {
                                    for (let i = 0; i < root.countryOptions.length; i++) {
                                        if (root.countryOptions[i].code === root.quickConnectCountry) {
                                            return root.countryOptions[i].name + " (" + root.countryOptions[i].code + ")";
                                        }
                                    }
                                    return root.countryOptions.length > 0 ? (root.countryOptions[0].name + " (" + root.countryOptions[0].code + ")") : "";
                                }
                                onValueChanged: value => {
                                    for (let i = 0; i < root.countryOptions.length; i++) {
                                        let label = root.countryOptions[i].name + " (" + root.countryOptions[i].code + ")";
                                        if (label === value) {
                                            let code = root.countryOptions[i].code;
                                            root.quickConnectCountry = code;
                                            root.saveValue("quickConnectCountry", code);
                                            return;
                                        }
                                    }
                                }
                            }
                        }

                        // Sub-Option 2: Custom Server text input for "custom"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingS
                            visible: root.quickConnectType === "custom"

                            DankTextField {
                                id: customServerField
                                Layout.fillWidth: true
                                text: root.quickConnectCustom
                                placeholderText: "e.g. US-NY#1 or NL-FREE#1"
                                onEditingFinished: {
                                    let val = customServerField.text.trim();
                                    root.quickConnectCustom = val;
                                    root.saveValue("quickConnectCustom", val);
                                }
                            }

                            Rectangle {
                                width: 80
                                height: 36
                                radius: Theme.cornerRadius
                                color: Theme.primary
                                
                                StyledText {
                                    text: "Save"
                                    anchors.centerIn: parent
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.surface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        let val = customServerField.text.trim();
                                        root.quickConnectCustom = val;
                                        root.saveValue("quickConnectCustom", val);
                                    }
                                }
                            }
                        }
                    }
                }

                // 3. Show Countries & Server List (Middle)
                Rectangle {
                    width: parent.width
                    height: connRow.implicitHeight + Theme.spacingM * 2

                    topLeftRadius: root.innerR
                    topRightRadius: root.innerR
                    bottomLeftRadius: root.innerR
                    bottomRightRadius: root.innerR

                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                    RowLayout {
                        id: connRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingM

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: showConnectSwitch.checked ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.5)
                            Layout.alignment: Qt.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 150 } }

                            DankIcon {
                                name: "dns"
                                size: 18
                                color: showConnectSwitch.checked ? Theme.primary : Theme.surfaceVariantText
                                anchors.centerIn: parent
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Show manual server list"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Show or hide the countries and servers list for manual selection."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }
                        }

                        DankToggle {
                            id: showConnectSwitch
                            hideText: true
                            checked: root.showConnectContainer
                            onToggled: function(newChecked) {
                                checked = newChecked;
                                root.showConnectContainer = newChecked;
                                root.saveValue("showConnectContainer", newChecked);
                            }
                        }
                    }
                }

                // 4. Show Speed Monitor (Middle)
                Rectangle {
                    width: parent.width
                    height: speedRow.implicitHeight + Theme.spacingM * 2

                    topLeftRadius: root.innerR
                    topRightRadius: root.innerR
                    bottomLeftRadius: root.innerR
                    bottomRightRadius: root.innerR

                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                    RowLayout {
                        id: speedRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingM

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: showSpeedSwitch.checked ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.5)
                            Layout.alignment: Qt.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 150 } }

                            DankIcon {
                                name: "speed"
                                size: 18
                                color: showSpeedSwitch.checked ? Theme.primary : Theme.surfaceVariantText
                                anchors.centerIn: parent
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Show speed monitor"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Show or hide the real-time upload and download speed container."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }
                        }

                        DankToggle {
                            id: showSpeedSwitch
                            hideText: true
                            checked: root.showSpeedContainer
                            onToggled: function(newChecked) {
                                checked = newChecked;
                                root.showSpeedContainer = newChecked;
                                root.saveValue("showSpeedContainer", newChecked);
                            }
                        }
                    }
                }

                // 5. Only Show Paid Servers (Last)
                Rectangle {
                    width: parent.width
                    height: paidRow.implicitHeight + Theme.spacingM * 2

                    topLeftRadius: root.innerR
                    topRightRadius: root.innerR
                    bottomLeftRadius: root.outerR
                    bottomRightRadius: root.outerR

                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                    RowLayout {
                        id: paidRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingM

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: paidServersSwitch.checked ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.5)
                            Layout.alignment: Qt.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 150 } }

                            DankIcon {
                                name: "monetization_on"
                                size: 18
                                color: paidServersSwitch.checked ? Theme.primary : Theme.surfaceVariantText
                                anchors.centerIn: parent
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Only show paid servers"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "For Paid users only. If enabled, free servers will be hidden from the server selection list."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.error
                                wrapMode: Text.WordWrap
                            }
                        }

                        DankToggle {
                            id: paidServersSwitch
                            hideText: true
                            checked: root.paidServersOnly
                            onToggled: function(newChecked) {
                                checked = newChecked;
                                root.paidServersOnly = newChecked;
                                root.saveValue("paidServersOnly", newChecked);
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // REQUIRED PACKAGES, ACCOUNT AUTH & BACKEND UPDATES
        // =====================================================================
        Item {
            id: depsWrapper
            width: parent.width
            implicitHeight: depsCol.implicitHeight

            property bool expanded: true
            property var depStatus: ({
                "pvpnctl": false,
                "pvpn": false,
                "pvpnd": false,
                "curl": true,
                "systemctl": true,
                "nft": true,
                "wg": true,
                "installed_version": "",
                "latest_version": "",
                "has_update": false,
                "logged_in": false,
                "username": "",
                "plan_name": "",
                "daemon_running": false
            })
            property bool isChecking: true
            property bool isLoggingIn: false
            property bool isLoggingOut: false
            property string authError: ""
            property string authSuccess: ""
            property string installStatusText: ""
            readonly property string installCmd: "curl -fsSL https://raw.githubusercontent.com/YourDoritos/pVPN/main/install.sh | sudo bash"

            function refresh() {
                isChecking = true;
                depChecker.running = false;
                depChecker.running = true;
            }

            Process {
                id: depChecker
                command: ["bash", "-c", "python3 /home/JD/Downloads/Projects/DMS-Proton_VPN/check_backend.py 2>/dev/null || echo '{}'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        depsWrapper.isChecking = false;
                        try {
                            if (text && text.trim() !== "") {
                                depsWrapper.depStatus = JSON.parse(text.trim());
                            }
                        } catch (e) {
                            console.warn("Failed to parse Proton VPN dependency status:", e);
                        }
                    }
                }
            }

            Process {
                id: loginProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        depsWrapper.isLoggingIn = false;
                        let out = (text || "").trim();
                        if (out.toLowerCase().includes("successfully") || out.toLowerCase().includes("logged in")) {
                            depsWrapper.authSuccess = "Logged in successfully!";
                            depsWrapper.authError = "";
                            usernameInput.text = "";
                            passwordInput.text = "";
                            twoFactorInput.text = "";
                            depsWrapper.refresh();
                        } else if (out.toLowerCase().includes("2fa")) {
                            depsWrapper.authError = "2FA Code Required. Please enter your 2FA code above and click Login.";
                            depsWrapper.authSuccess = "";
                        } else {
                            depsWrapper.authError = out || "Login failed. Please check credentials.";
                            depsWrapper.authSuccess = "";
                        }
                    }
                }
            }

            Process {
                id: logoutProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        depsWrapper.isLoggingOut = false;
                        depsWrapper.authSuccess = "Logged out successfully.";
                        depsWrapper.authError = "";
                        depsWrapper.refresh();
                    }
                }
            }

            property bool isInstalling: false

            Process {
                id: installProc
                command: ["pkexec", "/home/JD/Downloads/Projects/DMS-Proton_VPN/install_backend_headless.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        depsWrapper.isInstalling = false;
                        depsWrapper.installStatusText = "Installation finished.";
                        depsWrapper.refresh();
                    }
                }
            }

            Process {
                id: uninstallProc
                command: ["bash", "/home/JD/Downloads/Projects/DMS-Proton_VPN/launch_uninstaller.sh"]
            }

            function launchUninstallTerminal() {
                uninstallProc.running = false;
                uninstallProc.running = true;
            }

            function launchInstallTerminal() {
                depsWrapper.installStatusText = "Authenticating via Polkit & installing...";
                depsWrapper.isInstalling = true;
                installProc.running = false;
                installProc.running = true;
            }

            function performLogin() {
                let user = usernameInput.text.trim();
                let pass = passwordInput.text.trim();
                let twoFa = twoFactorInput.text.trim();
                if (!user || !pass) {
                    authError = "Please enter both username and password.";
                    return;
                }
                authError = "";
                authSuccess = "";
                isLoggingIn = true;
                let cmd = ["pvpnctl", "login", user, pass];
                if (twoFa) cmd.push(twoFa);
                loginProc.command = cmd;
                loginProc.running = false;
                loginProc.running = true;
            }

            function performLogout() {
                authError = "";
                authSuccess = "";
                isLoggingOut = true;
                logoutProc.command = ["python3", "/home/JD/Downloads/Projects/DMS-Proton_VPN/pvpn_logout.py"];
                logoutProc.running = false;
                logoutProc.running = true;
            }

            Component.onCompleted: {
                depChecker.running = true;
            }

            Column {
                id: depsCol
                width: parent.width
                spacing: Theme.spacingM

                // --- Section Header with Collapse Toggle ---
                Item {
                    id: depsHeaderRow
                    width: parent.width
                    height: 40

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "extension"
                            size: 16
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: I18n.tr("Required packages & Backend")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    DankIcon {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: "expand_more"
                        size: Theme.iconSize || 20
                        color: Theme.surfaceVariantText
                        rotation: depsWrapper.expanded ? 180 : 0

                        Behavior on rotation {
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            depsWrapper.expanded = !depsWrapper.expanded;
                            if (depsWrapper.expanded) {
                                depsWrapper.refresh();
                            }
                        }
                    }
                }

                // --- Animated Collapsible Body Container ---
                Item {
                    id: depsAnimHost
                    width: parent.width
                    clip: true
                    height: depsWrapper.expanded ? depsContentCol.implicitHeight : 0
                    opacity: depsWrapper.expanded ? 1.0 : 0.0
                    visible: height > 0 || depsWrapper.expanded

                    Behavior on height {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutQuad
                        }
                    }

                    Column {
                        id: depsContentCol
                        width: parent.width
                        spacing: Theme.spacingM

                    // 1. Backend Update Banner (if update available)
                    Rectangle {
                        width: parent.width
                        visible: depsWrapper.depStatus.has_update
                        implicitHeight: updateCol.implicitHeight + Theme.spacingM * 2
                        radius: root.outerR
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        border.width: 1
                        border.color: Theme.primary

                        ColumnLayout {
                            id: updateCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "system_update"
                                    size: 24
                                    color: Theme.primary
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "Update Available for pVPN Backend"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Installed: " + (depsWrapper.depStatus.installed_version || "unknown") + "  →  Latest: " + depsWrapper.depStatus.latest_version + ". Outdated backends may fail authentication or stop connecting due to Proton API updates."
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            // Segmented Action Row (First / Last covering full width with full-pill hover anim)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    height: 38
                                    readonly property bool isHov: updateBtnMa.containsMouse
                                    topLeftRadius: isHov ? height / 2 : root.outerR
                                    bottomLeftRadius: isHov ? height / 2 : root.outerR
                                    topRightRadius: isHov ? height / 2 : root.innerR
                                    bottomRightRadius: isHov ? height / 2 : root.innerR
                                    color: isHov ? Qt.darker(Theme.primary, 1.1) : Theme.primary

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on topLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on bottomLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on topRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on bottomRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DankIcon {
                                            name: "terminal"
                                            size: 16
                                            color: Theme.surfaceContainerHighest
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: depsWrapper.isInstalling ? "Installing..." : "Update Backend"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.surfaceContainerHighest
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: updateBtnMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: depsWrapper.launchInstallTerminal()
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    height: 38
                                    readonly property bool isHov: refreshBtnMa.containsMouse
                                    topLeftRadius: isHov ? height / 2 : root.innerR
                                    bottomLeftRadius: isHov ? height / 2 : root.innerR
                                    topRightRadius: isHov ? height / 2 : root.outerR
                                    bottomRightRadius: isHov ? height / 2 : root.outerR
                                    color: isHov ? Theme.withAlpha(Theme.primary, 0.25) : Theme.withAlpha(Theme.primary, 0.15)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, isHov ? 0.5 : 0.3)

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    Behavior on topLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on bottomLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on topRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on bottomRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DankIcon {
                                            name: "refresh"
                                            size: 16
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: depsWrapper.isChecking ? "Checking..." : "Refresh Status"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: refreshBtnMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !depsWrapper.isChecking
                                        onClicked: depsWrapper.refresh()
                                    }
                                }
                            }

                            StyledText {
                                text: depsWrapper.installStatusText
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                visible: depsWrapper.installStatusText !== ""
                            }

                            CopyBox {
                                Layout.fillWidth: true
                                label: "Or update manually via terminal:"
                                text: depsWrapper.installCmd
                            }
                        }
                    }

                    // 2. Missing Backend Alert (if pvpn is not installed)
                    Rectangle {
                        width: parent.width
                        visible: !depsWrapper.isChecking && !depsWrapper.depStatus.pvpn && !depsWrapper.depStatus.pvpnctl
                        implicitHeight: missingBackendCol.implicitHeight + Theme.spacingM * 2
                        radius: root.outerR
                        color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                        border.width: 1
                        border.color: Theme.error

                        ColumnLayout {
                            id: missingBackendCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "warning"
                                    size: 24
                                    color: Theme.error
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "pVPN Backend Not Installed"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        color: Theme.error
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "The pVPN backend (pvpn, pvpnctl, pvpnd) was not found on your system. You can install it using the button below or copy the one-line curl command."
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            // Segmented Action Row (First / Last covering full width with full-pill hover anim)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    height: 38
                                    readonly property bool isHov: installBtnMa.containsMouse
                                    topLeftRadius: isHov ? height / 2 : root.outerR
                                    bottomLeftRadius: isHov ? height / 2 : root.outerR
                                    topRightRadius: isHov ? height / 2 : root.innerR
                                    bottomRightRadius: isHov ? height / 2 : root.innerR
                                    color: isHov ? Qt.darker(Theme.primary, 1.1) : Theme.primary

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on topLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on bottomLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on topRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on bottomRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DankIcon {
                                            name: "download"
                                            size: 16
                                            color: Theme.surfaceContainerHighest
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: depsWrapper.isInstalling ? "Installing..." : "Install pVPN Backend"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.surfaceContainerHighest
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: installBtnMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: depsWrapper.launchInstallTerminal()
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    height: 38
                                    readonly property bool isHov: missingRefreshMa.containsMouse
                                    topLeftRadius: isHov ? height / 2 : root.innerR
                                    bottomLeftRadius: isHov ? height / 2 : root.innerR
                                    topRightRadius: isHov ? height / 2 : root.outerR
                                    bottomRightRadius: isHov ? height / 2 : root.outerR
                                    color: isHov ? Theme.withAlpha(Theme.primary, 0.25) : Theme.withAlpha(Theme.primary, 0.15)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, isHov ? 0.5 : 0.3)

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    Behavior on topLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on bottomLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on topRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on bottomRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DankIcon {
                                            name: "refresh"
                                            size: 16
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: depsWrapper.isChecking ? "Checking..." : "Refresh Status"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: missingRefreshMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !depsWrapper.isChecking
                                        onClicked: depsWrapper.refresh()
                                    }
                                }
                            }

                            StyledText {
                                text: depsWrapper.installStatusText
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                visible: depsWrapper.installStatusText !== ""
                            }

                            CopyBox {
                                Layout.fillWidth: true
                                label: "Install command:"
                                text: depsWrapper.installCmd
                            }
                        }
                    }

                    // 3. Proton Account Status & Login / Logout GUI
                    Rectangle {
                        width: parent.width
                        implicitHeight: accountCol.implicitHeight + Theme.spacingM * 2
                        radius: root.outerR
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                        ColumnLayout {
                            id: accountCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingM

                            // Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: depsWrapper.depStatus.logged_in ? "account_circle" : "no_accounts"
                                    size: 24
                                    color: depsWrapper.depStatus.logged_in ? Theme.success : Theme.surfaceVariantText
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: depsWrapper.depStatus.logged_in ? "Proton Account (Logged In)" : "Proton Account (Not Logged In)"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: depsWrapper.depStatus.logged_in
                                            ? ("Signed in as: " + (depsWrapper.depStatus.username || "Authenticated User") + (depsWrapper.depStatus.plan_name ? (" (" + depsWrapper.depStatus.plan_name + ")") : ""))
                                            : "You are not logged in. Sign in below or via 'pvpnctl login <user> <pass>' to access Proton VPN servers."
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                DankButton {
                                    visible: depsWrapper.depStatus.logged_in
                                    text: depsWrapper.isLoggingOut ? "Logging out..." : "Log Out"
                                    iconName: "logout"
                                    buttonHeight: 32
                                    backgroundColor: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                                    textColor: Theme.error
                                    enabled: !depsWrapper.isLoggingOut
                                    onClicked: depsWrapper.performLogout()
                                }
                            }

                            // Notification messages
                            StyledText {
                                visible: depsWrapper.authError !== ""
                                text: depsWrapper.authError
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.error
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            StyledText {
                                visible: depsWrapper.authSuccess !== ""
                                text: depsWrapper.authSuccess
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.success
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Login Form (visible when NOT logged in)
                            ColumnLayout {
                                visible: !depsWrapper.depStatus.logged_in
                                Layout.fillWidth: true
                                spacing: Theme.spacingS

                                DankTextField {
                                    id: usernameInput
                                    Layout.fillWidth: true
                                    labelText: "Proton Username or Email"
                                    placeholderText: "Username / Email"
                                    leftIconName: "person"
                                    cornerRadius: root.outerR
                                }

                                DankTextField {
                                    id: passwordInput
                                    Layout.fillWidth: true
                                    labelText: "Password"
                                    placeholderText: "Password"
                                    echoMode: TextInput.Password
                                    showPasswordToggle: true
                                    leftIconName: "lock"
                                    cornerRadius: root.outerR
                                }

                                DankTextField {
                                    id: twoFactorInput
                                    Layout.fillWidth: true
                                    labelText: "2FA Code (Optional)"
                                    placeholderText: "6-digit 2FA code (if enabled)"
                                    leftIconName: "security"
                                    cornerRadius: root.outerR
                                }

                                // Segmented Action Row (First / Last covering full width with full-pill hover anim)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        height: 38
                                        readonly property bool isHov: loginBtnMa.containsMouse
                                        topLeftRadius: isHov ? height / 2 : root.outerR
                                        bottomLeftRadius: isHov ? height / 2 : root.outerR
                                        topRightRadius: isHov ? height / 2 : root.innerR
                                        bottomRightRadius: isHov ? height / 2 : root.innerR
                                        color: isHov ? Qt.darker(Theme.primary, 1.1) : Theme.primary
                                        opacity: depsWrapper.isLoggingIn ? 0.7 : 1.0

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on topLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on bottomLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on topRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on bottomRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: Theme.spacingXS

                                            DankIcon {
                                                name: depsWrapper.isLoggingIn ? "hourglass_top" : "login"
                                                size: 16
                                                color: Theme.surfaceContainerHighest
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                text: depsWrapper.isLoggingIn ? "Signing In..." : "Log In"
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Medium
                                                color: Theme.surfaceContainerHighest
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: loginBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            enabled: !depsWrapper.isLoggingIn
                                            onClicked: depsWrapper.performLogin()
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        height: 38
                                        readonly property bool isHov: loginRefreshBtnMa.containsMouse
                                        topLeftRadius: isHov ? height / 2 : root.innerR
                                        bottomLeftRadius: isHov ? height / 2 : root.innerR
                                        topRightRadius: isHov ? height / 2 : root.outerR
                                        bottomRightRadius: isHov ? height / 2 : root.outerR
                                        color: isHov ? Theme.withAlpha(Theme.primary, 0.25) : Theme.withAlpha(Theme.primary, 0.15)
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, isHov ? 0.5 : 0.3)

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                        Behavior on topLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on bottomLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on topRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on bottomRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: Theme.spacingXS

                                            DankIcon {
                                                name: "refresh"
                                                size: 16
                                                color: Theme.primary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                text: depsWrapper.isChecking ? "Checking..." : "Refresh Status"
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Medium
                                                color: Theme.primary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: loginRefreshBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: !depsWrapper.isChecking
                                            onClicked: depsWrapper.refresh()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 4. Required Packages Status List (Matching ScreenCapture_Toolbar style)
                    SettingsGroup {
                        width: parent.width

                        SettingsRow {
                            visible: depsWrapper.isChecking
                            iconName: "hourglass_top"
                            title: I18n.tr("Checking packages & backend...")
                        }

                        Repeater {
                            model: [
                                {
                                    id: "pvpnctl",
                                    pkg: "pvpnctl (pVPN CLI Client)",
                                    features: "Command-line interface to connect, disconnect, and query status",
                                    present: Boolean(depsWrapper.depStatus.pvpnctl)
                                },
                                {
                                    id: "pvpnd",
                                    pkg: "pvpnd (pVPN Daemon)",
                                    features: "Background system service managing WireGuard tunnel and routes",
                                    present: Boolean(depsWrapper.depStatus.pvpnd)
                                },
                                {
                                    id: "pvpn",
                                    pkg: "pvpn (pVPN TUI)",
                                    features: "Interactive terminal user interface for Proton VPN",
                                    present: Boolean(depsWrapper.depStatus.pvpn)
                                },
                                {
                                    id: "curl",
                                    pkg: "curl",
                                    features: "Fetching releases, server configs, and running installer scripts",
                                    present: Boolean(depsWrapper.depStatus.curl)
                                },
                                {
                                    id: "systemctl",
                                    pkg: "systemd (systemctl)",
                                    features: "Managing the pvpnd background daemon service",
                                    present: Boolean(depsWrapper.depStatus.systemctl)
                                },
                                {
                                    id: "nft",
                                    pkg: "nftables (nft)",
                                    features: "Traffic kill switch & leak prevention rules",
                                    present: Boolean(depsWrapper.depStatus.nft)
                                },
                                {
                                    id: "wg",
                                    pkg: "wireguard (wg / wg-quick)",
                                    features: "Kernel WireGuard interface for high-speed VPN connections",
                                    present: Boolean(depsWrapper.depStatus.wg)
                                }
                            ]

                            delegate: SettingsRow {
                                iconName: modelData.present ? "check_circle" : "error"
                                iconColor: modelData.present ? Theme.success : Theme.error
                                title: modelData.pkg
                                subtitle: I18n.tr("Used for: %1").arg(modelData.features)
                                trailingBadge: modelData.present ? I18n.tr("Installed") : I18n.tr("Missing")
                                trailingBadgeColor: modelData.present ? Theme.surfaceVariantText : Theme.error
                            }
                        }
                    }

                    // 5. Backend Version & Release Category (Matching Required Packages SettingsGroup)
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        // Category Section Header with Expanding Uninstall Button on right
                        Item {
                            width: parent.width
                            height: 36

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: "memory"
                                    size: 16
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: I18n.tr("Backend Releases & Version")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Expanding Uninstall Button: rounded square that expands to pill with text on hover
                            Rectangle {
                                id: uninstallBtn
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Boolean(depsWrapper.depStatus.pvpn || depsWrapper.depStatus.pvpnctl)
                                readonly property bool isHov: uninstallMa.containsMouse
                                width: isHov ? 108 : 32
                                height: 32
                                radius: isHov ? height / 2 : root.outerR
                                color: isHov ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.22) : Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, isHov ? 0.6 : 0.25)
                                clip: true

                                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on radius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    DankIcon {
                                        name: "delete"
                                        size: 16
                                        color: Theme.error
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: "Uninstall"
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        font.weight: Font.Medium
                                        color: Theme.error
                                        visible: uninstallBtn.isHov
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: uninstallMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: depsWrapper.launchUninstallTerminal()
                                }
                            }
                        }

                        // Version Rows Grouped Similar to Required Packages
                        SettingsGroup {
                            width: parent.width

                            SettingsRow {
                                iconName: depsWrapper.depStatus.installed_version ? "verified" : "help_outline"
                                iconColor: depsWrapper.depStatus.installed_version ? Theme.primary : Theme.error
                                title: I18n.tr("Installed Backend Version")
                                subtitle: depsWrapper.depStatus.installed_version ? I18n.tr("Currently active local pVPN binary version") : I18n.tr("Backend binaries (pvpn, pvpnctl, pvpnd) not installed")
                                trailingBadge: depsWrapper.depStatus.installed_version || I18n.tr("Not installed")
                                trailingBadgeColor: depsWrapper.depStatus.installed_version ? Theme.surfaceVariantText : Theme.error
                            }

                            SettingsRow {
                                iconName: "cloud_sync"
                                iconColor: depsWrapper.depStatus.has_update ? Theme.primary : Theme.success
                                title: I18n.tr("Latest Release Version")
                                subtitle: depsWrapper.depStatus.has_update ? I18n.tr("New release available on GitHub (YourDoritos/pVPN)") : I18n.tr("Up to date with latest published GitHub release")
                                trailingBadge: depsWrapper.depStatus.latest_version || I18n.tr("Checking...")
                                trailingBadgeColor: depsWrapper.depStatus.has_update ? Theme.primary : Theme.success
                            }
                        }
                    }
                    } // end depsContentCol
                } // end depsAnimHost
            }
        }
    }
}
