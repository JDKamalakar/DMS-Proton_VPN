import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "protonVPN"

    // --- Settings State on Root ---
    property string defaultProtocol: "smart"
    property string defaultConnectTarget: "fastest"
    property bool paidServersOnly: false

    function loadValue(key, def) {
        return PluginService.loadPluginData(root.pluginId, key, def);
    }

    function saveValue(key, val) {
        PluginService.savePluginData(root.pluginId, key, val);
        PluginService.setGlobalVar(root.pluginId, key, val);
    }

    function loadAll() {
        defaultProtocol = loadValue("defaultProtocol", "smart");
        defaultConnectTarget = loadValue("defaultConnectTarget", "fastest");
        paidServersOnly = loadValue("paidServersOnly", false);
    }

    Component.onCompleted: loadAll()

    Column {
        id: mainSettingsCol
        width: parent.width
        spacing: Theme.spacingL

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
                        StyledText { text: "Select preferred backend protocol. This is passed directly via --protocol flag on connect."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    ComboBox {
                        id: protocolCombo
                        Layout.fillWidth: true
                        model: ["smart", "wireguard", "stealth"]
                        currentIndex: Math.max(0, model.indexOf(root.defaultProtocol))
                        
                        onActivated: function(index) {
                            let val = protocolCombo.model[index];
                            root.defaultProtocol = val;
                            root.saveValue("defaultProtocol", val);
                        }

                        contentItem: StyledText {
                            leftPadding: 12
                            rightPadding: 12
                            text: protocolCombo.displayText
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        background: Rectangle {
                            color: Theme.surfaceContainerHigh
                            border.color: Theme.outline
                            border.width: 1
                            radius: Theme.cornerRadius
                        }

                        delegate: ItemDelegate {
                            width: protocolCombo.width
                            contentItem: StyledText {
                                text: modelData
                                color: highlighted ? Theme.surface : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: highlighted ? Font.Bold : Font.Normal
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            background: Rectangle {
                                color: highlighted ? Theme.primary : Theme.surfaceContainerHigh
                                radius: 4
                            }
                        }

                        popup: Popup {
                            y: protocolCombo.height + 4
                            width: protocolCombo.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 4
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: protocolCombo.popup.visible ? protocolCombo.delegateModel : null
                                currentIndex: protocolCombo.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                            background: Rectangle {
                                color: Theme.surfaceContainerHigh
                                border.color: Theme.outline
                                border.width: 1
                                radius: Theme.cornerRadius
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
                            root.saveValue("defaultConnectTarget", val);
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
                                root.saveValue("defaultConnectTarget", val);
                            }
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
            opacity: 0.9

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
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXS
                        StyledText { text: "Only Show Paid Servers"; font.weight: Font.Medium; color: Theme.surfaceText }
                        StyledText { text: "WARNING: Only for Paid users. If enabled, free servers will be hidden from the list."; font.pixelSize: Theme.fontSizeSmall; color: Theme.error; width: parent.width; wrapMode: Text.WordWrap }
                    }

                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: root.paidServersOnly ? Theme.primary : Theme.surfaceContainerHigh
                        border.color: root.paidServersOnly ? Theme.primary : Theme.outline
                        border.width: 1

                        Rectangle {
                            width: 18; height: 18; radius: 9
                            color: Theme.surface
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.paidServersOnly ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.paidServersOnly = !root.paidServersOnly;
                                root.saveValue("paidServersOnly", root.paidServersOnly);
                            }
                        }
                    }
                }
            }
        }
    }
}
