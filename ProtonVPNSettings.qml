import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
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

    function loadValue(key, def) {
        return PluginService.loadPluginData(root.pluginId, key, def);
    }

    function saveValue(key, val) {
        PluginService.savePluginData(root.pluginId, key, val);
        PluginService.setGlobalVar(root.pluginId, key, val);
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

    Column {
        id: mainSettingsCol
        width: parent.width
        spacing: Theme.spacingL

        // ── About & Plugin Info Card ───────────────────────────
        StyledRect {
            width: parent.width
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.65)
            border.width: 1
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
            implicitHeight: aboutCol.implicitHeight + Theme.spacingM * 2

            ColumnLayout {
                id: aboutCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM

                    Rectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.primary, 0.10)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            source: Qt.resolvedUrl("assets/icons/Proton-VPN.svg")
                            sourceSize.width: 80
                            sourceSize.height: 80
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Proton VPN"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: "Secure, high-speed Swiss VPN client powered by pvpn-cli"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Configure connection protocols, default quick-connect actions, and interface visibility toggles for the DankBar widget and Control Center module."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── Settings Cards Stack ───────────────────────────────
        Column {
            id: prefColumn
            width: parent.width
            spacing: 2

            // 1. Connection Protocol (First)
            Rectangle {
                width: parent.width
                height: protoCol.implicitHeight + Theme.spacingM * 2
                readonly property bool isFirst: true
                readonly property bool isLast: false
                readonly property real outerR: Theme.cornerRadius
                readonly property real innerR: 4

                topLeftRadius: isFirst ? outerR : innerR
                topRightRadius: isFirst ? outerR : innerR
                bottomLeftRadius: isLast ? outerR : innerR
                bottomRightRadius: isLast ? outerR : innerR

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

                        DankIcon {
                            name: "vpn_key"
                            size: 20
                            color: Theme.primary
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
                readonly property bool isFirst: false
                readonly property bool isLast: false
                readonly property real outerR: Theme.cornerRadius
                readonly property real innerR: 4

                topLeftRadius: isFirst ? outerR : innerR
                topRightRadius: isFirst ? outerR : innerR
                bottomLeftRadius: isLast ? outerR : innerR
                bottomRightRadius: isLast ? outerR : innerR

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

                        DankIcon {
                            name: "flash_on"
                            size: 20
                            color: Theme.primary
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

                        ComboBox {
                            id: countryCombo
                            Layout.fillWidth: true
                            model: root.countryOptions.map(c => c.name + " (" + c.code + ")")
                            
                            currentIndex: {
                                for (let i = 0; i < root.countryOptions.length; i++) {
                                    if (root.countryOptions[i].code === root.quickConnectCountry) return i;
                                }
                                return 0;
                            }

                            onActivated: function(index) {
                                let code = root.countryOptions[index].code;
                                root.quickConnectCountry = code;
                                root.saveValue("quickConnectCountry", code);
                            }

                            contentItem: StyledText {
                                leftPadding: Theme.spacingS
                                rightPadding: countryCombo.indicator ? countryCombo.indicator.width + countryCombo.spacing : Theme.spacingM
                                text: countryCombo.displayText
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                implicitWidth: 120
                                implicitHeight: 40
                                border.color: countryCombo.pressed ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                                border.width: countryCombo.visualFocus ? 2 : 1
                                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                radius: Theme.cornerRadius
                            }

                            popup: Popup {
                                id: countryPopup
                                y: countryCombo.height + 4
                                width: countryCombo.width
                                implicitHeight: Math.min(260, popupCol.implicitHeight + 16)
                                padding: 6

                                onOpened: {
                                    countrySearchInput.forceActiveFocus();
                                }

                                onClosed: {
                                    countrySearchInput.text = "";
                                }

                                contentItem: ColumnLayout {
                                    id: popupCol
                                    spacing: Theme.spacingS

                                    DankTextField {
                                        id: countrySearchInput
                                        Layout.fillWidth: true
                                        placeholderText: "Search country..."
                                        focus: true
                                    }

                                    ListView {
                                        id: countryListView
                                        Layout.fillWidth: true
                                        implicitHeight: Math.min(180, contentHeight)
                                        clip: true

                                        model: {
                                            let q = countrySearchInput.text.trim().toLowerCase();
                                            let list = root.countryOptions;
                                            if (q) {
                                                list = list.filter(c => c.name.toLowerCase().includes(q) || c.code.toLowerCase().includes(q));
                                            }
                                            return list;
                                        }

                                        delegate: ItemDelegate {
                                            width: countryListView.width
                                            contentItem: StyledText {
                                                text: modelData.name + " (" + modelData.code + ")"
                                                color: highlighted ? Theme.primary : Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeMedium
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                color: highlighted ? Theme.withAlpha(Theme.primary, 0.1) : "transparent"
                                                radius: 4
                                            }
                                            onClicked: {
                                                let code = modelData.code;
                                                root.quickConnectCountry = code;
                                                root.saveValue("quickConnectCountry", code);
                                                countryPopup.close();
                                            }
                                        }

                                        ScrollIndicator.vertical: ScrollIndicator { }
                                    }
                                }

                                background: Rectangle {
                                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                                    border.width: 1
                                    radius: Theme.cornerRadius
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
                readonly property bool isFirst: false
                readonly property bool isLast: false
                readonly property real outerR: Theme.cornerRadius
                readonly property real innerR: 4

                topLeftRadius: isFirst ? outerR : innerR
                topRightRadius: isFirst ? outerR : innerR
                bottomLeftRadius: isLast ? outerR : innerR
                bottomRightRadius: isLast ? outerR : innerR

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

                    DankIcon {
                        name: "dns"
                        size: 20
                        color: Theme.primary
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
                readonly property bool isFirst: false
                readonly property bool isLast: false
                readonly property real outerR: Theme.cornerRadius
                readonly property real innerR: 4

                topLeftRadius: isFirst ? outerR : innerR
                topRightRadius: isFirst ? outerR : innerR
                bottomLeftRadius: isLast ? outerR : innerR
                bottomRightRadius: isLast ? outerR : innerR

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

                    DankIcon {
                        name: "speed"
                        size: 20
                        color: Theme.primary
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
                readonly property bool isFirst: false
                readonly property bool isLast: true
                readonly property real outerR: Theme.cornerRadius
                readonly property real innerR: 4

                topLeftRadius: isFirst ? outerR : innerR
                topRightRadius: isFirst ? outerR : innerR
                bottomLeftRadius: isLast ? outerR : innerR
                bottomRightRadius: isLast ? outerR : innerR

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

                    DankIcon {
                        name: "monetization_on"
                        size: 20
                        color: Theme.primary
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
}
