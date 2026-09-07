import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root

    property var discoveredDatabases: []
    property string bannerMsg: ""
    property string bannerType: "info" // "info", "success", "error"

    function loadDatabasesList() {
        if (backend) {
            discoveredDatabases = backend.get_available_databases() || [];
        }
    }

    Component.onCompleted: {
        loadDatabasesList();
    }

    // Connect to backend settings signals
    Connections {
        target: backend

        function onSettingsChanged() {
            root.loadDatabasesList();
        }

        function onStatsChanged() {
            root.loadDatabasesList();
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        clip: true

        ColumnLayout {
            width: Math.min(1080, parent.width - 48)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20

            Item { height: 6 }

            // ==========================================
            // Page Header with Connect New Project Button
            // ==========================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Column {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Settings & Project Configuration"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }

                    Text {
                        text: "Select a different SQLite cache database, switch active projects, or connect to a new TFS instance"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#8b949e"
                    }
                }

                // Connect New Project Button
                Button {
                    text: "➕ Connect New Project..."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 36
                        implicitWidth: 190
                        radius: 6
                        color: parent.hovered ? "#2ea043" : "#238636"
                        border.color: "#3fb950"
                        border.width: 1
                    }
                    onClicked: newProjectDialog.open()
                }
            }

            // Notification / Feedback Banner
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 6
                visible: root.bannerMsg !== ""
                color: root.bannerType === "success" ? "#162b20" : (root.bannerType === "error" ? "#3c1e1e" : "#16243b")
                border.color: root.bannerType === "success" ? "#238636" : (root.bannerType === "error" ? "#f85149" : "#388bfd")
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: root.bannerType === "success" ? "✓" : (root.bannerType === "error" ? "⚠️" : "ℹ️")
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: root.bannerType === "success" ? "#3fb950" : (root.bannerType === "error" ? "#f85149" : "#58a6ff")
                    }

                    Text {
                        text: root.bannerMsg
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: root.bannerType === "success" ? "#3fb950" : (root.bannerType === "error" ? "#f85149" : "#79c0ff")
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "✕"
                        font.pixelSize: 11
                        color: "#8b949e"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.bannerMsg = ""
                        }
                    }
                }
            }

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
            // Agile & Deadline Attribute Configuration Card
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: deadlineCol.implicitHeight + 36
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: deadlineCol
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    RowLayout {
                        spacing: 8
                        Text { text: "🎯"; font.pixelSize: 16 }
                        Text {
                            text: "Work Item Deadline Attribute Configuration"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                    }

                    Text {
                        text: "Specify a custom TFS / Azure DevOps field reference name used for milestone deadlines (e.g. Custom.MilestoneDeadline). If left empty, the application automatically inspects Microsoft.VSTS.Scheduling.TargetDate, DueDate, FinishDate, or weekly sprint milestone dates."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        TextField {
                            id: deadlineFieldInput
                            Layout.fillWidth: true
                            implicitHeight: 34
                            font.family: "Consolas, monospace"
                            font.pixelSize: 12
                            text: (backend && backend.customDeadlineField) ? backend.customDeadlineField : ""
                            placeholderText: "e.g. Microsoft.VSTS.Scheduling.TargetDate or Custom.MilestoneDeadline"
                            placeholderTextColor: "#484f58"
                            color: "#f0f6fc"
                            background: Rectangle {
                                color: "#0d1117"
                                radius: 6
                                border.color: deadlineFieldInput.activeFocus ? "#58a6ff" : "#30363d"
                                border.width: 1
                            }
                        }

                        Button {
                            text: "💾 Save Attribute"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            contentItem: Text {
                                text: parent.text; font: parent.font; color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 34; implicitWidth: 130; radius: 6
                                color: parent.hovered ? "#1f6feb" : "#238636"
                                border.color: "#3fb950"
                            }
                            onClicked: {
                                if (backend) {
                                    backend.setCustomDeadlineField(deadlineFieldInput.text);
                                    root.bannerMsg = "Custom deadline field updated to: " + (deadlineFieldInput.text.trim() || "Default (TargetDate / DueDate)");
                                    root.bannerType = "success";
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Bug Hierarchy & Container Grouping Card
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: bugHierarchyCol.implicitHeight + 36
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: bugHierarchyCol
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text { text: "🪲"; font.pixelSize: 20 }

                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Bug Hierarchy & Workload Container Grouping"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Text {
                                text: "Configure how Bugs are structured and grouped in the Workload Explorer & Agile views"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 10
                        columnSpacing: 10

                        Repeater {
                            model: [
                                {
                                    mode: "like_user_story",
                                    title: "Bugs as Stories (Containers)",
                                    desc: "Bugs are top-level backlog items that contain individual tasks. Recommended for Scrum / Agile projects where bugs are tracked like User Stories.",
                                    badge: "Top-Level Container"
                                },
                                {
                                    mode: "like_task",
                                    title: "Bugs as Tasks (Child Items)",
                                    desc: "Bugs are child work items contained within parent User Stories or Requirements. Recommended for projects where bugs belong directly to stories.",
                                    badge: "Child Task Item"
                                }
                            ]

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 80
                                radius: 6
                                property bool isSelected: backend && backend.bugHierarchyMode === modelData.mode
                                color: isSelected ? "#0d2344" : (bugOptMa.containsMouse ? "#21262d" : "#0d1117")
                                border.color: isSelected ? "#1f6feb" : (bugOptMa.containsMouse ? "#388bfd" : "#30363d")
                                border.width: isSelected ? 2 : 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    // Radio Indicator
                                    Rectangle {
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: parent.parent.isSelected ? "#1f6feb" : "#161b22"
                                        border.color: parent.parent.isSelected ? "#58a6ff" : "#30363d"
                                        border.width: 1

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: "#ffffff"
                                            visible: parent.parent.parent.isSelected
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: modelData.title
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: parent.parent.parent.parent.isSelected ? "#f0f6fc" : "#e6edf3"
                                            }

                                            Rectangle {
                                                implicitHeight: 16
                                                implicitWidth: bugBadgeLabel.implicitWidth + 8
                                                radius: 8
                                                color: parent.parent.parent.parent.isSelected ? "#1f6feb" : "#21262d"
                                                Text {
                                                    id: bugBadgeLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.badge
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    color: parent.parent.parent.parent.parent.isSelected ? "#ffffff" : "#8b949e"
                                                }
                                            }
                                        }

                                        Text {
                                            text: modelData.desc
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: bugOptMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend) {
                                            backend.setBugHierarchyMode(modelData.mode);
                                            root.bannerMsg = "Bug hierarchy mode updated to: " + modelData.title;
                                            root.bannerType = "success";
                                        }
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

            // Display & Typography Sizing Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fontSettingCol.implicitHeight + 36
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: fontSettingCol
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text { text: "🔤"; font.pixelSize: 20 }

                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Display & Typography Scaling"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Text {
                                text: "Adjust font size and interface scaling for high-DPI (2K/4K) monitors or compact viewing"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 10
                        columnSpacing: 10

                        Repeater {
                            model: [
                                {
                                    mode: "small",
                                    title: "Small (90%)",
                                    desc: "Compact view for dense data tables and smaller screens",
                                    badge: "Compact"
                                },
                                {
                                    mode: "medium",
                                    title: "Medium (100% - Default)",
                                    desc: "Standard balanced scale for regular 1080p monitors",
                                    badge: "Standard"
                                },
                                {
                                    mode: "large",
                                    title: "Large (115%)",
                                    desc: "Enhanced readability for larger displays and text clarity",
                                    badge: "Enhanced"
                                },
                                {
                                    mode: "xlarge",
                                    title: "Extra Large (130%)",
                                    desc: "High-DPI / 4K monitors and high-accessibility viewing",
                                    badge: "4K / HiDPI"
                                }
                            ]

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 68
                                radius: 6
                                property bool isSelected: backend && backend.fontSizeMode === modelData.mode
                                color: isSelected ? "#0d2344" : (optMa.containsMouse ? "#21262d" : "#0d1117")
                                border.color: isSelected ? "#1f6feb" : (optMa.containsMouse ? "#388bfd" : "#30363d")
                                border.width: isSelected ? 2 : 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    // Radio Indicator
                                    Rectangle {
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: parent.parent.isSelected ? "#1f6feb" : "#161b22"
                                        border.color: parent.parent.isSelected ? "#58a6ff" : "#30363d"
                                        border.width: 1

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: "#ffffff"
                                            visible: parent.parent.parent.isSelected
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: modelData.title
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: parent.parent.parent.parent.isSelected ? "#f0f6fc" : "#e6edf3"
                                            }

                                            Rectangle {
                                                implicitHeight: 16
                                                implicitWidth: bLabel.implicitWidth + 8
                                                radius: 8
                                                color: parent.parent.parent.parent.isSelected ? "#1f6feb" : "#21262d"
                                                Text {
                                                    id: bLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.badge
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    color: parent.parent.parent.parent.parent.isSelected ? "#ffffff" : "#8b949e"
                                                }
                                            }
                                        }

                                        Text {
                                            text: modelData.desc
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: optMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend) {
                                            backend.setFontSizeMode(modelData.mode);
                                            root.bannerMsg = "Font size updated to " + modelData.title;
                                            root.bannerType = "success";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // About Application Card
            Rectangle {
                Layout.fillWidth: true
                height: 100
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 6

                    Text {
                        text: "About DevOps Manager"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }

                    Text {
                        text: "Desktop interface for managing multi-repository Azure DevOps (TFS) pipelines, Work Item WIQL sync, Tag Day releases, and Build Artifact storage."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Item { height: 20 }
        }
    }

    // Modal New Project Dialog
    NewProjectDialog {
        id: newProjectDialog
        onProjectCreated: function(pName, dPath) {
            root.bannerMsg = "Project '" + pName + "' connected and database created successfully!";
            root.bannerType = "success";
            root.loadDatabasesList();
        }
    }
}
