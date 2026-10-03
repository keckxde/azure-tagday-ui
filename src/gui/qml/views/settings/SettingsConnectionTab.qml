import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

ColumnLayout {
    id: tabRoot
    Layout.fillWidth: true
    spacing: 16

    // ==========================================
    // Active Database & Connection Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: activeDbCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: activeDbCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Active Database & TFS Environment"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }

                Item { Layout.fillWidth: true }

                // Active status pill
                Rectangle {
                    implicitHeight: 22
                    implicitWidth: activePillText.implicitWidth + 14
                    radius: 11
                    color: (backend && backend.dbPath) ? "#162b20" : "#3c1e1e"
                    border.color: (backend && backend.dbPath) ? "#238636" : "#f85149"
                    border.width: 1

                    Text {
                        id: activePillText
                        anchors.centerIn: parent
                        text: (backend && backend.dbPath) ? "● Connected" : "● Not Connected"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: (backend && backend.dbPath) ? "#3fb950" : "#f85149"
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#21262d"
            }

            // Database Path
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "Database Path:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                    Layout.preferredWidth: 130
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 4
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: (backend && backend.dbPath) ? backend.dbPath : "No database selected"
                            font.family: "Consolas, monospace"
                            font.pixelSize: 11
                            color: "#58a6ff"
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }

                        Text {
                            text: "📋"
                            font.pixelSize: 11
                            opacity: copyDbMa.containsMouse ? 1.0 : 0.6
                            MouseArea {
                                id: copyDbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (backend && backend.dbPath) {
                                        backend.copy_to_clipboard(backend.dbPath);
                                        root.bannerMsg = "Database path copied to clipboard!";
                                        root.bannerType = "info";
                                    }
                                }
                            }
                            ToolTip.visible: copyDbMa.containsMouse
                            ToolTip.text: "Copy full path to clipboard"
                        }
                    }
                }
            }

            // Active Project
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "Active Project:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                    Layout.preferredWidth: 130
                }

                Text {
                    text: (backend && backend.projectName) ? backend.projectName : "N/A"
                    font.family: "Consolas, monospace"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }
            }

            // TFS Server & Collection
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "TFS Server URL:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                    Layout.preferredWidth: 130
                }

                Text {
                    text: (backend && backend.tfsUrl) ? (backend.tfsUrl + "/" + backend.tfsCollection) : "N/A"
                    font.family: "Consolas, monospace"
                    font.pixelSize: 11
                    color: "#8b949e"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            // Last Synced
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "Last Synced:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                    Layout.preferredWidth: 130
                }

                Text {
                    text: (backend && backend.lastSynced) ? backend.lastSynced : "Never"
                    font.family: "Consolas, monospace"
                    font.pixelSize: 12
                    color: "#3fb950"
                }
            }

            // Area Path Filter Status
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "Area Path Filter:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                    Layout.preferredWidth: 130
                }

                RowLayout {
                    spacing: 8

                    Rectangle {
                        implicitHeight: 20
                        implicitWidth: areaFilterPillText.implicitWidth + 12
                        radius: 10
                        color: (backend && backend.areaPathFilterEnabled) ? "#162b20" : "#3c2d1e"
                        border.color: (backend && backend.areaPathFilterEnabled) ? "#238636" : "#d29922"
                        border.width: 1

                        Text {
                            id: areaFilterPillText
                            anchors.centerIn: parent
                            text: (backend && backend.areaPathFilterEnabled) 
                                ? ("● Active (" + (backend.areaPathRules ? backend.areaPathRules.length : 0) + " rules)")
                                : "● Disabled"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: (backend && backend.areaPathFilterEnabled) ? "#3fb950" : "#e3b341"
                        }
                    }

                    Text {
                        text: (backend && backend.defaultAreaPath) ? ("Default: " + backend.defaultAreaPath) : ""
                        font.family: "Consolas, monospace"
                        font.pixelSize: 11
                        color: "#8b949e"
                        visible: !!(backend && backend.defaultAreaPath && backend.defaultAreaPath !== "")
                    }
                }
            }

            // Action Buttons Bar
            RowLayout {
                spacing: 10
                Layout.topMargin: 4

                // Select / Switch Database File
                Button {
                    text: "📁 Select / Switch Database File..."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0f6fc"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 32
                        implicitWidth: 230
                        radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: parent.hovered ? "#58a6ff" : "#30363d"
                        border.width: 1
                    }
                    onClicked: {
                        if (backend) {
                            var chosen = backend.browse_database_file();
                            if (chosen && chosen.trim() !== "") {
                                var success = backend.switch_database(chosen);
                                if (success) {
                                    root.bannerMsg = "Switched to database: " + chosen;
                                    root.bannerType = "success";
                                    root.loadDatabasesList();
                                } else {
                                    root.bannerMsg = "Failed to switch to database: " + chosen;
                                    root.bannerType = "error";
                                }
                            }
                        }
                    }
                }

                // Open DB Folder in Windows Explorer
                Button {
                    text: "📂 Open Folder"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 32
                        implicitWidth: 110
                        radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: "#30363d"
                        border.width: 1
                    }
                    onClicked: {
                        if (backend) backend.open_db_folder();
                    }
                }

                // Reconnect & Refresh Cache
                Button {
                    text: "🔄 Reconnect & Refresh"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 32
                        implicitWidth: 160
                        radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: "#30363d"
                        border.width: 1
                    }
                    onClicked: {
                        if (backend) {
                            backend.reconnect_cache();
                            root.bannerMsg = "Database cache reconnected and reloaded.";
                            root.bannerType = "success";
                            root.loadDatabasesList();
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // Available / Discovered Databases in Workspace
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: discCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: discCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Discovered Databases in Workspace"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "🔄 Rescan"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#8b949e"
                    }
                    background: Rectangle {
                        implicitHeight: 26
                        implicitWidth: 70
                        radius: 4
                        color: parent.hovered ? "#30363d" : "transparent"
                        border.color: "#30363d"
                    }
                    onClicked: root.loadDatabasesList()
                }
            }

            Text {
                text: "All SQLite databases (.db) found in the project root and workspace folders:"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 11
                color: "#8b949e"
            }

            // Databases Table Header
            Rectangle {
                Layout.fillWidth: true
                height: 32
                color: "#0d1117"
                radius: 4
                border.color: "#30363d"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text { text: "DATABASE FILE"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e"; Layout.preferredWidth: 220 }
                    Text { text: "PROJECT"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e"; Layout.preferredWidth: 150 }
                    Text { text: "SIZE"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e"; Layout.preferredWidth: 80 }
                    Text { text: "LAST MODIFIED"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e"; Layout.fillWidth: true }
                    Text { text: "ACTION"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e"; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
                }
            }

            // Repeater for Discovered Databases
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: root.discoveredDatabases

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: 4
                        color: modelData.is_active ? Qt.rgba(31/255, 111/255, 235/255, 0.12) : (dbItemMa.containsMouse ? "#21262d" : "#0d1117")
                        border.color: modelData.is_active ? "#1f6feb" : "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            // Database Name
                            Row {
                                Layout.preferredWidth: 220
                                spacing: 6
                                Layout.alignment: Qt.AlignVCenter

                                Text { text: "💾"; font.pixelSize: 12 }
                                Text {
                                    text: modelData.name
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: modelData.is_active ? Font.Bold : Font.DemiBold
                                    color: modelData.is_active ? "#58a6ff" : "#f0f6fc"
                                    elide: Text.ElideRight
                                }
                            }

                            // Project
                            Text {
                                text: modelData.project || "Unknown"
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                color: "#c9d1d9"
                                Layout.preferredWidth: 150
                                elide: Text.ElideRight
                            }

                            // Size
                            Text {
                                text: modelData.size_mb
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                color: "#8b949e"
                                Layout.preferredWidth: 80
                            }

                            // Last Modified
                            Text {
                                text: modelData.modified
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                color: "#8b949e"
                                Layout.fillWidth: true
                            }

                            // Action (Active Pill or Switch Button)
                            Rectangle {
                                Layout.preferredWidth: 80
                                implicitHeight: 24
                                radius: 4
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                color: modelData.is_active ? "#162b20" : (swMa.containsMouse ? "#1f6feb" : "#21262d")
                                border.color: modelData.is_active ? "#238636" : (swMa.containsMouse ? "#58a6ff" : "#30363d")

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.is_active ? "✓ Active" : "Switch"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: modelData.is_active ? "#3fb950" : (swMa.containsMouse ? "#ffffff" : "#c9d1d9")
                                }

                                MouseArea {
                                    id: swMa
                                    anchors.fill: parent
                                    enabled: !modelData.is_active
                                    hoverEnabled: true
                                    cursorShape: modelData.is_active ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend) {
                                            var ok = backend.switch_database(modelData.path);
                                            if (ok) {
                                                root.bannerMsg = "Switched to database: " + modelData.name;
                                                root.bannerType = "success";
                                                root.loadDatabasesList();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: dbItemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            cursorShape: Qt.ArrowCursor
                        }
                    }
                }

                // Empty placeholder
                Item {
                    Layout.fillWidth: true
                    height: 40
                    visible: root.discoveredDatabases.length === 0

                    Text {
                        anchors.centerIn: parent
                        text: "No databases detected in the workspace folder. Click 'Connect New Project...' above to create one."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#8b949e"
                    }
                }
            }
        }
    }

    // ==========================================
    // Scheduled Synchronization & Auto-Sync Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: autoSyncCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: autoSyncCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text { text: "⏱️"; font.pixelSize: 20 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Scheduled Synchronization (Auto-Sync)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Periodically synchronize TFS / Azure DevOps in the background. Manual syncs can still be triggered at any time."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }

                Item { Layout.fillWidth: true }

                // Enable / Disable Switch Pill
                Rectangle {
                    implicitHeight: 28
                    implicitWidth: autoSyncSwitchLayout.implicitWidth + 20
                    radius: 14
                    color: backend && backend.autoSyncEnabled ? "#162b20" : "#21262d"
                    border.color: backend && backend.autoSyncEnabled ? "#238636" : "#30363d"
                    border.width: 1

                    RowLayout {
                        id: autoSyncSwitchLayout
                        anchors.centerIn: parent
                        spacing: 8

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: backend && backend.autoSyncEnabled ? "#3fb950" : "#8b949e"
                        }

                        Text {
                            text: backend && backend.autoSyncEnabled ? "Auto-Sync Enabled" : "Auto-Sync Disabled"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: backend && backend.autoSyncEnabled ? "#3fb950" : "#8b949e"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (backend) {
                                backend.setAutoSyncEnabled(!backend.autoSyncEnabled);
                                root.bannerMsg = backend.autoSyncEnabled
                                    ? ("Scheduled synchronization enabled (every " + backend.autoSyncIntervalMinutes + " min).")
                                    : "Scheduled synchronization disabled.";
                                root.bannerType = backend.autoSyncEnabled ? "success" : "info";
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Sync Interval Selection
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Sync Interval:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#c9d1d9"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { label: "1 min",  minutes: 1 },
                            { label: "2 min",  minutes: 2 },
                            { label: "5 min (Default)",  minutes: 5 },
                            { label: "10 min", minutes: 10 },
                            { label: "15 min", minutes: 15 },
                            { label: "30 min", minutes: 30 },
                            { label: "60 min", minutes: 60 }
                        ]

                        Rectangle {
                            property bool isCur: backend && backend.autoSyncIntervalMinutes === modelData.minutes
                            implicitHeight: 30
                            implicitWidth: intervalBtnText.implicitWidth + 16
                            radius: 5
                            color: isCur ? "#1f6feb" : (intMa.containsMouse ? "#21262d" : "#0d1117")
                            border.color: isCur ? "#58a6ff" : (intMa.containsMouse ? "#388bfd" : "#30363d")
                            border.width: 1

                            Text {
                                id: intervalBtnText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: parent.isCur ? Font.Bold : Font.Normal
                                color: parent.isCur ? "#ffffff" : "#c9d1d9"
                            }

                            MouseArea {
                                id: intMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (backend) {
                                        backend.setAutoSyncInterval(modelData.minutes);
                                        root.bannerMsg = "Auto-sync interval set to " + modelData.minutes + " minute(s).";
                                        root.bannerType = "success";
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            // Scope Selection
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Sync Scope:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#c9d1d9"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: [
                            { mode: "all",           label: "🔄 Full Sync (All Repos, WIQL & PRs)", desc: "Synchronizes git repos, work items, and pull requests" },
                            { mode: "work_items",    label: "⚡ Work Items (WIQL) Only",           desc: "Fast agile work items and query status sync" },
                            { mode: "pull_requests", label: "🔀 Pull Requests Only",               desc: "Lightweight pull requests status sync" }
                        ]

                        Rectangle {
                            property bool isCur: backend && backend.autoSyncScope === modelData.mode
                            implicitHeight: 34
                            implicitWidth: scopeBtnText.implicitWidth + 20
                            radius: 6
                            color: isCur ? Qt.rgba(31/255, 111/255, 235/255, 0.15) : (scopeMa.containsMouse ? "#21262d" : "#0d1117")
                            border.color: isCur ? "#1f6feb" : (scopeMa.containsMouse ? "#58a6ff" : "#30363d")
                            border.width: isCur ? 2 : 1

                            Text {
                                id: scopeBtnText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: parent.isCur ? Font.Bold : Font.Normal
                                color: parent.isCur ? "#58a6ff" : "#c9d1d9"
                            }

                            MouseArea {
                                id: scopeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (backend) {
                                        backend.setAutoSyncScope(modelData.mode);
                                        root.bannerMsg = "Auto-sync scope updated.";
                                        root.bannerType = "success";
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            // Live Status & Quick Action Row
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: 6
                color: "#0d1117"
                border.color: "#21262d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Text {
                        text: "Live Status:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#8b949e"
                    }

                    Text {
                        text: backend ? backend.autoSyncStatusText : "N/A"
                        font.family: "Consolas, monospace"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: backend && backend.autoSyncEnabled ? "#58a6ff" : "#8b949e"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "Triggering a manual sync automatically resets the countdown timer."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#6e7681"
                    }

                    Button {
                        text: "⚡ Trigger Sync Now"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        enabled: backend ? !backend.isBusy : false
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.parent.enabled ? "#ffffff" : "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 26
                            implicitWidth: 135
                            radius: 4
                            color: parent.enabled ? (parent.hovered ? "#1f6feb" : "#238636") : "#21262d"
                            border.color: parent.enabled ? "#3fb950" : "#30363d"
                        }
                        onClicked: {
                            if (backend) {
                                backend.triggerAutoSyncNow();
                                root.bannerMsg = "Manual synchronization started.";
                                root.bannerType = "info";
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // Recent Projects History Card (if any)
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: recentCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1
        visible: backend && backend.recentProjects && backend.recentProjects.length > 0

        ColumnLayout {
            id: recentCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: "Previously Connected Projects"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 15
                font.weight: Font.Bold
                color: "#f0f6fc"
            }

            Repeater {
                model: backend ? backend.recentProjects : []

                delegate: Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 4
                    color: isCurrentProj ? Qt.rgba(31/255, 111/255, 235/255, 0.12) : (recProjMa.containsMouse ? "#21262d" : "#0d1117")
                    border.color: isCurrentProj ? "#1f6feb" : "#30363d"
                    border.width: 1

                    property bool isCurrentProj: backend && backend.projectName === modelData.name

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Text { text: "📦"; font.pixelSize: 12 }

                        Text {
                            text: modelData.name
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: isCurrentProj ? "#58a6ff" : "#f0f6fc"
                            Layout.preferredWidth: 180
                        }

                        Text {
                            text: (modelData.url || "") + "/" + (modelData.collection || "")
                            font.family: "Consolas, monospace"
                            font.pixelSize: 11
                            color: "#8b949e"
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }

                        Text {
                            text: modelData.date || ""
                            font.family: "Consolas, monospace"
                            font.pixelSize: 10
                            color: "#6e7681"
                            Layout.preferredWidth: 110
                        }

                        Button {
                            text: isCurrentProj ? "Active" : "Switch Project"
                            enabled: !isCurrentProj
                            font.pixelSize: 11
                            background: Rectangle {
                                implicitHeight: 24
                                implicitWidth: 90
                                radius: 4
                                color: isCurrentProj ? "#162b20" : (parent.hovered ? "#1f6feb" : "#21262d")
                                border.color: isCurrentProj ? "#238636" : "#30363d"
                            }
                            onClicked: {
                                if (backend && modelData.db_path) {
                                    backend.switch_database(modelData.db_path);
                                    root.bannerMsg = "Switched to project: " + modelData.name;
                                    root.bannerType = "success";
                                    root.loadDatabasesList();
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: recProjMa
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: true
                        cursorShape: Qt.ArrowCursor
                    }
                }
            }
        }
    }
}
