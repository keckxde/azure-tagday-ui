import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "components"
import "views"

ApplicationWindow {
    id: window
    width: Math.min(1420, Screen.desktopAvailableWidth ? Math.max(1200, Math.round(Screen.desktopAvailableWidth * 0.88)) : 1380)
    height: Math.min(980, Screen.desktopAvailableHeight ? Math.max(780, Math.round(Screen.desktopAvailableHeight * 0.90)) : 920)
    minimumWidth: 1024
    minimumHeight: 700
    visible: true
    title: "DevOps Manager"
    color: "#0d1117"

    Component.onCompleted: {
        if (Screen.desktopAvailableWidth && Screen.desktopAvailableHeight) {
            window.x = Math.max(0, Math.round((Screen.desktopAvailableWidth - window.width) / 2));
            window.y = Math.max(0, Math.round((Screen.desktopAvailableHeight - window.height) / 2));
        }
    }

    property int currentTabIndex: 0

    function navigateToTagDayRepo(repoName) {
        window.currentTabIndex = 5;
        if (reportsView) {
            reportsView.openTagDayRepo(repoName);
        }
    }

    function navigateToRepos(categoryFilter) {
        window.currentTabIndex = 1;
        if (reposView && categoryFilter) {
            reposView.selectedCategory = categoryFilter;
            reposView.currentPage = 1;
        }
    }

    function navigateToPullRequests(filterArg, isStatus) {
        window.currentTabIndex = 2;
        if (pullRequestsView) {
            if (isStatus) {
                pullRequestsView.filterByStatus(filterArg);
                pullRequestsView.filterByRepo("ALL");
            } else if (filterArg) {
                pullRequestsView.filterByRepo(filterArg);
                pullRequestsView.filterByStatus("ALL");
            } else {
                pullRequestsView.filterByRepo("ALL");
                pullRequestsView.filterByStatus("ALL");
            }
        }
    }

    function openPullRequestsPage() {
        navigateToPullRequests("", false);
    }

    function navigateToSprint(sprintName) {
        window.currentTabIndex = 5;
        if (reportsView && typeof reportsView.openSprintReport === "function") {
            reportsView.openSprintReport(sprintName);
        }
    }

    function navigateToWorkloadSprint(assignee, sprintName) {
        window.currentTabIndex = 4;
        if (workloadExplorerView) {
            if (assignee && assignee !== "Unassigned" && assignee !== "ALL") {
                workloadExplorerView.searchQuery = assignee;
            } else if (sprintName) {
                workloadExplorerView.searchQuery = sprintName;
            } else {
                workloadExplorerView.searchQuery = "";
            }
        }
    }

    function navigateToWorkItem(workItemId) {
        window.currentTabIndex = 3;
        if (workItemsView && typeof workItemsView.searchQuery !== "undefined") {
            workItemsView.searchQuery = "#" + workItemId;
        }
    }

    property bool isSyncLogDrawerOpen: false
    property real syncLogDrawerHeight: 380

    function toggleSyncLogDrawer() {
        window.isSyncLogDrawerOpen = !window.isSyncLogDrawerOpen;
    }

    function openMilestonesManager() {
        if (milestonesManagerDialog) {
            if (typeof milestonesManagerDialog.openDialog === "function") {
                milestonesManagerDialog.openDialog();
            } else if (typeof milestonesManagerDialog.open === "function") {
                milestonesManagerDialog.open();
            }
        }
    }

    // ==========================================
    // Scalable Root Container for Typography & High-DPI Zoom
    // ==========================================
    Item {
        id: rootScaleContainer
        anchors.left: parent.left
        anchors.top: parent.top
        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: (backend && backend.uiScale) ? backend.uiScale : 1.0
            yScale: (backend && backend.uiScale) ? backend.uiScale : 1.0
        }
        width: (backend && backend.uiScale && backend.uiScale !== 0) ? (window.width / backend.uiScale) : window.width
        height: (backend && backend.uiScale && backend.uiScale !== 0) ? (window.height / backend.uiScale) : window.height

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ==========================================
            // Sidebar Navigation
            // ==========================================
        Rectangle {
            Layout.preferredWidth: 240
            Layout.fillHeight: true
            color: "#161b22"
            border.color: "#30363d"
            border.width: 1
            clip: true
            z: 2

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                // App Brand
                Item {
                    Layout.fillWidth: true
                    height: 70

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        spacing: 12

                        Rectangle {
                            width: 38
                            height: 38
                            radius: 8
                            color: "#1f6feb"

                            Text {
                                anchors.centerIn: parent
                                text: "⚡"
                                font.pixelSize: 20
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: "DevOps Manager"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }

                            Text {
                                text: backend ? backend.projectName : "Unknown Project"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }
                    }
                }

                // Nav Links
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    NavItem {
                        iconText: "📊"
                        label: "Dashboard"
                        active: window.currentTabIndex === 0
                        onClicked: window.currentTabIndex = 0
                    }

                    NavItem {
                        iconText: "📦"
                        label: "Repositories"
                        active: window.currentTabIndex === 1
                        onClicked: window.currentTabIndex = 1
                    }

                    NavItem {
                        iconText: "🔀"
                        label: "Pull Requests"
                        active: window.currentTabIndex === 2
                        onClicked: window.currentTabIndex = 2
                    }

                    NavItem {
                        iconText: "📋"
                        label: "Work Items"
                        active: window.currentTabIndex === 3
                        onClicked: window.currentTabIndex = 3
                    }

                    NavItem {
                        iconText: "👥"
                        label: "Workload Explorer"
                        active: window.currentTabIndex === 4
                        onClicked: window.currentTabIndex = 4
                    }

                    NavItem {
                        iconText: "📈"
                        label: "Reports & Analytics"
                        active: window.currentTabIndex === 5
                        onClicked: window.currentTabIndex = 5
                    }

                    NavItem {
                        iconText: "⚙️"
                        label: "Settings"
                        active: window.currentTabIndex === 6
                        onClicked: window.currentTabIndex = 6
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                // ==========================================
                // Quick Font Size / Scaling Switcher
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 8
                    implicitHeight: 36
                    radius: 6
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 4

                        Text {
                            text: "🔤 Font:"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }

                        Item { Layout.fillWidth: true }

                        Repeater {
                            model: [
                                { label: "S", mode: "small", tip: "Small (90%) - Compact" },
                                { label: "M", mode: "medium", tip: "Medium (100%) - Default" },
                                { label: "L", mode: "large", tip: "Large (115%) - Enhanced" },
                                { label: "XL", mode: "xlarge", tip: "Extra Large (130%) - 4K/HiDPI" }
                            ]

                            Rectangle {
                                property bool isCur: backend && backend.fontSizeMode === modelData.mode
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: 4
                                color: isCur ? "#1f6feb" : (btnMa.containsMouse ? "#21262d" : "transparent")
                                border.color: isCur ? "#388bfd" : (btnMa.containsMouse ? "#30363d" : "transparent")

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    font.weight: parent.isCur ? Font.Bold : Font.Normal
                                    color: parent.isCur ? "#ffffff" : "#8b949e"
                                }

                                ToolTip.visible: btnMa.containsMouse
                                ToolTip.text: modelData.tip

                                MouseArea {
                                    id: btnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend) {
                                            backend.setFontSizeMode(modelData.mode);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ==========================================
                // Sidebar Sync Actions Panel
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 8
                    implicitHeight: syncControlsCol.implicitHeight + 20
                    color: "#0d1117"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: syncControlsCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Section Header with DB quick refresh
                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "DATA SYNC"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#8b949e"
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 22
                                height: 22
                                radius: 4
                                color: refreshMa.containsMouse ? "#21262d" : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "🔄"
                                    font.pixelSize: 11
                                    opacity: refreshMa.containsMouse ? 1.0 : 0.7
                                }
                                MouseArea {
                                    id: refreshMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend)
                                            backend.refresh_all_data();
                                    }
                                }
                                ToolTip.visible: refreshMa.containsMouse
                                ToolTip.text: "Reload local cache from disk"
                            }
                        }

                        // Primary: Sync All
                        Button {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            enabled: backend ? !backend.isBusy : false
                            font.weight: Font.DemiBold
                            contentItem: Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: backend && backend.isBusy ? "⏳" : "🔄"
                                    font.pixelSize: 12
                                }
                                Text {
                                    text: backend && backend.isBusy ? "Syncing..." : "Sync All"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: parent.parent.enabled ? "#ffffff" : "#8b949e"
                                }
                            }
                            background: Rectangle {
                                radius: 6
                                color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#21262d"
                                border.color: parent.enabled ? "#3fb950" : "#30363d"
                                border.width: 1
                            }
                            onClicked: {
                                if (backend)
                                    backend.sync_all_async();
                            }
                        }

                        // Secondary: Sync Work Items (WIQL)
                        Button {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            enabled: backend ? !backend.isBusy : false
                            font.weight: Font.DemiBold
                            contentItem: Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: backend && backend.isBusy ? "⏳" : "⚡"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: backend && backend.isBusy ? "Syncing WIQL..." : "Sync Work Items (WIQL)"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: parent.parent.enabled ? (parent.parent.hovered ? "#79c0ff" : "#58a6ff") : "#8b949e"
                                }
                            }
                            background: Rectangle {
                                radius: 6
                                color: parent.enabled ? (parent.hovered ? Qt.rgba(56 / 255, 139 / 255, 253 / 255, 0.15) : "#161b22") : "#161b22"
                                border.color: parent.enabled ? (parent.hovered ? "#58a6ff" : "#1f6feb") : "#30363d"
                                border.width: 1
                            }
                            onClicked: {
                                if (backend)
                                    backend.sync_work_items_async();
                            }
                        }

                        // Secondary: Sync Pull Requests
                        Button {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            enabled: backend ? !backend.isBusy : false
                            font.weight: Font.DemiBold
                            contentItem: Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: backend && backend.isBusy ? "⏳" : "🔀"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: backend && backend.isBusy ? "Syncing PRs..." : "Sync Pull Requests"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: parent.parent.enabled ? (parent.parent.hovered ? "#a371f7" : "#bc8cff") : "#8b949e"
                                }
                            }
                            background: Rectangle {
                                radius: 6
                                color: parent.enabled ? (parent.hovered ? Qt.rgba(163 / 255, 113 / 255, 247 / 255, 0.15) : "#161b22") : "#161b22"
                                border.color: parent.enabled ? (parent.hovered ? "#bc8cff" : "#8957e5") : "#30363d"
                                border.width: 1
                            }
                            onClicked: {
                                if (backend)
                                    backend.sync_pull_requests_async();
                            }
                        }

                        // Progress Bar & Abort Button (Visible during active sync / tasks)
                        Rectangle {
                            Layout.fillWidth: true
                            height: 18
                            visible: backend ? backend.isBusy : false
                            color: "#161b22"
                            radius: 4
                            border.color: "#30363d"
                            border.width: 1
                            clip: true

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * (Math.max(0, Math.min(100, backend ? backend.progress : 0)) / 100.0)
                                radius: 3
                                color: "#1f6feb"

                                Behavior on width {
                                    NumberAnimation { duration: 150 }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: (backend ? backend.progress : 0) + "%"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#ffffff"
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            visible: backend ? backend.isBusy : false
                            font.weight: Font.DemiBold
                            contentItem: Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "⏹️"
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: "Abort Sync"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#ff7b72"
                                }
                            }
                            background: Rectangle {
                                radius: 6
                                color: parent.hovered ? "#490202" : "#210909"
                                border.color: parent.hovered ? "#f85149" : "#da3633"
                                border.width: 1
                            }
                            onClicked: {
                                if (backend)
                                    backend.abort_sync();
                            }
                        }
                    }
                }

                // Bottom sync status indicator (Clickable to toggle Sync Log)
                Rectangle {
                    id: bottomStatusBar
                    Layout.fillWidth: true
                    height: 52
                    color: statusMa.containsMouse ? "#21262d" : "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: backend && backend.isBusy ? "#d29922" : "#3fb950"

                            SequentialAnimation on opacity {
                                running: backend && backend.isBusy
                                loops: Animation.Infinite
                                PropertyAnimation {
                                    to: 0.3
                                    duration: 600
                                }
                                PropertyAnimation {
                                    to: 1.0
                                    duration: 600
                                }
                            }
                        }

                        Text {
                            text: backend ? backend.statusMessage : "Ready"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: backend && backend.isBusy ? "#e3b341" : "#8b949e"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        // Log pill button
                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: logBtnText.implicitWidth + 10
                            radius: 3
                            color: window.isSyncLogDrawerOpen ? "#1f6feb" : (statusMa.containsMouse ? "#30363d" : "#161b22")
                            border.color: window.isSyncLogDrawerOpen ? "#58a6ff" : "#30363d"
                            border.width: 1

                            Text {
                                id: logBtnText
                                anchors.centerIn: parent
                                text: window.isSyncLogDrawerOpen ? "▼ Log" : "▲ Log"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: window.isSyncLogDrawerOpen ? "#ffffff" : "#c9d1d9"
                            }
                        }
                    }

                    MouseArea {
                        id: statusMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.toggleSyncLogDrawer()
                    }

                    ToolTip.visible: statusMa.containsMouse
                    ToolTip.text: "Click to " + (window.isSyncLogDrawerOpen ? "hide" : "show") + " Sync Log"
                }
            }
        }

        // ==========================================
        // Main Content Area Stack
        // ==========================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // View Stack
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: window.currentTabIndex

                    DashboardView {}
                    ReposView {
                        id: reposView
                    }
                    PullRequestsView {
                        id: pullRequestsView
                    }
                    WorkItemsView {
                        id: workItemsView
                    }
                    WorkloadExplorerView {
                        id: workloadExplorerView
                    }
                    ReportsView {
                        id: reportsView
                    }
                    SettingsView {}
                }

                // =========================================
                // Global Sync Log Drawer (available from every page)
                // =========================================
                Rectangle {
                    id: syncLogDrawer
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.isSyncLogDrawerOpen ? window.syncLogDrawerHeight : 0
                    Layout.minimumHeight: window.isSyncLogDrawerOpen ? 140 : 0
                    Layout.maximumHeight: window.isSyncLogDrawerOpen ? Math.round(window.height * 0.85) : 0
                    visible: window.isSyncLogDrawerOpen && Layout.preferredHeight > 0
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1
                    clip: true

                    Behavior on Layout.preferredHeight {
                        enabled: !dragHandleMa.pressed
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Drag-resize handle bar at the top of the drawer
                    Rectangle {
                        id: dragHandle
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 12
                        color: dragHandleMa.containsMouse ? "#21262d" : "#161b22"
                        border.color: dragHandleMa.containsMouse ? "#58a6ff" : "#30363d"
                        border.width: 1
                        z: 20

                        Row {
                            anchors.centerIn: parent
                            spacing: 3
                            Repeater {
                                model: 5
                                Rectangle {
                                    width: 8
                                    height: 3
                                    radius: 1.5
                                    color: dragHandleMa.containsMouse ? "#58a6ff" : "#8b949e"
                                }
                            }
                        }

                        property real _startGlobalY: 0
                        property real _startH: 0

                        MouseArea {
                            id: dragHandleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function(mouse) {
                                var pt = mapToItem(null, mouse.x, mouse.y);
                                dragHandle._startGlobalY = pt.y;
                                dragHandle._startH = window.syncLogDrawerHeight;
                            }
                            onPositionChanged: function(mouse) {
                                if (pressed) {
                                    var pt = mapToItem(null, mouse.x, mouse.y);
                                    var delta = dragHandle._startGlobalY - pt.y;
                                    var minH = 140;
                                    var maxH = Math.max(minH, Math.round(window.height * 0.85));
                                    var newH = Math.max(minH, Math.min(maxH, dragHandle._startH + delta));
                                    window.syncLogDrawerHeight = newH;
                                }
                            }
                        }
                    }

                    SyncLogView {
                        anchors.top: dragHandle.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        showHeaderTitle: true
                        headerTitleText: "Background Activity & Sync Log"
                        canClose: true
                        onCloseRequested: window.isSyncLogDrawerOpen = false
                        onHeightPresetRequested: function(h) {
                            window.syncLogDrawerHeight = Math.max(140, Math.min(Math.round(window.height * 0.85), h));
                        }
                    }
                }
            }

            // Non-intrusive Floating Background Task Pill (Top Right)
            // Note: parent Item is mouse-transparent so it cannot block sidebar clicks
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 16
                implicitHeight: 36
                implicitWidth: bgPillLayout.implicitWidth + 24
                radius: 6
                color: "#161b22"
                border.color: "#30363d"
                border.width: 1
                visible: backend && backend.isBusy
                z: 50
                // Only the pill itself is interactive; never block sidebar
                enabled: true

                RowLayout {
                    id: bgPillLayout
                    anchors.centerIn: parent
                    spacing: 8

                    BusyIndicator {
                        running: backend && backend.isBusy
                        implicitWidth: 16
                        implicitHeight: 16
                    }

                    Text {
                        text: backend ? backend.statusMessage : "Syncing in background..."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#e6edf3"
                    }

                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: pillLogBtnText.implicitWidth + 10
                        radius: 3
                        color: pillMa.containsMouse ? "#30363d" : "#21262d"
                        border.color: "#30363d"
                        border.width: 1

                        Text {
                            id: pillLogBtnText
                            anchors.centerIn: parent
                            text: "View Log ↗"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#58a6ff"
                        }

                        MouseArea {
                            id: pillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.isSyncLogDrawerOpen = true
                        }
                    }
                }
            }
        }
    }
}

    // ==========================================
    // Global Milestones Manager Modal Dialog
    // ==========================================
    MilestonesManagerDialog {
        id: milestonesManagerDialog
    }
}
