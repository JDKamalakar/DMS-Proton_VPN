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

        // --- Connection Protocol Section ---
        Rectangle {
            width: parent.width
            height: generalCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            Column {
                id: generalCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM
                    
                    DankIcon { 
                        name: "vpn_key"
                        size: 22
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                    
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXS
                        StyledText { text: "Connection Protocol"; font.weight: Font.Medium; color: Theme.surfaceText }
                        StyledText { text: "Select preferred backend protocol. This is passed directly via --protocol flag on connect."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    ComboBox {
                        id: protocolCombo
                        Layout.fillWidth: true
                        model: ["Smart", "WireGuard", "Stealth"]
                        readonly property var protocolKeys: ["smart", "wireguard", "stealth"]
                        currentIndex: Math.max(0, protocolKeys.indexOf(root.defaultProtocol))
                        
                        onActivated: function(index) {
                            let val = protocolKeys[index];
                            root.defaultProtocol = val;
                            root.saveValue("defaultProtocol", val);
                        }

                        delegate: ItemDelegate {
                            width: protocolCombo.width
                            contentItem: StyledText {
                                text: modelData
                                color: highlighted ? Theme.primary : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: highlighted ? Theme.withAlpha(Theme.primary, 0.1) : "transparent"
                            }
                        }

                        contentItem: StyledText {
                            leftPadding: Theme.spacingS
                            rightPadding: protocolCombo.indicator ? protocolCombo.indicator.width + protocolCombo.spacing : Theme.spacingM
                            text: protocolCombo.displayText
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            border.color: protocolCombo.pressed ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)
                            border.width: protocolCombo.visualFocus ? 2 : 1
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                            radius: Theme.cornerRadius
                        }

                        popup: Popup {
                            y: protocolCombo.height + 2
                            width: protocolCombo.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 1

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: protocolCombo.popup.visible ? protocolCombo.delegateModel : null
                                currentIndex: protocolCombo.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }

                            background: Rectangle {
                                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                border.color: Theme.withAlpha(Theme.outline, 0.5)
                                border.width: 1
                                radius: Theme.cornerRadius
                            }
                        }
                    }
                }
            }
        }

        // --- Quick Connect Action Target Section ---
        Rectangle {
            width: parent.width
            height: targetCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            Column {
                id: targetCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM
                    
                    DankIcon { 
                        name: "flash_on"
                        size: 22
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                    
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXS
                        StyledText { text: "Quick Connect Action"; font.weight: Font.Medium; color: Theme.surfaceText }
                        StyledText { text: "Action executed when clicking the Quick Connect button or the Control Center tile action."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    ComboBox {
                        id: targetTypeCombo
                        Layout.fillWidth: true
                        model: ["Fastest Server", "Fastest Selected Country's Server", "Custom Server"]
                        readonly property var typeKeys: ["fastest", "country_fastest", "custom"]
                        currentIndex: Math.max(0, typeKeys.indexOf(root.quickConnectType))
                        
                        onActivated: function(index) {
                            let val = typeKeys[index];
                            root.quickConnectType = val;
                            root.saveValue("quickConnectType", val);
                        }

                        delegate: ItemDelegate {
                            width: targetTypeCombo.width
                            contentItem: StyledText {
                                text: modelData
                                color: highlighted ? Theme.primary : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: highlighted ? Theme.withAlpha(Theme.primary, 0.1) : "transparent"
                            }
                        }

                        contentItem: StyledText {
                            leftPadding: Theme.spacingS
                            rightPadding: targetTypeCombo.indicator ? targetTypeCombo.indicator.width + targetTypeCombo.spacing : Theme.spacingM
                            text: targetTypeCombo.displayText
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            border.color: targetTypeCombo.pressed ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)
                            border.width: targetTypeCombo.visualFocus ? 2 : 1
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                            radius: Theme.cornerRadius
                        }

                        popup: Popup {
                            y: targetTypeCombo.height + 2
                            width: targetTypeCombo.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 1

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: targetTypeCombo.popup.visible ? targetTypeCombo.delegateModel : null
                                currentIndex: targetTypeCombo.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }

                            background: Rectangle {
                                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                border.color: Theme.withAlpha(Theme.outline, 0.5)
                                border.width: 1
                                radius: Theme.cornerRadius
                            }
                        }
                    }
                }

                // Sub-Option 1: Country selection for "country_fastest"
                RowLayout {
                    width: parent.width
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
                            border.color: countryCombo.pressed ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)
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
                                border.color: Theme.withAlpha(Theme.outline, 0.5)
                                border.width: 1
                                radius: Theme.cornerRadius
                            }
                        }
                    }
                }

                // Sub-Option 2: Custom Server text input for "custom"
                RowLayout {
                    width: parent.width
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

        // --- Toggle Option: Show Connect Container (Server List) ---
        Rectangle {
            width: parent.width
            height: connCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            Column {
                id: connCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM
                    
                    DankIcon { 
                        name: "dns"
                        size: 22
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                    
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXS
                        StyledText { text: "Show Countries & Server List For Manual Connection"; font.weight: Font.Medium; color: Theme.surfaceText }
                        StyledText { text: "Show or hide the countries and servers list for manual selection."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap }
                    }

                    DankToggle {
                        id: showConnectSwitch
                        Layout.alignment: Qt.AlignVCenter
                        checked: root.showConnectContainer
                        onToggled: function(newChecked) {
                            checked = newChecked;
                            root.showConnectContainer = newChecked;
                            root.saveValue("showConnectContainer", newChecked);
                        }
                    }
                }
            }
        }

        // --- Toggle Option: Show Speed Monitor Container ---
        Rectangle {
            width: parent.width
            height: speedCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            Column {
                id: speedCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM
                    
                    DankIcon { 
                        name: "speed"
                        size: 22
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                    
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXS
                        StyledText { text: "Show Speed Monitor"; font.weight: Font.Medium; color: Theme.surfaceText }
                        StyledText { text: "Show or hide the real-time upload and download speed container."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap }
                    }

                    DankToggle {
                        id: showSpeedSwitch
                        Layout.alignment: Qt.AlignVCenter
                        checked: root.showSpeedContainer
                        onToggled: function(newChecked) {
                            checked = newChecked;
                            root.showSpeedContainer = newChecked;
                            root.saveValue("showSpeedContainer", newChecked);
                        }
                    }
                }
            }
        }

        // --- Paid Servers Only Filter Section ---
        Rectangle {
            width: parent.width
            height: paidCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            Column {
                id: paidCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM
                    
                    DankIcon { 
                        name: "monetization_on"
                        size: 22
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                    
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXS
                        StyledText { text: "Only Show Paid Servers"; font.weight: Font.Medium; color: Theme.surfaceText }
                        StyledText { text: "WARNING: Only for Paid users. If enabled, free servers will be hidden from the list."; font.pixelSize: Theme.fontSizeSmall; color: Theme.error; width: parent.width; wrapMode: Text.WordWrap }
                    }

                    DankToggle {
                        id: paidServersSwitch
                        Layout.alignment: Qt.AlignVCenter
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
