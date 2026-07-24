import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "protonVPN"

    Column {
        id: mainSettingsCol
        width: parent.width
        spacing: Theme.spacingL

        function loadValue(key, def) {
            return PluginService.loadPluginData(root.pluginId, key, def);
        }

        function saveValue(key, val) {
            PluginService.savePluginData(root.pluginId, key, val);
            PluginService.setGlobalVar(root.pluginId, key, val);
        }

        // --- Settings State ---
        property string defaultProtocol: "smart"
        property string defaultConnectTarget: "fastest"

        function loadAll() {
            defaultProtocol = loadValue("defaultProtocol", "smart");
            defaultConnectTarget = loadValue("defaultConnectTarget", "fastest");
        }

        Component.onCompleted: loadAll()

        // --- Proton VPN Connection Protocol Section ---
        Rectangle {
            width: parent.width
            height: generalCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.9

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
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXS
                        StyledText { text: "Connection Protocol"; font.weight: Font.Medium; color: Theme.surfaceText }
                        StyledText { text: "Select preferred backend protocol passed directly via --protocol flag to pvpnctl."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: ["smart", "wireguard", "stealth"]
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: Theme.cornerRadius
                            color: root.defaultProtocol === modelData ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Theme.surfaceContainerHigh
                            border.color: root.defaultProtocol === modelData ? Theme.primary : Theme.outline
                            border.width: 1

                            StyledText {
                                text: modelData.toUpperCase()
                                anchors.centerIn: parent
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                                color: root.defaultProtocol === modelData ? Theme.primary : Theme.surfaceText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.defaultProtocol = modelData;
                                    mainSettingsCol.saveValue("defaultProtocol", modelData);
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- Default Quick Connect Target Section ---
        Rectangle {
            width: parent.width
            height: targetCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.9

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
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXS
                        StyledText { text: "Default Connect Target"; font.weight: Font.Medium; color: Theme.surfaceText }
                        StyledText { text: "Default server or country code for the header Connect button (e.g. 'fastest', 'US', 'NL')."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    DankTextField {
                        id: targetField
                        Layout.fillWidth: true
                        text: root.defaultConnectTarget
                        placeholderText: "fastest"
                        onEditingFinished: {
                            let val = targetField.text.trim() || "fastest";
                            root.defaultConnectTarget = val;
                            mainSettingsCol.saveValue("defaultConnectTarget", val);
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
                                let val = targetField.text.trim() || "fastest";
                                root.defaultConnectTarget = val;
                                mainSettingsCol.saveValue("defaultConnectTarget", val);
                            }
                        }
                    }
                }
            }
        }
    }
}
