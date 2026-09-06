import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: dialogRoot
    anchors.fill: parent
    visible: false
    z: 1000

    signal projectCreated(string projectName, string dbPath)

    // Form state
    property string tfsUrl: (backend && backend.tfsUrl) ? backend.tfsUrl : "https://tfs.example.com/tfs"
    property string tfsCollection: (backend && backend.tfsCollection) ? backend.tfsCollection : "DefaultCollection"
    property string tfsPat: (backend && backend.tfsPat) ? backend.tfsPat : ""
    property bool storePat: true
    property bool showPatText: false
    property bool isConnecting: false
    property string connectionError: ""
    property string connectionSuccessMsg: ""
    
    // Project selection
    property var projectList: []
    property string projectSearchKeyword: ""
    property var selectedProject: null
    property string targetDbPath: ""
    property bool startSyncAfterCreate: true

    function open() {
        if (backend) {
            tfsUrl = backend.tfsUrl || "";
            tfsCollection = backend.tfsCollection || "DefaultCollection";
            tfsPat = backend.tfsPat || "";
        }
        connectionError = "";
        connectionSuccessMsg = "";
        projectList = [];
        selectedProject = null;
        targetDbPath = "";
        projectSearchKeyword = "";
        dialogRoot.visible = true;
    }

    function close() {
        dialogRoot.visible = false;
    }

    // Modal background dimmer
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)
        MouseArea {
            anchors.fill: parent
            onClicked: { /* consume clicks */ }
        }
    }

    // Dialog Window Container
    Rectangle {
        id: dialogBox
        width: Math.min(680, parent.width - 32)
        height: Math.min(720, parent.height - 32)
        anchors.centerIn: parent
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                height: 56
                color: "#0d1117"
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 16
                    spacing: 12

                    Text {
                        text: "⚡"
                        font.pixelSize: 18
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Connect Azure DevOps / TFS Project"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }

                        Text {
                            text: "Connect to TFS server, choose a project, and create a new cache database"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 4
                        color: closeBtnMa.containsMouse ? "#30363d" : "transparent"
                        border.color: "#30363d"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 12
                            color: "#8b949e"
                        }

                        MouseArea {
                            id: closeBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dialogRoot.close()
                        }
                    }
                }
            }

            // Scrollable Content
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: dialogBox.width - 24
                clip: true

                ColumnLayout {
                    width: dialogBox.width - 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    Item { height: 4 }

                    // ==========================================
                    // 1. TFS Server & Authentication
                    // ==========================================
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: authCol.implicitHeight + 24
                        color: "#0d1117"
                        radius: 6
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: authCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Text {
                                text: "1. TFS SERVER & AUTHENTICATION"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#58a6ff"
                            }

                            // URL & Collection row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 3
                                    spacing: 4

                                    Text {
                                        text: "TFS Base URL"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 32
                                        radius: 4
                                        color: "#161b22"
                                        border.color: urlInput.activeFocus ? "#58a6ff" : "#30363d"

                                        TextInput {
                                            id: urlInput
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            verticalAlignment: Text.AlignVCenter
                                            text: dialogRoot.tfsUrl
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            color: "#f0f6fc"
                                            selectByMouse: true
                                            onTextChanged: dialogRoot.tfsUrl = text
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 2
                                    spacing: 4

                                    Text {
                                        text: "Collection"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 32
                                        radius: 4
                                        color: "#161b22"
                                        border.color: colInput.activeFocus ? "#58a6ff" : "#30363d"

                                        TextInput {
                                            id: colInput
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            verticalAlignment: Text.AlignVCenter
                                            text: dialogRoot.tfsCollection
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            color: "#f0f6fc"
                                            selectByMouse: true
                                            onTextChanged: dialogRoot.tfsCollection = text
                                        }
                                    }
                                }
                            }

                            // PAT Token Field
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Personal Access Token (PAT)"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 32
                                    radius: 4
                                    color: "#161b22"
                                    border.color: patInput.activeFocus ? "#58a6ff" : "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        TextInput {
                                            id: patInput
                                            Layout.fillWidth: true
                                            verticalAlignment: Text.AlignVCenter
                                            text: dialogRoot.tfsPat
                                            echoMode: dialogRoot.showPatText ? TextInput.Normal : TextInput.Password
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            color: "#f0f6fc"
                                            selectByMouse: true
                                            onTextChanged: dialogRoot.tfsPat = text
                                        }

                                        Text {
                                            text: dialogRoot.showPatText ? "👁️" : "🔒"
                                            font.pixelSize: 12
                                            opacity: patEyeMa.containsMouse ? 1.0 : 0.7
                                            MouseArea {
                                                id: patEyeMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: dialogRoot.showPatText = !dialogRoot.showPatText
                                            }
                                        }
                                    }
                                }
                            }

                            // Options & Connect Button Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                // Save PAT checkbox
                                Row {
                                    spacing: 6
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 3
                                        color: dialogRoot.storePat ? "#1f6feb" : "#161b22"
                                        border.color: dialogRoot.storePat ? "#58a6ff" : "#30363d"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            font.pixelSize: 10
                                            color: "#ffffff"
                                            visible: dialogRoot.storePat
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dialogRoot.storePat = !dialogRoot.storePat
                                        }
                                    }

                                    Text {
                                        text: "Save PAT locally in configuration"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#c9d1d9"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Connect & Fetch Projects Button
                                Button {
                                    text: dialogRoot.isConnecting ? "Connecting..." : "🔗 Test & Fetch Projects"
                                    enabled: !dialogRoot.isConnecting && dialogRoot.tfsUrl !== ""
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    contentItem: Row {
                                        spacing: 6
                                        anchors.centerIn: parent
                                        BusyIndicator {
                                            running: dialogRoot.isConnecting
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            visible: dialogRoot.isConnecting
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: parent.parent.text
                                            font: parent.parent.font
                                            color: "#ffffff"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    background: Rectangle {
                                        implicitHeight: 30
                                        implicitWidth: 160
                                        radius: 4
                                        color: parent.enabled ? (parent.hovered ? "#1f6feb" : "#238636") : "#21262d"
                                        border.color: parent.enabled ? "#3fb950" : "#30363d"
                                    }
                                    onClicked: {
                                        dialogRoot.isConnecting = true;
                                        dialogRoot.connectionError = "";
                                        dialogRoot.connectionSuccessMsg = "";
                                        
                                        Qt.callLater(function() {
                                            if (backend) {
                                                var res = backend.test_tfs_connection(dialogRoot.tfsUrl, dialogRoot.tfsCollection, dialogRoot.tfsPat);
                                                dialogRoot.isConnecting = false;
                                                if (res && res.success) {
                                                    dialogRoot.projectList = res.projects || [];
                                                    dialogRoot.connectionSuccessMsg = "Connected successfully! Found " + (res.count || dialogRoot.projectList.length) + " projects.";
                                                } else {
                                                    dialogRoot.connectionError = (res && res.error) ? res.error : "Unknown connection error";
                                                    dialogRoot.projectList = [];
                                                }
                                            }
                                        });
                                    }
                                }
                            }

                            // Feedback Banners
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 4
                                color: "#162b20"
                                border.color: "#238636"
                                visible: dialogRoot.connectionSuccessMsg !== ""

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    spacing: 6
                                    Text { text: "✓"; color: "#3fb950"; font.pixelSize: 11; font.weight: Font.Bold }
                                    Text {
                                        text: dialogRoot.connectionSuccessMsg
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#3fb950"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: errText.implicitHeight + 14
                                radius: 4
                                color: "#3c1e1e"
                                border.color: "#f85149"
                                visible: dialogRoot.connectionError !== ""

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    anchors.leftMargin: 10
                                    spacing: 6
                                    Text { text: "⚠️"; color: "#f85149"; font.pixelSize: 12; Layout.alignment: Qt.AlignTop }
                                    Text {
                                        id: errText
                                        text: dialogRoot.connectionError
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#f85149"
                                        wrapMode: Text.WrapAnywhere
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    // ==========================================
                    // 2. Select Project
                    // ==========================================
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: projCol.implicitHeight + 24
                        color: "#0d1117"
                        radius: 6
                        border.color: dialogRoot.selectedProject ? "#58a6ff" : "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: projCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "2. SELECT PROJECT"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#58a6ff"
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: dialogRoot.projectList.length + " projects loaded"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                    visible: dialogRoot.projectList.length > 0
                                }
                            }

                            // Project Search Filter
                            Rectangle {
                                Layout.fillWidth: true
                                height: 30
                                radius: 4
                                color: "#161b22"
                                border.color: projSearchInput.activeFocus ? "#58a6ff" : "#30363d"
                                visible: dialogRoot.projectList.length > 0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text { text: "🔍"; font.pixelSize: 11; color: "#8b949e" }

                                    TextInput {
                                        id: projSearchInput
                                        Layout.fillWidth: true
                                        verticalAlignment: Text.AlignVCenter
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#f0f6fc"
                                        selectByMouse: true
                                        onTextChanged: dialogRoot.projectSearchKeyword = text

                                        Text {
                                            text: "Filter projects by name..."
                                            font: parent.font
                                            color: "#484f58"
                                            visible: !parent.text && !parent.activeFocus
                                        }
                                    }

                                    Text {
                                        text: "✕"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                        visible: dialogRoot.projectSearchKeyword !== ""
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                projSearchInput.text = "";
                                                dialogRoot.projectSearchKeyword = "";
                                            }
                                        }
                                    }
                                }
                            }

                            // Projects List Container
                            Rectangle {
                                Layout.fillWidth: true
                                height: Math.min(180, Math.max(80, projListView.count * 36 + 10))
                                color: "#161b22"
                                radius: 4
                                border.color: "#30363d"
                                clip: true

                                ListView {
                                    id: projListView
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    clip: true
                                    spacing: 3
                                    boundsBehavior: Flickable.StopAtBounds

                                    model: dialogRoot.getFilteredProjects()

                                    delegate: Rectangle {
                                        id: projItemRect
                                        width: projListView.width
                                        height: 32
                                        radius: 4
                                        color: isSelected ? "#1f6feb" : (projItemMa.containsMouse ? "#21262d" : "transparent")
                                        border.color: isSelected ? "#58a6ff" : "transparent"

                                        property bool isSelected: dialogRoot.selectedProject && dialogRoot.selectedProject.id === modelData.id

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 8

                                            Text {
                                                text: isSelected ? "●" : "○"
                                                font.pixelSize: 11
                                                color: isSelected ? "#ffffff" : "#8b949e"
                                            }

                                            Text {
                                                text: modelData.name
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: isSelected ? Font.Bold : Font.DemiBold
                                                color: isSelected ? "#ffffff" : "#f0f6fc"
                                                Layout.preferredWidth: 220
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: modelData.description || modelData.id
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: isSelected ? "#c9d1d9" : "#8b949e"
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            id: projItemMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                dialogRoot.selectedProject = modelData;
                                                // Generate default proposed db path
                                                var defaultName = "tfs_cache_" + modelData.name + ".db";
                                                if (backend) {
                                                    dialogRoot.targetDbPath = defaultName;
                                                }
                                            }
                                        }
                                    }
                                }

                                // Placeholder if no projects loaded
                                Item {
                                    anchors.fill: parent
                                    visible: dialogRoot.projectList.length === 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Click 'Test & Fetch Projects' above to retrieve project list"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#6e7681"
                                    }
                                }
                            }
                        }
                    }

                    // ==========================================
                    // 3. Database Configuration & Sync Options
                    // ==========================================
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: dbCol.implicitHeight + 24
                        color: "#0d1117"
                        radius: 6
                        border.color: "#30363d"
                        border.width: 1
                        visible: dialogRoot.selectedProject !== null

                        ColumnLayout {
                            id: dbCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Text {
                                text: "3. TARGET DATABASE & SYNCHRONIZATION"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#58a6ff"
                            }

                            // DB Path input & Browse
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 32
                                    radius: 4
                                    color: "#161b22"
                                    border.color: "#30363d"

                                    TextInput {
                                        id: dbPathInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: Text.AlignVCenter
                                        text: dialogRoot.targetDbPath
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        color: "#58a6ff"
                                        selectByMouse: true
                                        onTextChanged: dialogRoot.targetDbPath = text
                                    }
                                }

                                Button {
                                    text: "Browse..."
                                    font.pixelSize: 11
                                    background: Rectangle {
                                        implicitHeight: 32
                                        implicitWidth: 80
                                        radius: 4
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend) {
                                            var defaultName = dialogRoot.selectedProject ? ("tfs_cache_" + dialogRoot.selectedProject.name + ".db") : "tfs_cache.db";
                                            var chosen = backend.browse_new_db_path(defaultName);
                                            if (chosen && chosen.trim() !== "") {
                                                dialogRoot.targetDbPath = chosen;
                                            }
                                        }
                                    }
                                }
                            }

                            // Start Sync checkbox
                            Row {
                                spacing: 8
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 3
                                    color: dialogRoot.startSyncAfterCreate ? "#238636" : "#161b22"
                                    border.color: dialogRoot.startSyncAfterCreate ? "#3fb950" : "#30363d"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        font.pixelSize: 10
                                        color: "#ffffff"
                                        visible: dialogRoot.startSyncAfterCreate
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: dialogRoot.startSyncAfterCreate = !dialogRoot.startSyncAfterCreate
                                    }
                                }

                                Text {
                                    text: "Start Full Synchronization immediately in the background"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#f0f6fc"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    Item { height: 8 }
                }
            }

            // Footer Actions
            Rectangle {
                Layout.fillWidth: true
                height: 56
                color: "#0d1117"
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    Button {
                        text: "Cancel"
                        font.pixelSize: 12
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 34
                            implicitWidth: 80
                            radius: 6
                            color: parent.hovered ? "#21262d" : "transparent"
                            border.color: "#30363d"
                        }
                        onClicked: dialogRoot.close()
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Create Database & Connect"
                        enabled: dialogRoot.selectedProject !== null && !dialogRoot.isConnecting
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.parent.enabled ? "#ffffff" : "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 34
                            implicitWidth: 200
                            radius: 6
                            color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#21262d"
                            border.color: parent.enabled ? "#3fb950" : "#30363d"
                        }
                        onClicked: {
                            if (!dialogRoot.selectedProject || !backend) return;
                            
                            var p = dialogRoot.selectedProject;
                            var res = backend.create_project_and_database(
                                dialogRoot.tfsUrl,
                                dialogRoot.tfsCollection,
                                dialogRoot.tfsPat,
                                p.id,
                                p.name,
                                dialogRoot.targetDbPath,
                                dialogRoot.startSyncAfterCreate,
                                dialogRoot.storePat
                            );

                            if (res && res.success) {
                                dialogRoot.projectCreated(p.name, res.db_path);
                                dialogRoot.close();
                            } else {
                                dialogRoot.connectionError = (res && res.error) ? res.error : "Failed to create project database";
                            }
                        }
                    }
                }
            }
        }
    }

    function getFilteredProjects() {
        if (!dialogRoot.projectList || dialogRoot.projectList.length === 0) {
            return [];
        }
        if (!dialogRoot.projectSearchKeyword || dialogRoot.projectSearchKeyword.trim() === "") {
            return dialogRoot.projectList;
        }
        var kw = dialogRoot.projectSearchKeyword.toLowerCase();
        var out = [];
        for (var i = 0; i < dialogRoot.projectList.length; ++i) {
            var item = dialogRoot.projectList[i];
            if ((item.name && item.name.toLowerCase().indexOf(kw) !== -1) ||
                (item.description && item.description.toLowerCase().indexOf(kw) !== -1)) {
                out.push(item);
            }
        }
        return out;
    }
}
