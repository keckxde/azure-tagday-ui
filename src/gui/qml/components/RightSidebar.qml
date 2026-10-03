import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: rightSidebarRoot

    // Public Properties
    property bool isOpen: false
    property string mode: "workload_member" // "workload_member", "workload_cell", "report_preview", "contributor_profile", "raw_file", "badge_detail", "badge_category"
    property string sidebarTitle: "Context Details"
    property string sidebarSubtitle: ""
    property var sidebarData: null
    property real preferredWidth: 440
    property real minWidth: 340
    property real maxWidth: 760

    // Workload Cell State
    property bool cellHideClosedTasks: false

    // Report View State
    property int reportViewMode: 0 // 0: Formatted Markdown, 1: Raw Text, 2: Data Table
    property var reportParsedTable: null
    property string reportRawText: ""
    property var reportMeta: null
    property string toastMessage: ""

    signal closeRequested()
    signal actionTriggered(string action, var params)

    function getFilteredCellContainers(containers, hideClosed) {
        if (!containers) return [];
        var res = [];
        for (var i = 0; i < containers.length; i++) {
            var c = containers[i];
            var openTasks = getFilteredCellTasks(c.tasks || [], hideClosed);
            if (hideClosed) {
                if (openTasks.length === 0 && c.is_done) continue;
            }
            res.push(c);
        }
        res.sort(function(a, b) {
            var aGrouped = a.is_grouped ? 1 : 0;
            var bGrouped = b.is_grouped ? 1 : 0;
            if (aGrouped !== bGrouped) return bGrouped - aGrouped;

            var aPrio = a.is_prio1 ? 1 : 0;
            var bPrio = b.is_prio1 ? 1 : 0;
            if (aPrio !== bPrio) return bPrio - aPrio;

            return (b.id || 0) - (a.id || 0);
        });
        return res;
    }

    function getFilteredCellTasks(tasksList, hideClosed) {
        if (!tasksList) return [];
        if (!hideClosed) return tasksList;
        var res = [];
        for (var i = 0; i < tasksList.length; i++) {
            if (!tasksList[i].is_done) {
                res.push(tasksList[i]);
            }
        }
        return res;
    }

    Layout.preferredWidth: isOpen ? preferredWidth : 0
    Layout.fillHeight: true
    visible: isOpen || Layout.preferredWidth > 0
    color: "#161b22"
    border.color: "#30363d"
    border.width: 1
    clip: true
    z: 10

    // Vertical drag-resize handle bar at the left edge of the sidebar
    Rectangle {
        id: dragHandle
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 6
        color: dragHandleMa.containsMouse ? Qt.rgba(88 / 255, 166 / 255, 255 / 255, 0.4) : "transparent"
        z: 30

        Rectangle {
            anchors.centerIn: parent
            width: 2
            height: 32
            radius: 1
            color: dragHandleMa.containsMouse ? "#58a6ff" : "#30363d"
        }

        property real _startGlobalX: 0
        property real _startW: 0

        MouseArea {
            id: dragHandleMa
            anchors.fill: parent
            anchors.leftMargin: -3
            anchors.rightMargin: -3
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            onPressed: function(mouse) {
                var pt = mapToItem(null, mouse.x, mouse.y);
                dragHandle._startGlobalX = pt.x;
                dragHandle._startW = rightSidebarRoot.preferredWidth;
            }
            onPositionChanged: function(mouse) {
                if (pressed) {
                    var pt = mapToItem(null, mouse.x, mouse.y);
                    var delta = dragHandle._startGlobalX - pt.x;
                    var minW = 280;
                    var maxW = Math.min(1200, Math.round((typeof window !== "undefined" && window.width) ? window.width * 0.8 : 1000));
                    var newW = Math.max(minW, Math.min(maxW, dragHandle._startW + delta));
                    rightSidebarRoot.preferredWidth = newW;
                    if (typeof window !== "undefined") {
                        window.rightSidebarWidth = newW;
                    }
                }
            }
            onReleased: function(mouse) {
                if (backend && typeof backend.setRightSidebarWidth === "function") {
                    backend.setRightSidebarWidth(Math.round(rightSidebarRoot.preferredWidth));
                }
            }
        }
    }

    Behavior on Layout.preferredWidth {
        enabled: !dragHandleMa.pressed
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    function showToast(msg) {
        toastMessage = msg;
        toastTimer.restart();
    }

    Timer {
        id: toastTimer
        interval: 2500
        onTriggered: rightSidebarRoot.toastMessage = ""
    }

    // React to data changes
    onSidebarDataChanged: {
        updateSidebarData();
    }

    onModeChanged: {
        updateSidebarData();
    }

    function updateSidebarData() {
        if (mode === "report_preview" || mode === "raw_file") {
            if (typeof sidebarData === "string") {
                if (backend) {
                    var res = backend.get_report_content(sidebarData);
                    reportMeta = res;
                    reportRawText = res.content || "";
                    if (res.format === "csv" || (res.file_name && res.file_name.endsWith(".csv"))) {
                        reportViewMode = 2;
                        reportParsedTable = backend.parse_csv_to_table(res.content || "");
                    } else {
                        reportViewMode = 0;
                    }
                }
            } else if (sidebarData && typeof sidebarData === "object") {
                reportMeta = sidebarData;
                reportRawText = sidebarData.content || "";
                if (sidebarData.format === "csv") {
                    reportViewMode = 2;
                    if (backend) {
                        reportParsedTable = backend.parse_csv_to_table(sidebarData.content || "");
                    }
                }
            }
        }
    }

    // ==========================================
    // Left Drag-Resize Handle
    // ==========================================
    Rectangle {
        id: leftDragBorder
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 6
        color: dragHandleMa.containsMouse || dragHandleMa.pressed ? "#58a6ff" : "transparent"
        z: 30

        MouseArea {
            id: dragHandleMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            property real startGlobalX: 0
            property real startWidth: 0

            onPressed: function(mouse) {
                var pt = mapToItem(null, mouse.x, mouse.y);
                startGlobalX = pt.x;
                startWidth = rightSidebarRoot.preferredWidth;
            }
            onPositionChanged: function(mouse) {
                if (pressed) {
                    var pt = mapToItem(null, mouse.x, mouse.y);
                    var delta = startGlobalX - pt.x; // Dragging left increases width
                    var newW = Math.max(rightSidebarRoot.minWidth, Math.min(rightSidebarRoot.maxWidth, startWidth + delta));
                    rightSidebarRoot.preferredWidth = newW;
                    if (typeof window !== "undefined" && typeof window.rightSidebarWidth !== "undefined") {
                        window.rightSidebarWidth = newW;
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        spacing: 0

        // ==========================================
        // Sidebar Top Header
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: "#0d1117"
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                // Mode Icon
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: {
                        if (rightSidebarRoot.mode === "workload_member" || rightSidebarRoot.mode === "workload_cell") return "#1f6feb";
                        if (rightSidebarRoot.mode === "contributor_profile") return "#a371f7";
                        if (rightSidebarRoot.mode === "badge_detail" || rightSidebarRoot.mode === "badge_category") return "#d29922";
                        return "#238636";
                    }
                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (rightSidebarRoot.mode === "workload_cell") return "📋";
                            if (rightSidebarRoot.mode === "workload_member") return "📊";
                            if (rightSidebarRoot.mode === "contributor_profile") return "👤";
                            if (rightSidebarRoot.mode === "badge_detail" || rightSidebarRoot.mode === "badge_category") return "🎖️";
                            return "📑";
                        }
                        font.pixelSize: 15
                    }
                }

                // Title & Subtitle
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: rightSidebarRoot.sidebarTitle
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: rightSidebarRoot.sidebarSubtitle || (rightSidebarRoot.mode === "workload_cell" ? "Sprint Workload Tasks" : (rightSidebarRoot.mode === "workload_member" ? "Team Member Workload" : (rightSidebarRoot.mode === "contributor_profile" ? "Contributor Gamification Profile" : (rightSidebarRoot.mode === "badge_detail" ? "Badge Requirements & Achievers" : "Report Preview"))))
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 10
                        color: "#8b949e"
                        elide: Text.ElideRight
                    }
                }

                // Width expander preset toggle
                Button {
                    implicitWidth: 28
                    implicitHeight: 28
                    font.pixelSize: 11
                    ToolTip.visible: hovered
                    ToolTip.text: rightSidebarRoot.preferredWidth > 500 ? "Collapse width (440px)" : "Expand width (640px)"
                    contentItem: Text {
                        text: rightSidebarRoot.preferredWidth > 500 ? "◀▶" : "↔"
                        font: parent.font
                        color: parent.hovered ? "#58a6ff" : "#8b949e"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6
                        color: parent.hovered ? "#21262d" : "transparent"
                    }
                    onClicked: {
                        var newW = rightSidebarRoot.preferredWidth > 500 ? 440 : 640;
                        rightSidebarRoot.preferredWidth = newW;
                        if (typeof window !== "undefined") {
                            window.rightSidebarWidth = newW;
                        }
                        if (backend && typeof backend.setRightSidebarWidth === "function") {
                            backend.setRightSidebarWidth(newW);
                        }
                    }
                }

                // Close Button
                Button {
                    implicitWidth: 28
                    implicitHeight: 28
                    font.pixelSize: 13
                    ToolTip.visible: hovered
                    ToolTip.text: "Close Sidebar (Esc)"
                    contentItem: Text {
                        text: "✖"
                        font: parent.font
                        color: parent.hovered ? "#ff7b72" : "#8b949e"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6
                        color: parent.hovered ? "#21262d" : "transparent"
                    }
                    onClicked: {
                        rightSidebarRoot.closeRequested();
                    }
                }
            }
        }

        // ==========================================
        // Toast Notification Bar
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            height: toastMessage ? 28 : 0
            visible: toastMessage !== ""
            color: "#1f6feb"
            clip: true

            Behavior on height {
                NumberAnimation { duration: 150 }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                    Layout.fillWidth: true
                    text: rightSidebarRoot.toastMessage
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                    elide: Text.ElideRight
                }
            }
        }

        // ==========================================
        // Main Dynamic Content Area
        // ==========================================
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: {
                if (rightSidebarRoot.mode === "workload_member") return 0;
                if (rightSidebarRoot.mode === "report_preview" || rightSidebarRoot.mode === "raw_file") return 1;
                if (rightSidebarRoot.mode === "contributor_profile") return 2;
                if (rightSidebarRoot.mode === "badge_detail" || rightSidebarRoot.mode === "badge_category") return 3;
                if (rightSidebarRoot.mode === "workload_cell") return 4;
                return 0;
            }

            // -------------------------------------------------------------
            // PANEL 0: Member Workload Explorer Panel
            // -------------------------------------------------------------
            ScrollView {
                id: memberWorkloadScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                clip: true

                ColumnLayout {
                    width: parent.width - 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14

                    Item { height: 4 } // top gap

                    // Member Avatar & Hero Stats Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: memberHeroCol.implicitHeight + 24
                        radius: 8
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: memberHeroCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Rectangle {
                                    width: 44
                                    height: 44
                                    radius: 22
                                    color: "#1f6feb"
                                    Text {
                                        anchors.centerIn: parent
                                        text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.initials) ? rightSidebarRoot.sidebarData.initials : "U"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.assignee) ? rightSidebarRoot.sidebarData.assignee : rightSidebarRoot.sidebarTitle
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        spacing: 6
                                        Text {
                                            text: (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.total_items || 0) : 0) + " total assigned items"
                                            font.pixelSize: 11
                                            color: "#8b949e"
                                        }

                                        Rectangle {
                                            visible: rightSidebarRoot.sidebarData && (rightSidebarRoot.sidebarData.overdue_items || 0) > 0
                                            implicitHeight: 16
                                            implicitWidth: wlOverdueLabel.implicitWidth + 8
                                            radius: 8
                                            color: "#3d0c0c"
                                            border.color: "#f85149"
                                            border.width: 1
                                            Text {
                                                id: wlOverdueLabel
                                                anchors.centerIn: parent
                                                text: "🚨 " + (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.overdue_items : 0) + " Overdue"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#ff7b72"
                                            }
                                        }
                                    }
                                }
                            }

                            // Completion Progress Bar
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Completion Rate"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.completion_rate || 0) : 0) + "%"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#3fb950"
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 6
                                    radius: 3
                                    color: "#21262d"

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width * Math.min(1.0, Math.max(0.0, (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.completion_rate || 0) : 0) / 100.0))
                                        radius: 3
                                        color: "#238636"
                                    }
                                }
                            }

                            // Quick Stats Grid
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Active
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 48
                                    radius: 6
                                    color: "#161b22"
                                    border.color: "#30363d"
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text { text: rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.active_items || 0).toString() : "0"; font.pixelSize: 14; font.weight: Font.Bold; color: "#58a6ff"; Layout.alignment: Qt.AlignHCenter }
                                        Text { text: "Active / WIP"; font.pixelSize: 9; color: "#8b949e"; Layout.alignment: Qt.AlignHCenter }
                                    }
                                }

                                // Closed
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 48
                                    radius: 6
                                    color: "#161b22"
                                    border.color: "#30363d"
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text { text: rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.closed_items || 0).toString() : "0"; font.pixelSize: 14; font.weight: Font.Bold; color: "#3fb950"; Layout.alignment: Qt.AlignHCenter }
                                        Text { text: "Completed"; font.pixelSize: 9; color: "#8b949e"; Layout.alignment: Qt.AlignHCenter }
                                    }
                                }

                                // New / Backlog
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 48
                                    radius: 6
                                    color: "#161b22"
                                    border.color: "#30363d"
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text { text: rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.new_items || 0).toString() : "0"; font.pixelSize: 14; font.weight: Font.Bold; color: "#d29922"; Layout.alignment: Qt.AlignHCenter }
                                        Text { text: "New / Backlog"; font.pixelSize: 9; color: "#8b949e"; Layout.alignment: Qt.AlignHCenter }
                                    }
                                }
                            }
                        }
                    }

                    // Sprint Distribution Section
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: sprintDistCol.implicitHeight + 20
                        radius: 8
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: sprintDistCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                text: "📅 Sprint Workload Distribution"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }

                            Repeater {
                                model: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.sprints) ? rightSidebarRoot.sidebarData.sprints : []
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: 28
                                    radius: 4
                                    color: sDistMa.containsMouse ? "#21262d" : "#161b22"
                                    border.color: modelData.overdue > 0 ? "#f85149" : "#30363d"

                                    MouseArea {
                                        id: sDistMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (typeof window !== "undefined" && typeof window.navigateToWorkloadSprint === "function") {
                                                window.navigateToWorkloadSprint(rightSidebarRoot.sidebarData.assignee, modelData.sprint);
                                            }
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        Text {
                                            text: modelData.sprint
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: "#58a6ff"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: "⚡ " + modelData.active + " act"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }

                                        Text {
                                            text: "✅ " + modelData.closed + " done"
                                            font.pixelSize: 10
                                            color: "#3fb950"
                                        }

                                        Rectangle {
                                            width: 22
                                            height: 16
                                            radius: 8
                                            color: "#30363d"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.total.toString()
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Assigned Work Items List Section
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: itemsListCol.implicitHeight + 20
                        radius: 8
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: itemsListCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "📋 Recent Assigned Work Items"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: ((rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.work_items) ? rightSidebarRoot.sidebarData.work_items.length : 0) + " items"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                }
                            }

                            Repeater {
                                model: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.work_items) ? rightSidebarRoot.sidebarData.work_items : []
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: wiCardCol.implicitHeight + 14
                                    radius: 6
                                    color: wiItemMa.containsMouse ? "#21262d" : "#161b22"
                                    border.color: modelData.urgency_status === "overdue" ? "#f85149" : "#30363d"
                                    border.width: modelData.urgency_status === "overdue" ? 1.5 : 1

                                    MouseArea {
                                        id: wiItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.tfs_url) {
                                                Qt.openUrlExternally(modelData.tfs_url);
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        id: wiCardCol
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            // Type icon
                                            Text {
                                                text: {
                                                    var t = (modelData.type || "").toLowerCase();
                                                    if (t.indexOf("bug") !== -1) return "🐛";
                                                    if (t.indexOf("story") !== -1 || t.indexOf("user story") !== -1) return "📖";
                                                    if (t.indexOf("feature") !== -1) return "⭐";
                                                    return "🛠️";
                                                }
                                                font.pixelSize: 11
                                            }

                                            Text {
                                                text: "#" + modelData.id
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: "#58a6ff"
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                color: "#f0f6fc"
                                                elide: Text.ElideRight
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Rectangle {
                                                implicitHeight: 16
                                                implicitWidth: wiStateText.implicitWidth + 8
                                                radius: 3
                                                color: {
                                                    var s = (modelData.state || "").toLowerCase();
                                                    if (s === "closed" || s === "done" || s === "resolved") return "#1b4728";
                                                    if (s === "active" || s === "in progress") return "#0d2344";
                                                    return "#21262d";
                                                }
                                                Text {
                                                    id: wiStateText
                                                    anchors.centerIn: parent
                                                    text: modelData.state
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    color: {
                                                        var s = (modelData.state || "").toLowerCase();
                                                        if (s === "closed" || s === "done" || s === "resolved") return "#3fb950";
                                                        if (s === "active" || s === "in progress") return "#58a6ff";
                                                        return "#8b949e";
                                                    }
                                                }
                                            }

                                            Text {
                                                text: modelData.sprint_week_name ? modelData.sprint_week_name : ""
                                                font.pixelSize: 10
                                                color: "#8b949e"
                                                visible: modelData.sprint_week_name !== ""
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Urgency badge if deadline set
                                            Rectangle {
                                                visible: modelData.urgency_badge && modelData.urgency_badge !== "—"
                                                implicitHeight: 16
                                                implicitWidth: wiUrgText.implicitWidth + 8
                                                radius: 3
                                                color: modelData.urgency_status === "overdue" ? "#3d0c0c" : "#161b22"
                                                border.color: modelData.urgency_color || "#30363d"
                                                border.width: 1
                                                Text {
                                                    id: wiUrgText
                                                    anchors.centerIn: parent
                                                    text: modelData.urgency_badge
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: modelData.urgency_color || "#8b949e"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { height: 12 } // bottom gap
                }
            }

            // -------------------------------------------------------------
            // PANEL 1: Reports Preview & Inspector Panel
            // -------------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Report Sub-Toolbar (Format switcher & action buttons)
                Rectangle {
                    Layout.fillWidth: true
                    height: 42
                    color: "#161b22"
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6

                        // View mode segmented buttons
                        Button {
                            implicitHeight: 26
                            implicitWidth: 80
                            checkable: true
                            checked: rightSidebarRoot.reportViewMode === 0
                            font.pixelSize: 10
                            font.weight: checked ? Font.Bold : Font.Normal
                            contentItem: Text {
                                text: "🎨 Preview"
                                font: parent.font
                                color: parent.checked ? "#ffffff" : "#8b949e"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 4
                                color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                                border.color: parent.checked ? "#388bfd" : "#30363d"
                            }
                            onClicked: rightSidebarRoot.reportViewMode = 0
                        }

                        Button {
                            implicitHeight: 26
                            implicitWidth: 65
                            checkable: true
                            checked: rightSidebarRoot.reportViewMode === 1
                            font.pixelSize: 10
                            font.weight: checked ? Font.Bold : Font.Normal
                            contentItem: Text {
                                text: "📝 Raw"
                                font: parent.font
                                color: parent.checked ? "#ffffff" : "#8b949e"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 4
                                color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                                border.color: parent.checked ? "#388bfd" : "#30363d"
                            }
                            onClicked: rightSidebarRoot.reportViewMode = 1
                        }

                        Button {
                            implicitHeight: 26
                            implicitWidth: 68
                            visible: rightSidebarRoot.reportParsedTable !== null || (rightSidebarRoot.reportMeta && rightSidebarRoot.reportMeta.format === "csv")
                            checkable: true
                            checked: rightSidebarRoot.reportViewMode === 2
                            font.pixelSize: 10
                            font.weight: checked ? Font.Bold : Font.Normal
                            contentItem: Text {
                                text: "📊 Table"
                                font: parent.font
                                color: parent.checked ? "#ffffff" : "#8b949e"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 4
                                color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                                border.color: parent.checked ? "#388bfd" : "#30363d"
                            }
                            onClicked: {
                                if (!rightSidebarRoot.reportParsedTable && backend) {
                                    rightSidebarRoot.reportParsedTable = backend.parse_csv_to_table(rightSidebarRoot.reportRawText);
                                }
                                rightSidebarRoot.reportViewMode = 2;
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Copy Content Button
                        Button {
                            implicitHeight: 26
                            implicitWidth: 70
                            font.pixelSize: 10
                            contentItem: Text {
                                text: "📋 Copy"
                                font: parent.font
                                color: "#f0f6fc"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 4
                                color: parent.hovered ? "#30363d" : "#21262d"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (backend && rightSidebarRoot.reportRawText) {
                                    backend.copy_to_clipboard(rightSidebarRoot.reportRawText);
                                    rightSidebarRoot.showToast("✅ Copied report content to clipboard!");
                                }
                            }
                        }

                        // Open in external editor button
                        Button {
                            implicitHeight: 26
                            implicitWidth: 70
                            visible: rightSidebarRoot.reportMeta && rightSidebarRoot.reportMeta.file_path && !rightSidebarRoot.reportMeta.file_path.startsWith("clipboard://")
                            font.pixelSize: 10
                            contentItem: Text {
                                text: "📂 Open"
                                font: parent.font
                                color: "#58a6ff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 4
                                color: parent.hovered ? "#30363d" : "#21262d"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (backend && rightSidebarRoot.reportMeta && rightSidebarRoot.reportMeta.file_path) {
                                    backend.open_external_file(rightSidebarRoot.reportMeta.file_path);
                                    rightSidebarRoot.showToast("📂 Opened file in system viewer.");
                                }
                            }
                        }
                    }
                }

                // File Metadata Banner
                Rectangle {
                    Layout.fillWidth: true
                    height: 24
                    color: "#0d1117"
                    visible: rightSidebarRoot.reportMeta !== null

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Text {
                            text: (rightSidebarRoot.reportMeta ? (rightSidebarRoot.reportMeta.file_name || "report") : "")
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#8b949e"
                        }

                        Text {
                            text: "• " + (rightSidebarRoot.reportMeta ? (rightSidebarRoot.reportMeta.line_count || 0) : 0) + " lines"
                            font.pixelSize: 10
                            color: "#8b949e"
                        }

                        Text {
                            text: "• " + (rightSidebarRoot.reportMeta ? (rightSidebarRoot.reportMeta.word_count || 0) : 0) + " words"
                            font.pixelSize: 10
                            color: "#8b949e"
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: rightSidebarRoot.reportMeta ? (rightSidebarRoot.reportMeta.modified_at || "") : ""
                            font.pixelSize: 10
                            color: "#6e7681"
                        }
                    }
                }

                // Report Content Body Switcher
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: rightSidebarRoot.reportViewMode

                    // 0: Formatted Markdown View
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        clip: true

                        TextArea {
                            width: parent.width - 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: rightSidebarRoot.reportRawText
                            textFormat: TextEdit.MarkdownText
                            wrapMode: TextEdit.WordWrap
                            readOnly: true
                            selectByMouse: true
                            color: "#e6edf3"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            background: Rectangle { color: "transparent" }
                        }
                    }

                    // 1: Raw Monospace Text View
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        TextArea {
                            text: rightSidebarRoot.reportRawText
                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.NoWrap
                            readOnly: true
                            selectByMouse: true
                            color: "#7ee787"
                            font.family: "Consolas, 'Cascadia Code', monospace"
                            font.pixelSize: 11
                            background: Rectangle { color: "#0d1117" }
                        }
                    }

                    // 2: CSV Data Table View
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ScrollView {
                            anchors.fill: parent
                            clip: true

                            ColumnLayout {
                                width: Math.max(parent.width, 600)
                                spacing: 1

                                // Table Header
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 28
                                    color: "#21262d"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        spacing: 8
                                        Repeater {
                                            model: (rightSidebarRoot.reportParsedTable && rightSidebarRoot.reportParsedTable.headers) ? rightSidebarRoot.reportParsedTable.headers : []
                                            Text {
                                                Layout.preferredWidth: 120
                                                text: modelData
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }

                                // Table Rows
                                Repeater {
                                    model: (rightSidebarRoot.reportParsedTable && rightSidebarRoot.reportParsedTable.rows) ? rightSidebarRoot.reportParsedTable.rows : []
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: 24
                                        color: index % 2 === 0 ? "#161b22" : "#0d1117"
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            spacing: 8
                                            Repeater {
                                                model: modelData
                                                Text {
                                                    Layout.preferredWidth: 120
                                                    text: modelData
                                                    font.pixelSize: 10
                                                    color: "#c9d1d9"
                                                    elide: Text.ElideRight
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

            // -------------------------------------------------------------
            // PANEL 2: Contributor Motivation Profile Panel
            // -------------------------------------------------------------
            ScrollView {
                id: contributorProfileScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                clip: true

                ColumnLayout {
                    width: parent.width - 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14

                    Item { height: 4 }

                    // Contributor Hero Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: contribHeroCol.implicitHeight + 24
                        radius: 8
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: contribHeroCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Rectangle {
                                    width: 48
                                    height: 48
                                    radius: 24
                                    color: "#a371f7"
                                    Text {
                                        anchors.centerIn: parent
                                        text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.initials) ? rightSidebarRoot.sidebarData.initials : "C"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.name) ? rightSidebarRoot.sidebarData.name : rightSidebarRoot.sidebarTitle
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        spacing: 6
                                        Rectangle {
                                            implicitHeight: 16
                                            implicitWidth: tierBadgeText.implicitWidth + 8
                                            radius: 8
                                            color: "#3d1f00"
                                            border.color: "#d29922"
                                            border.width: 1
                                            Text {
                                                id: tierBadgeText
                                                anchors.centerIn: parent
                                                text: (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.tier : "Pro") || "Pro"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#e3b341"
                                            }
                                        }

                                        Text {
                                            text: "XP: " + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.total_xp || rightSidebarRoot.sidebarData.score || 0) : 0)
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
                                        }
                                    }
                                }
                            }

                            // Work Rhythm Persona
                            Rectangle {
                                Layout.fillWidth: true
                                height: 32
                                radius: 6
                                color: "#161b22"
                                border.color: "#30363d"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 6
                                    Text { text: "⚡ Work Rhythm:"; font.pixelSize: 10; color: "#8b949e" }
                                    Text {
                                        text: rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.persona || "Balanced Achiever") : "Balanced Achiever"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#a371f7"
                                    }
                                }
                            }

                            // Send Kudos Interactive Button
                            Button {
                                Layout.fillWidth: true
                                implicitHeight: 32
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                contentItem: Text {
                                    text: "💖 Send Instant Kudos to " + (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.name : "Member")
                                    font: parent.font
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 6
                                    color: parent.hovered ? "#b34080" : "#9e256b"
                                }
                                onClicked: {
                                    rightSidebarRoot.showToast("💖 Kudos sent! Contributor notified.");
                                }
                            }
                        }
                    }

                    // Achievement Badges Section
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: badgesGridCol.implicitHeight + 20
                        radius: 8
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: badgesGridCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "🏆 Earned Badges & Medals"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: ((rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.badges) ? rightSidebarRoot.sidebarData.badges.length : 0) + " Badges"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                }
                            }

                            Repeater {
                                model: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.badges) ? rightSidebarRoot.sidebarData.badges : []
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: badgeItemRow.implicitHeight + 16
                                    radius: 6
                                    color: modelData.bg_color || "#161b22"
                                    border.color: modelData.color || "#30363d"
                                    border.width: 1

                                    RowLayout {
                                        id: badgeItemRow
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 10

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: modelData.bg_color || "#21262d"
                                            border.color: modelData.color || "#30363d"
                                            border.width: 1
                                            Layout.alignment: Qt.AlignTop

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.icon || "🏅"
                                                font.pixelSize: 16
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Text {
                                                    text: modelData.name || "Achievement"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    color: modelData.color || "#f0f6fc"
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                // Tier chip
                                                Rectangle {
                                                    visible: modelData.tier !== undefined
                                                    implicitHeight: 16
                                                    implicitWidth: sTierTxt.implicitWidth + 8
                                                    radius: 3
                                                    color: modelData.tier === "gold" ? "#2d2300" : (modelData.tier === "silver" ? "#21262d" : "#2a1e17")
                                                    border.color: modelData.color || "#30363d"
                                                    border.width: 1

                                                    Text {
                                                        id: sTierTxt
                                                        anchors.centerIn: parent
                                                        text: (modelData.tier_label || modelData.tier || "Badge").toUpperCase()
                                                        font.pixelSize: 8
                                                        font.weight: Font.Bold
                                                        color: modelData.color || "#8b949e"
                                                    }
                                                }

                                                Text {
                                                    text: "+" + (modelData.points || modelData.xp || 50) + " XP"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: modelData.color || "#e3b341"
                                                }
                                            }

                                            Text {
                                                text: modelData.description || "Completed milestone"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#8b949e"
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }
                            }

                            // Empty placeholder when 0 badges
                            Rectangle {
                                visible: !rightSidebarRoot.sidebarData || !rightSidebarRoot.sidebarData.badges || rightSidebarRoot.sidebarData.badges.length === 0
                                Layout.fillWidth: true
                                implicitHeight: 40
                                radius: 6
                                color: "#161b22"
                                border.color: "#21262d"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "No badges earned yet in this timeframe."
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    color: "#6e7681"
                                }
                            }
                        }
                    }

                    Item { height: 12 }
                }
            }

            // -------------------------------------------------------------
            // PANEL 3: Badge Details, Multi-Tier Requirements & Achievers Panel
            // -------------------------------------------------------------
            ScrollView {
                id: badgeDetailScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: badgeDetailScroll.width - 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Item { height: 6 }

                    // Badge Hero Header Banner
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: badgeHeroCol.implicitHeight + 24
                        radius: 8
                        color: "#0d1117"
                        border.color: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.color) ? rightSidebarRoot.sidebarData.color : "#d29922"
                        border.width: 1

                        ColumnLayout {
                            id: badgeHeroCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Rectangle {
                                    width: 48
                                    height: 48
                                    radius: 24
                                    color: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.bg_color) ? rightSidebarRoot.sidebarData.bg_color : "#2d2300"
                                    border.color: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.color) ? rightSidebarRoot.sidebarData.color : "#ffd700"
                                    border.width: 2

                                    Text {
                                        anchors.centerIn: parent
                                        text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.icon) ? rightSidebarRoot.sidebarData.icon : "🎖️"
                                        font.pixelSize: 22
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        text: rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.name : "Badge Details"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.color) ? rightSidebarRoot.sidebarData.color : "#f0f6fc"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    RowLayout {
                                        spacing: 6

                                        // Category Pill
                                        Rectangle {
                                            implicitHeight: 20
                                            implicitWidth: catTagTxt.implicitWidth + 10
                                            radius: 10
                                            color: "#1f242c"
                                            border.color: "#388bfd"
                                            border.width: 1

                                            Text {
                                                id: catTagTxt
                                                anchors.centerIn: parent
                                                text: (rightSidebarRoot.sidebarData && (rightSidebarRoot.sidebarData.category_name || rightSidebarRoot.sidebarData.category)) ? (rightSidebarRoot.sidebarData.category_name || rightSidebarRoot.sidebarData.category) : "Achievement"
                                                font.pixelSize: 9
                                                font.weight: Font.DemiBold
                                                color: "#79c0ff"
                                            }
                                        }

                                        // Total Achievers Pill
                                        Rectangle {
                                            implicitHeight: 20
                                            implicitWidth: achCountTagTxt.implicitWidth + 10
                                            radius: 10
                                            color: "#1a271e"
                                            border.color: "#3fb950"
                                            border.width: 1

                                            Text {
                                                id: achCountTagTxt
                                                anchors.centerIn: parent
                                                text: "👥 " + (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.achievers ? rightSidebarRoot.sidebarData.achievers.length : 0) + " Achievers"
                                                font.pixelSize: 9
                                                font.weight: Font.DemiBold
                                                color: "#3fb950"
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.description) ? rightSidebarRoot.sidebarData.description : ""
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Multi-Tier Level Progression Card (Bronze, Silver, Gold)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: tiersCol.implicitHeight + 20
                        radius: 8
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: tiersCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "🎖️ Tier Difficulty & Requirements"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Escalating Thresholds"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                }
                            }

                            // Bronze Tier Card
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: bronzeRow.implicitHeight + 16
                                radius: 6
                                color: "#1c1510"
                                border.color: "#cd7f32"
                                border.width: 1

                                RowLayout {
                                    id: bronzeRow
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: "#2a1e17"
                                        border.color: "#cd7f32"
                                        Text { anchors.centerIn: parent; text: "🥉"; font.pixelSize: 13 }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            Text {
                                                text: "BRONZE LEVEL"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#cd7f32"
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: "+" + ((rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.tiers && rightSidebarRoot.sidebarData.tiers.bronze) ? rightSidebarRoot.sidebarData.tiers.bronze.points : 50) + " pts"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#cd7f32"
                                            }
                                        }
                                        Text {
                                            text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.tiers && rightSidebarRoot.sidebarData.tiers.bronze) ? rightSidebarRoot.sidebarData.tiers.bronze.criteria : "Meet standard threshold"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#c9d1d9"
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            // Silver Tier Card
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: silverRow.implicitHeight + 16
                                radius: 6
                                color: "#161b22"
                                border.color: "#c0c0c0"
                                border.width: 1

                                RowLayout {
                                    id: silverRow
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: "#21262d"
                                        border.color: "#c0c0c0"
                                        Text { anchors.centerIn: parent; text: "🥈"; font.pixelSize: 13 }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            Text {
                                                text: "SILVER LEVEL (HARDER)"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#e6edf3"
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: "+" + ((rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.tiers && rightSidebarRoot.sidebarData.tiers.silver) ? rightSidebarRoot.sidebarData.tiers.silver.points : 100) + " pts"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#e6edf3"
                                            }
                                        }
                                        Text {
                                            text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.tiers && rightSidebarRoot.sidebarData.tiers.silver) ? rightSidebarRoot.sidebarData.tiers.silver.criteria : "Higher threshold"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#c9d1d9"
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            // Gold Tier Card
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: goldRow.implicitHeight + 16
                                radius: 6
                                color: "#241c08"
                                border.color: "#ffd700"
                                border.width: 1.5

                                RowLayout {
                                    id: goldRow
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: "#2d2300"
                                        border.color: "#ffd700"
                                        Text { anchors.centerIn: parent; text: "🥇"; font.pixelSize: 13 }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            Text {
                                                text: "GOLD LEVEL (ELITE MASTER)"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#ffd700"
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: "+" + ((rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.tiers && rightSidebarRoot.sidebarData.tiers.gold) ? rightSidebarRoot.sidebarData.tiers.gold.points : 200) + " pts"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#ffd700"
                                            }
                                        }
                                        Text {
                                            text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.tiers && rightSidebarRoot.sidebarData.tiers.gold) ? rightSidebarRoot.sidebarData.tiers.gold.criteria : "Top master threshold"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#c9d1d9"
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Achievers Section Header
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "👥 Achieved by Team Members"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.achievers ? rightSidebarRoot.sidebarData.achievers.length : 0) + " Unlocked"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#58a6ff"
                        }
                    }

                    // Achievers List Repeater
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.achievers) ? rightSidebarRoot.sidebarData.achievers : []

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 58
                                radius: 6
                                color: achMa.containsMouse ? "#1f242c" : "#0d1117"
                                border.color: modelData.color || "#30363d"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    // Achiever Avatar Circle
                                    Rectangle {
                                        width: 38
                                        height: 38
                                        radius: 19
                                        color: "#1f6feb"

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.initials || "??"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            color: "#ffffff"
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: modelData.name || "Member"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                                elide: Text.ElideRight
                                            }

                                            // Tier Badge Chip (Gold, Silver, Bronze)
                                            Rectangle {
                                                implicitHeight: 18
                                                implicitWidth: achTierTxt.implicitWidth + 10
                                                radius: 9
                                                color: modelData.tier === "gold" ? "#2d2300" : (modelData.tier === "silver" ? "#21262d" : "#2a1e17")
                                                border.color: modelData.color || "#ffd700"
                                                border.width: 1

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 3
                                                    Text {
                                                        text: modelData.tier_icon || (modelData.tier === "gold" ? "🥇" : (modelData.tier === "silver" ? "🥈" : "🥉"))
                                                        font.pixelSize: 9
                                                    }
                                                    Text {
                                                        id: achTierTxt
                                                        text: (modelData.tier_label || modelData.tier || "Bronze").toUpperCase()
                                                        font.pixelSize: 8
                                                        font.weight: Font.Bold
                                                        color: modelData.color || "#ffd700"
                                                    }
                                                }
                                            }

                                            Item { Layout.fillWidth: true }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Text {
                                                text: "📊 " + (modelData.metric_label || "Achieved:") + " "
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#8b949e"
                                            }
                                            Text {
                                                text: String(modelData.times_achieved !== undefined ? modelData.times_achieved : 1)
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: "#58a6ff"
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: modelData.score ? (modelData.score + " pts total") : ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#7ee787"
                                            }
                                        }
                                    }

                                    // View Member Profile Arrow Button
                                    Rectangle {
                                        width: 26
                                        height: 26
                                        radius: 13
                                        color: profBtnMa.containsMouse ? "#30363d" : "#161b22"
                                        border.color: "#30363d"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "👤"
                                            font.pixelSize: 11
                                        }

                                        ToolTip.visible: profBtnMa.containsMouse
                                        ToolTip.text: "View " + modelData.name + "'s Profile"
                                        ToolTip.delay: 200

                                        MouseArea {
                                            id: profBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var memObj = null;
                                                if (backend && backend.teamMotivationData && backend.teamMotivationData.members) {
                                                    var ml = backend.teamMotivationData.members;
                                                    for (var i = 0; i < ml.length; i++) {
                                                        if (ml[i].name === modelData.name) {
                                                            memObj = ml[i];
                                                            break;
                                                        }
                                                    }
                                                }
                                                if (!memObj) {
                                                    memObj = {
                                                        name: modelData.name,
                                                        initials: modelData.initials || "??",
                                                        score: modelData.score || 0
                                                    };
                                                }
                                                if (typeof window !== "undefined" && typeof window.openRightSidebar === "function") {
                                                    window.openRightSidebar("contributor_profile", memObj.name, "Contributor & Gamification Profile", memObj);
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: achMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var memObj = null;
                                        if (backend && backend.teamMotivationData && backend.teamMotivationData.members) {
                                            var ml = backend.teamMotivationData.members;
                                            for (var i = 0; i < ml.length; i++) {
                                                if (ml[i].name === modelData.name) {
                                                    memObj = ml[i];
                                                    break;
                                                }
                                            }
                                        }
                                        if (!memObj) {
                                            memObj = {
                                                name: modelData.name,
                                                initials: modelData.initials || "??",
                                                score: modelData.score || 0
                                            };
                                        }
                                        if (typeof window !== "undefined" && typeof window.openRightSidebar === "function") {
                                            window.openRightSidebar("contributor_profile", memObj.name, "Contributor & Gamification Profile", memObj);
                                        }
                                    }
                                }
                            }
                        }

                        // Empty State if no achievers yet
                        Rectangle {
                            visible: !rightSidebarRoot.sidebarData || !rightSidebarRoot.sidebarData.achievers || rightSidebarRoot.sidebarData.achievers.length === 0
                            Layout.fillWidth: true
                            implicitHeight: 90
                            radius: 6
                            color: "#0d1117"
                            border.color: "#21262d"
                            border.width: 1

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "🎯 No Achievers Yet in This Timeframe"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Complete Bronze criteria to be the first champion!"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    color: "#6e7681"
                                }
                            }
                        }
                    }

                    Item { height: 16 }
                }
            }

            // -------------------------------------------------------------
            // PANEL 4: Sprint Cell Workload Tasks Drilldown Panel
            // -------------------------------------------------------------
            ScrollView {
                id: cellWorkloadScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                clip: true

                ColumnLayout {
                    width: parent.width - 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Item { height: 4 } // top gap

                    // Cell & Sprint Hero Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: cellHeroCol.implicitHeight + 24
                        radius: 8
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: cellHeroCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Rectangle {
                                    width: 44
                                    height: 44
                                    radius: 22
                                    color: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.assignee === "Unassigned") ? "#30363d" : "#1f6feb"
                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            if (!rightSidebarRoot.sidebarData || !rightSidebarRoot.sidebarData.assignee) return "U";
                                            var parts = rightSidebarRoot.sidebarData.assignee.trim().split(" ");
                                            if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
                                            return rightSidebarRoot.sidebarData.assignee.substring(0, 2).toUpperCase();
                                        }
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.assignee || "Team Member") : "Team Member"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        spacing: 8
                                        Text {
                                            text: "Sprint: " + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.sprint_name || "") : "")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: "#58a6ff"
                                        }

                                        Rectangle {
                                            implicitHeight: 18
                                            implicitWidth: cellTotalBadgeText.implicitWidth + 10
                                            radius: 9
                                            color: "#21262d"
                                            border.color: "#30363d"
                                            Text {
                                                id: cellTotalBadgeText
                                                anchors.centerIn: parent
                                                text: (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.total_count || 0) : 0) + " items"
                                                font.pixelSize: 9
                                                font.weight: Font.DemiBold
                                                color: "#c9d1d9"
                                            }
                                        }
                                    }
                                }
                            }

                            // Task status summary row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: rightSidebarRoot.sidebarData && (rightSidebarRoot.sidebarData.tasks_count || 0) > 0

                                Text {
                                    text: "🛠️ " + (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.tasks_count : 0) + " tasks:"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                }
                                Text {
                                    text: "⏳ " + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_not_started_count || 0) : 0) + " Not Started"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                }
                                Text {
                                    text: "⚡ " + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_active_count || 0) : 0) + " Active"
                                    font.pixelSize: 10
                                    color: "#58a6ff"
                                }
                                Text {
                                    text: "✅ " + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_closed_percent !== undefined ? rightSidebarRoot.sidebarData.tasks_closed_percent : Math.round(((rightSidebarRoot.sidebarData.tasks_closed_count || 0) / Math.max(1, rightSidebarRoot.sidebarData.tasks_count || 1)) * 100)) : 0) + "% Closed (" + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_closed_count || 0) : 0) + "/" + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_count || 0) : 0) + ")"
                                    font.pixelSize: 10
                                    color: "#3fb950"
                                }
                            }

                            // 3-Segment Tasks Progress Bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: "#21262d"
                                clip: true
                                visible: rightSidebarRoot.sidebarData && (rightSidebarRoot.sidebarData.tasks_count || 0) > 0

                                Row {
                                    anchors.fill: parent
                                    spacing: 0

                                    Rectangle {
                                        width: parent.width * ((rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_closed_count || 0) : 0) / Math.max(1, (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_count || 1) : 1)))
                                        height: parent.height
                                        color: "#3fb950"
                                    }

                                    Rectangle {
                                        width: parent.width * ((rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_active_count || 0) : 0) / Math.max(1, (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_count || 1) : 1)))
                                        height: parent.height
                                        color: "#1f6feb"
                                    }

                                    Rectangle {
                                        width: parent.width * ((rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_not_started_count || 0) : 0) / Math.max(1, (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.tasks_count || 1) : 1)))
                                        height: parent.height
                                        color: "#30363d"
                                    }
                                }
                            }
                        }
                    }

                    // Filter Bar
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Filter:"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }

                            // Show All Button
                            Rectangle {
                                implicitHeight: 22
                                implicitWidth: cellShowAllText.implicitWidth + 14
                                radius: 11
                                color: !rightSidebarRoot.cellHideClosedTasks ? "#1f6feb" : "#21262d"
                                border.color: !rightSidebarRoot.cellHideClosedTasks ? "#388bfd" : "#30363d"
                                Text {
                                    id: cellShowAllText
                                    anchors.centerIn: parent
                                    text: "Show All (" + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.total_count || 0) : 0) + ")"
                                    font.pixelSize: 10
                                    font.weight: !rightSidebarRoot.cellHideClosedTasks ? Font.Bold : Font.Normal
                                    color: !rightSidebarRoot.cellHideClosedTasks ? "#ffffff" : "#8b949e"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { rightSidebarRoot.cellHideClosedTasks = false; }
                                }
                            }

                            // Hide Closed Button
                            Rectangle {
                                implicitHeight: 22
                                implicitWidth: cellHideClosedRow.implicitWidth + 14
                                radius: 11
                                color: rightSidebarRoot.cellHideClosedTasks ? "#238636" : "#21262d"
                                border.color: rightSidebarRoot.cellHideClosedTasks ? "#3fb950" : "#30363d"
                                RowLayout {
                                    id: cellHideClosedRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "⚡"
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        text: "Hide Closed (" + (rightSidebarRoot.sidebarData ? ((rightSidebarRoot.sidebarData.total_count || 0) - (rightSidebarRoot.sidebarData.completed_count || 0)) : 0) + " open)"
                                        font.pixelSize: 10
                                        font.weight: rightSidebarRoot.cellHideClosedTasks ? Font.Bold : Font.Normal
                                        color: rightSidebarRoot.cellHideClosedTasks ? "#ffffff" : "#8b949e"
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { rightSidebarRoot.cellHideClosedTasks = true; }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                visible: rightSidebarRoot.cellHideClosedTasks && rightSidebarRoot.sidebarData && (rightSidebarRoot.sidebarData.completed_count || 0) > 0
                                text: "✓ " + (rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.completed_count || 0) : 0) + " closed hidden"
                                font.pixelSize: 10
                                color: "#3fb950"
                            }
                        }
                    }

                    // Grouped Parent Container Cards Repeater
                    Repeater {
                        model: rightSidebarRoot.getFilteredCellContainers(rightSidebarRoot.sidebarData ? (rightSidebarRoot.sidebarData.grouped_containers || rightSidebarRoot.sidebarData.items || []) : [], rightSidebarRoot.cellHideClosedTasks)

                        delegate: Rectangle {
                            id: cellCardDelegate
                            Layout.fillWidth: true
                            implicitHeight: cellContainerCol.implicitHeight + 18
                            radius: 8
                            color: "#0d1117"
                            border.color: {
                                if (modelData.urgency_status === "overdue") return "#f85149";
                                if (cellCardDelegateMa.containsMouse) return "#388bfd";
                                return "#30363d";
                            }
                            border.width: 1

                            MouseArea {
                                id: cellCardDelegateMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            ColumnLayout {
                                id: cellContainerCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                // Parent Item Header Box
                                Rectangle {
                                    id: cellParentHeaderBox
                                    Layout.fillWidth: true
                                    implicitHeight: cellParentHeaderCol.implicitHeight + 16
                                    radius: 6
                                    color: cellCardDelegateMa.containsMouse ? "#1c2128" : "#161b22"
                                    border.color: {
                                        if (modelData.is_prio1) return "#d29922";
                                        if (modelData.urgency_status === "overdue") return "#f85149";
                                        if (modelData.is_done) return "#238636";
                                        return "#30363d";
                                    }
                                    border.width: modelData.is_prio1 || modelData.urgency_status === "overdue" ? 1.5 : 1

                                    // Left Accent Indicator Strip
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 4
                                        radius: 2
                                        color: {
                                            if (modelData.urgency_status === "overdue") return "#f85149";
                                            if (modelData.is_prio1) return "#d29922";
                                            if (modelData.is_done) return "#3fb950";
                                            var t = (modelData.type || "").toLowerCase();
                                            if (t.indexOf("bug") !== -1 || t.indexOf("defect") !== -1) return "#f85149";
                                            if (t.indexOf("feature") !== -1 || t.indexOf("epic") !== -1) return "#a371f7";
                                            if (t.indexOf("standalone") !== -1 || modelData.id === 0) return "#8b949e";
                                            return "#58a6ff";
                                        }
                                    }

                                    ColumnLayout {
                                        id: cellParentHeaderCol
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 8
                                        anchors.bottomMargin: 8
                                        spacing: 8

                                        // Top Line: Icon, #ID, Title, Prio 1 & State Badges
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                text: {
                                                    var t = (modelData.type || "").toLowerCase();
                                                    if (t.indexOf("bug") !== -1 || t.indexOf("defect") !== -1) return "🐛";
                                                    if (t.indexOf("feature") !== -1) return "🎯";
                                                    if (t.indexOf("epic") !== -1) return "👑";
                                                    if (t.indexOf("req") !== -1) return "📋";
                                                    if (t.indexOf("standalone") !== -1 || modelData.id === 0) return "🛠️";
                                                    return "📘";
                                                }
                                                font.pixelSize: 16
                                                Layout.alignment: Qt.AlignTop
                                            }

                                            // #ID Badge / Link (Opens TFS Editor)
                                            Rectangle {
                                                visible: modelData.id > 0
                                                implicitHeight: 22
                                                implicitWidth: cellCIdText.implicitWidth + 10
                                                radius: 4
                                                color: cellCIdMa.containsMouse ? "#1f6feb" : "#21262d"
                                                border.color: cellCIdMa.containsMouse ? "#58a6ff" : "#30363d"
                                                border.width: 1
                                                Layout.alignment: Qt.AlignTop

                                                Text {
                                                    id: cellCIdText
                                                    anchors.centerIn: parent
                                                    text: "#" + modelData.id
                                                    font.family: "Consolas, monospace"
                                                    font.pixelSize: 12
                                                    font.weight: Font.Bold
                                                    color: cellCIdMa.containsMouse ? "#ffffff" : "#58a6ff"
                                                }

                                                ToolTip.visible: cellCIdMa.containsMouse
                                                ToolTip.text: "Click to open Work Item Editor in TFS (#" + modelData.id + ")"

                                                MouseArea {
                                                    id: cellCIdMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (backend && modelData.id > 0) {
                                                            backend.open_work_item_in_browser(modelData.id);
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                visible: modelData.id === 0
                                                text: "Direct"
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: "#8b949e"
                                                Layout.alignment: Qt.AlignTop
                                            }

                                            // Parent Title
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title || (modelData.id > 0 ? ("Work Item #" + modelData.id) : "Direct Tasks / Standalone Items")
                                                font.family: "Segoe UI, -apple-system, BlinkMacSystemFont, sans-serif"
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                                color: cellCardTitleMa.containsMouse ? "#58a6ff" : "#ffffff"
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.2
                                                Layout.alignment: Qt.AlignVCenter

                                                ToolTip.visible: cellCardTitleMa.containsMouse
                                                ToolTip.text: (modelData.title || "") + "\n• Left-Click: Open Sprint Taskboard in TFS\n• Click #" + (modelData.id > 0 ? modelData.id : "ID") + ": Open Work Item Editor"

                                                MouseArea {
                                                    id: cellCardTitleMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.sprint_week_name || modelData.iteration_name || modelData.iteration_path || "";
                                                        if (backend) {
                                                            backend.open_sprint_in_browser(modelData.id || sName, sName);
                                                        }
                                                    }
                                                }
                                            }

                                            // Prio 1 Badge
                                            Rectangle {
                                                visible: !!modelData.is_prio1
                                                implicitHeight: 22
                                                implicitWidth: cellCPrioText.implicitWidth + 12
                                                radius: 4
                                                color: "#3d2800"
                                                border.color: "#d29922"
                                                border.width: 1
                                                Layout.alignment: Qt.AlignTop
                                                Text {
                                                    id: cellCPrioText
                                                    anchors.centerIn: parent
                                                    text: modelData.prio_badge || "⭐ Prio 1"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: "#f0883e"
                                                }
                                            }

                                            // State badge
                                            Rectangle {
                                                visible: modelData.id > 0
                                                implicitHeight: 22
                                                implicitWidth: cellCStateLabel.implicitWidth + 12
                                                radius: 11
                                                color: modelData.is_done ? "#0d3525" : (modelData.state === "Proposed" ? "#2d2006" : "#21262d")
                                                border.color: modelData.is_done ? "#3fb950" : (modelData.state === "Proposed" ? "#d29922" : "#30363d")
                                                Layout.alignment: Qt.AlignTop
                                                Text {
                                                    id: cellCStateLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.state || "Active"
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                    color: modelData.is_done ? "#3fb950" : (modelData.state === "Proposed" ? "#d29922" : "#58a6ff")
                                                }
                                            }
                                        }

                                        // Badges & Actions Chips Flow
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            // Type badge
                                            Rectangle {
                                                implicitHeight: 20
                                                implicitWidth: cellCTypeLabel.implicitWidth + 10
                                                radius: 10
                                                color: "#21262d"
                                                border.color: "#30363d"
                                                Text {
                                                    id: cellCTypeLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.type || "Story"
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                    color: "#c9d1d9"
                                                }
                                            }

                                            // External Parent
                                            Rectangle {
                                                visible: !!modelData.is_external_parent
                                                implicitHeight: 20
                                                implicitWidth: cellCExtLabel.implicitWidth + 10
                                                radius: 10
                                                color: "#16243b"
                                                border.color: "#1f6feb"
                                                Text {
                                                    id: cellCExtLabel
                                                    anchors.centerIn: parent
                                                    text: "🌐 External Parent"
                                                    font.pixelSize: 9
                                                    color: "#58a6ff"
                                                }
                                            }

                                            // Assignee Pill
                                            Rectangle {
                                                implicitHeight: 20
                                                implicitWidth: cellCOwnerText.implicitWidth + 12
                                                radius: 10
                                                color: "#21262d"
                                                border.color: "#30363d"
                                                Text {
                                                    id: cellCOwnerText
                                                    anchors.centerIn: parent
                                                    text: "👤 " + (modelData.assigned_to || "Unassigned")
                                                    font.pixelSize: 10
                                                    color: "#c9d1d9"
                                                }
                                            }

                                            // Iteration / Reschedule Pill
                                            Rectangle {
                                                visible: modelData.id > 0
                                                implicitHeight: 20
                                                implicitWidth: cellCSprintRow.implicitWidth + 10
                                                radius: 10
                                                color: "#21262d"
                                                border.color: cellCEditSprintMa.containsMouse ? "#58a6ff" : "#30363d"
                                                border.width: 1

                                                RowLayout {
                                                    id: cellCSprintRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    Text { text: "🔄"; font.pixelSize: 9 }
                                                    Text {
                                                        text: modelData.iteration_path ? modelData.iteration_path.split("\\").pop() : (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "Sprint")
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                        color: "#58a6ff"
                                                    }
                                                }
                                                ToolTip.visible: cellCEditSprintMa.containsMouse
                                                ToolTip.text: "Planned Iteration: " + (modelData.iteration_path || "Sprint") + "\n(Click to reschedule)"

                                                MouseArea {
                                                    id: cellCEditSprintMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        sidebarIterationPickerModal.openForWorkItem(
                                                            modelData.id,
                                                            modelData.title,
                                                            modelData.iteration_path || (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "")
                                                        );
                                                    }
                                                }
                                            }

                                            // Deadline Pill
                                            Rectangle {
                                                visible: modelData.id > 0
                                                implicitHeight: 20
                                                implicitWidth: cellCDdRow.implicitWidth + 10
                                                radius: 10
                                                property bool hasDate: (modelData.deadline_str || "") !== ""
                                                color: Qt.rgba((modelData.urgency_color ? modelData.urgency_color.r : 0.5), (modelData.urgency_color ? modelData.urgency_color.g : 0.5), (modelData.urgency_color ? modelData.urgency_color.b : 0.5), 0.15)
                                                border.color: cellCEditDlMa.containsMouse ? "#58a6ff" : Qt.rgba((modelData.urgency_color ? modelData.urgency_color.r : 0.5), (modelData.urgency_color ? modelData.urgency_color.g : 0.5), (modelData.urgency_color ? modelData.urgency_color.b : 0.5), 0.5)
                                                border.width: 1

                                                RowLayout {
                                                    id: cellCDdRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    Text {
                                                        text: parent.hasDate ? (modelData.urgency_badge || modelData.deadline_str) : "➕ Set Date"
                                                        font.pixelSize: 9
                                                        font.weight: Font.DemiBold
                                                        color: modelData.urgency_color || "#8b949e"
                                                    }
                                                }
                                                ToolTip.visible: cellCEditDlMa.containsMouse
                                                ToolTip.text: "Deadline: " + (modelData.deadline_str || "None") + "\n(Click to edit)"

                                                MouseArea {
                                                    id: cellCEditDlMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        sidebarDeadlineDialog.openForWorkItem(
                                                            modelData.id,
                                                            modelData.title,
                                                            modelData.deadline_str,
                                                            rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : ""
                                                        );
                                                    }
                                                }
                                            }

                                            // Milestone Pill
                                            Rectangle {
                                                visible: (modelData.milestone_name || "") !== ""
                                                implicitHeight: 20
                                                implicitWidth: cellCMStoneRow.implicitWidth + 10
                                                radius: 10
                                                color: modelData.milestone_bg || "#16243b"
                                                border.color: modelData.milestone_color || "#1f6feb"
                                                border.width: 1

                                                RowLayout {
                                                    id: cellCMStoneRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    Text {
                                                        text: modelData.milestone_icon || "🚩"
                                                        font.pixelSize: 9
                                                    }
                                                    Text {
                                                        text: modelData.milestone_name
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        color: modelData.milestone_color || "#79c0ff"
                                                    }
                                                }
                                                ToolTip.visible: cellCMStoneMa.containsMouse
                                                ToolTip.text: "Major Milestone: " + (modelData.milestone_name || "") + " (" + (modelData.milestone_category || "") + ")"
                                                MouseArea {
                                                    id: cellCMStoneMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (typeof window !== "undefined" && window.openMilestonesManager) {
                                                            window.openMilestonesManager();
                                                        }
                                                    }
                                                }
                                            }

                                            // PBS Chip
                                            Rectangle {
                                                visible: (modelData.level1_display || "") !== "" && modelData.level1_display !== "Ungrouped Sub-System"
                                                implicitHeight: 20
                                                implicitWidth: cellCHierarchyText.implicitWidth + 10
                                                radius: 4
                                                color: "#21262d"
                                                border.color: modelData.is_grouped ? "#30363d" : "#da3633"
                                                border.width: 1
                                                Text {
                                                    id: cellCHierarchyText
                                                    anchors.centerIn: parent
                                                    text: "🏷️ " + (modelData.level1_display || "") + ((modelData.level2_display && modelData.level2_display !== "Ungrouped Component") ? (" › " + modelData.level2_display) : "")
                                                    font.pixelSize: 9
                                                    color: modelData.is_grouped ? "#8b949e" : "#f85149"
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            // Ungrouped Warning Chip
                                            Rectangle {
                                                visible: modelData.id > 0 && !modelData.is_grouped && ((modelData.level1_display || "") === "" || modelData.level1_display === "Ungrouped Sub-System")
                                                implicitHeight: 20
                                                implicitWidth: cellCUngroupedText.implicitWidth + 8
                                                radius: 4
                                                color: "#2d1515"
                                                border.color: "#da3633"
                                                border.width: 1
                                                Text {
                                                    id: cellCUngroupedText
                                                    anchors.centerIn: parent
                                                    text: "⚠️ Ungrouped (No PBS)"
                                                    font.pixelSize: 9
                                                    color: "#f85149"
                                                }
                                            }

                                            // Sprint Taskboard Button
                                            Rectangle {
                                                implicitHeight: 20
                                                implicitWidth: cellCSprintBtnText.implicitWidth + 10
                                                radius: 10
                                                color: cellCSprintBtnMa.containsMouse ? "#1f6feb" : "#16243b"
                                                border.color: cellCSprintBtnMa.containsMouse ? "#58a6ff" : "#1f6feb"
                                                border.width: 1
                                                Text {
                                                    id: cellCSprintBtnText
                                                    anchors.centerIn: parent
                                                    text: "🏃 Sprint Board"
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    color: cellCSprintBtnMa.containsMouse ? "#ffffff" : "#79c0ff"
                                                }
                                                ToolTip.visible: cellCSprintBtnMa.containsMouse
                                                ToolTip.text: "Open Sprint Taskboard in TFS Browser\n(" + (modelData.iteration_path || (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "Sprint")) + ")"
                                                MouseArea {
                                                    id: cellCSprintBtnMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.sprint_week_name || modelData.iteration_name || modelData.iteration_path || "";
                                                        if (backend) {
                                                            backend.open_sprint_in_browser(modelData.id || sName, sName);
                                                        }
                                                    }
                                                }
                                            }

                                            // TFS Edit Button
                                            Rectangle {
                                                visible: modelData.id > 0
                                                implicitHeight: 20
                                                implicitWidth: cellCEditItemText.implicitWidth + 10
                                                radius: 10
                                                color: cellCEditItemMa.containsMouse ? "#238636" : "#21262d"
                                                border.color: cellCEditItemMa.containsMouse ? "#3fb950" : "#30363d"
                                                border.width: 1
                                                Text {
                                                    id: cellCEditItemText
                                                    anchors.centerIn: parent
                                                    text: "📝 Edit #" + modelData.id
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    color: cellCEditItemMa.containsMouse ? "#ffffff" : "#c9d1d9"
                                                }
                                                ToolTip.visible: cellCEditItemMa.containsMouse
                                                ToolTip.text: "Open Work Item Editor in TFS (#" + modelData.id + ")"
                                                MouseArea {
                                                    id: cellCEditItemMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (backend && modelData.id > 0) {
                                                            backend.open_work_item_in_browser(modelData.id);
                                                        }
                                                    }
                                                }
                                            }

                                            // In-App Sprint Analytics
                                            Rectangle {
                                                implicitHeight: 20
                                                implicitWidth: cellCAppReportText.implicitWidth + 10
                                                radius: 10
                                                color: cellCAppReportMa.containsMouse ? "#388bfd33" : "#21262d"
                                                border.color: cellCAppReportMa.containsMouse ? "#58a6ff" : "#30363d"
                                                border.width: 1
                                                Text {
                                                    id: cellCAppReportText
                                                    anchors.centerIn: parent
                                                    text: "📊 Analytics"
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    color: cellCAppReportMa.containsMouse ? "#58a6ff" : "#8b949e"
                                                }
                                                ToolTip.visible: cellCAppReportMa.containsMouse
                                                ToolTip.text: "Open In-App Sprint Analytics Report"
                                                MouseArea {
                                                    id: cellCAppReportMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.iteration_name || modelData.iteration_path;
                                                        if (typeof window !== "undefined" && typeof window.navigateToSprint === "function") {
                                                            window.navigateToSprint(sName);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Tasks Progress Bar
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: (modelData.total_tasks_count || 0) > 0
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: (modelData.tasks_not_started_count || 0) + " not started · " + (modelData.tasks_active_count || 0) + " active · " + (modelData.tasks_closed_count || 0) + " closed"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: (modelData.progress_percent || 0) + "% done"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: modelData.progress_percent === 100 ? "#3fb950" : "#58a6ff"
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 3
                                        color: "#21262d"
                                        clip: true

                                        Row {
                                            anchors.fill: parent
                                            spacing: 0

                                            Rectangle {
                                                width: parent.width * ((modelData.tasks_closed_count || 0) / Math.max(1, (modelData.total_tasks_count || 1)))
                                                height: parent.height
                                                color: "#3fb950"
                                            }

                                            Rectangle {
                                                width: parent.width * ((modelData.tasks_active_count || 0) / Math.max(1, (modelData.total_tasks_count || 1)))
                                                height: parent.height
                                                color: "#1f6feb"
                                            }

                                            Rectangle {
                                                width: parent.width * ((modelData.tasks_not_started_count || 0) / Math.max(1, (modelData.total_tasks_count || 1)))
                                                height: parent.height
                                                color: "#30363d"
                                            }
                                        }
                                    }
                                }

                                // Recessed Child Tasks Area
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: cellChildTasksCol.implicitHeight + 14
                                    radius: 6
                                    color: "#161b22"
                                    border.color: "#21262d"
                                    border.width: 1
                                    visible: (modelData.tasks && modelData.tasks.length > 0) || modelData.id === 0

                                    ColumnLayout {
                                        id: cellChildTasksCol
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 5

                                        Repeater {
                                            model: rightSidebarRoot.getFilteredCellTasks(modelData.tasks || [], rightSidebarRoot.cellHideClosedTasks)

                                            Rectangle {
                                                id: cellTaskCard
                                                Layout.fillWidth: true
                                                implicitHeight: cellTaskRow.implicitHeight + 10
                                                radius: 4
                                                color: cellTaskMa.containsMouse ? "#21262d" : "#0d1117"
                                                border.color: cellTaskMa.containsMouse ? "#388bfd" : "#30363d"
                                                border.width: 1

                                                // Context Menu
                                                Menu {
                                                    id: cellTaskContextMenu
                                                    MenuItem {
                                                        text: "🏃 Open Sprint Taskboard (TFS)"
                                                        onTriggered: {
                                                            var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.sprint_week_name || modelData.iteration_name || modelData.iteration_path || "";
                                                            if (backend) backend.open_sprint_in_browser(modelData.id || sName, sName);
                                                        }
                                                    }
                                                    MenuItem {
                                                        text: "📝 Open Work Item Editor (TFS #" + modelData.id + ")"
                                                        onTriggered: {
                                                            if (backend) backend.open_work_item_in_browser(modelData.id);
                                                        }
                                                    }
                                                    MenuItem {
                                                        text: "📊 View Sprint Analytics (In-App)"
                                                        onTriggered: {
                                                            var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.iteration_name || modelData.iteration_path;
                                                            if (typeof window !== "undefined" && typeof window.navigateToSprint === "function") {
                                                                window.navigateToSprint(sName);
                                                            }
                                                        }
                                                    }
                                                    MenuItem {
                                                        text: "📋 Filter in Work Items Tab"
                                                        onTriggered: {
                                                            if (typeof window !== "undefined" && typeof window.filterByWorkItem === "function") {
                                                                window.filterByWorkItem(modelData.id);
                                                            }
                                                        }
                                                    }
                                                    MenuSeparator {}
                                                    MenuItem {
                                                        text: "🔄 Reschedule Task Iteration..."
                                                        onTriggered: {
                                                            sidebarIterationPickerModal.openForWorkItem(
                                                                modelData.id,
                                                                modelData.title,
                                                                modelData.iteration_path || (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "")
                                                            );
                                                        }
                                                    }
                                                    MenuItem {
                                                        text: "📅 Set / Change Deadline..."
                                                        onTriggered: {
                                                            sidebarDeadlineDialog.openForWorkItem(
                                                                modelData.id,
                                                                modelData.title,
                                                                modelData.deadline_str,
                                                                rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : ""
                                                            );
                                                        }
                                                    }
                                                    MenuSeparator {}
                                                    MenuItem {
                                                        text: "🔗 Copy Work Item URL"
                                                        onTriggered: {
                                                            if (backend && modelData.tfs_url) backend.copy_to_clipboard(modelData.tfs_url);
                                                        }
                                                    }
                                                    MenuItem {
                                                        text: "🔗 Copy Sprint Taskboard URL"
                                                        onTriggered: {
                                                            if (backend) {
                                                                var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.sprint_week_name || modelData.iteration_name || modelData.iteration_path || "";
                                                                var sUrl = backend.get_sprint_taskboard_url(modelData.id || sName, sName);
                                                                if (sUrl) backend.copy_to_clipboard(sUrl);
                                                            }
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: cellTaskMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: function(mouse) {
                                                        if (mouse.button === Qt.RightButton) {
                                                            cellTaskContextMenu.popup();
                                                        } else {
                                                            var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.sprint_week_name || modelData.iteration_name || modelData.iteration_path || "";
                                                            if (backend) {
                                                                backend.open_sprint_in_browser(modelData.id || sName, sName);
                                                            }
                                                        }
                                                    }
                                                }

                                                RowLayout {
                                                    id: cellTaskRow
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 6

                                                    // Status Icon
                                                    Text {
                                                        text: modelData.is_done ? "✓" : "○"
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                        color: modelData.is_done ? "#3fb950" : "#58a6ff"
                                                    }

                                                    // Task ID Badge
                                                    Rectangle {
                                                        implicitHeight: 18
                                                        implicitWidth: cellTkIdText.implicitWidth + 8
                                                        radius: 4
                                                        color: cellTkIdMa.containsMouse ? "#1f6feb" : "#21262d"
                                                        border.color: cellTkIdMa.containsMouse ? "#58a6ff" : "#30363d"
                                                        border.width: 1

                                                        Text {
                                                            id: cellTkIdText
                                                            anchors.centerIn: parent
                                                            text: "#" + modelData.id
                                                            font.family: "Consolas, monospace"
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: cellTkIdMa.containsMouse ? "#ffffff" : "#58a6ff"
                                                        }
                                                        ToolTip.visible: cellTkIdMa.containsMouse
                                                        ToolTip.text: "Click to open Work Item Editor in TFS (#" + modelData.id + ")"
                                                        MouseArea {
                                                            id: cellTkIdMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (backend) {
                                                                    backend.open_work_item_in_browser(modelData.id);
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Task Title
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.title || (modelData.id > 0 ? ("Task #" + modelData.id) : "")
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: modelData.is_done ? "#8b949e" : "#e6edf3"
                                                        elide: Text.ElideRight
                                                        ToolTip.visible: cellTaskMa.containsMouse
                                                        ToolTip.text: (modelData.title || "") + "\n• Left-Click: Open Sprint Taskboard in TFS\n• Click #" + modelData.id + ": Open Work Item Editor\n• Right-Click: More sprint & item options"
                                                    }

                                                    // Type Pill (Task vs Bug)
                                                    Rectangle {
                                                        implicitHeight: 16
                                                        implicitWidth: cellTkTypeLabel.implicitWidth + 8
                                                        radius: 8
                                                        color: (modelData.type || "").toLowerCase().indexOf("bug") !== -1 ? "#3d1417" : "#161b22"
                                                        border.color: (modelData.type || "").toLowerCase().indexOf("bug") !== -1 ? "#f85149" : "#30363d"
                                                        Text {
                                                            id: cellTkTypeLabel
                                                            anchors.centerIn: parent
                                                            text: modelData.type || "Task"
                                                            font.pixelSize: 9
                                                            color: (modelData.type || "").toLowerCase().indexOf("bug") !== -1 ? "#ff7b72" : "#8b949e"
                                                        }
                                                    }

                                                    // State Pill
                                                    Rectangle {
                                                        implicitHeight: 16
                                                        implicitWidth: cellTkStateLabel.implicitWidth + 8
                                                        radius: 8
                                                        color: modelData.is_done ? "#0d3525" : "#161b22"
                                                        border.color: modelData.is_done ? "#3fb950" : "#30363d"
                                                        Text {
                                                            id: cellTkStateLabel
                                                            anchors.centerIn: parent
                                                            text: modelData.state || "Active"
                                                            font.pixelSize: 9
                                                            color: modelData.is_done ? "#3fb950" : "#d29922"
                                                        }
                                                    }

                                                    // Sprint Taskboard Button
                                                    Rectangle {
                                                        implicitHeight: 18
                                                        implicitWidth: cellTkSprintBtnText.implicitWidth + 8
                                                        radius: 9
                                                        color: cellTkSprintBtnMa.containsMouse ? "#1f6feb" : "#16243b"
                                                        border.color: cellTkSprintBtnMa.containsMouse ? "#58a6ff" : "#1f6feb"
                                                        border.width: 1
                                                        Text {
                                                            id: cellTkSprintBtnText
                                                            anchors.centerIn: parent
                                                            text: "🏃 Sprint"
                                                            font.pixelSize: 9
                                                            font.weight: Font.DemiBold
                                                            color: cellTkSprintBtnMa.containsMouse ? "#ffffff" : "#79c0ff"
                                                        }
                                                        ToolTip.visible: cellTkSprintBtnMa.containsMouse
                                                        ToolTip.text: "Open Sprint Taskboard in TFS Browser\n(" + (modelData.iteration_path || (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "Sprint")) + ")"
                                                        MouseArea {
                                                            id: cellTkSprintBtnMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.sprint_week_name || modelData.iteration_name || modelData.iteration_path || "";
                                                                if (backend) {
                                                                    backend.open_sprint_in_browser(modelData.id || sName, sName);
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Work Item Editor Button
                                                    Rectangle {
                                                        implicitHeight: 18
                                                        implicitWidth: cellTkEditBtnText.implicitWidth + 8
                                                        radius: 9
                                                        color: cellTkEditBtnMa.containsMouse ? "#238636" : "#21262d"
                                                        border.color: cellTkEditBtnMa.containsMouse ? "#3fb950" : "#30363d"
                                                        border.width: 1
                                                        Text {
                                                            id: cellTkEditBtnText
                                                            anchors.centerIn: parent
                                                            text: "📝 Edit"
                                                            font.pixelSize: 9
                                                            font.weight: Font.DemiBold
                                                            color: cellTkEditBtnMa.containsMouse ? "#ffffff" : "#c9d1d9"
                                                        }
                                                        ToolTip.visible: cellTkEditBtnMa.containsMouse
                                                        ToolTip.text: "Open Work Item Editor in TFS (#" + modelData.id + ")"
                                                        MouseArea {
                                                            id: cellTkEditBtnMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (backend) {
                                                                    backend.open_work_item_in_browser(modelData.id);
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // In-App Sprint Analytics
                                                    Rectangle {
                                                        implicitHeight: 18
                                                        implicitWidth: cellTkAppSprintText.implicitWidth + 8
                                                        radius: 9
                                                        color: cellTkAppSprintMa.containsMouse ? "#388bfd33" : "#161b22"
                                                        border.color: cellTkAppSprintMa.containsMouse ? "#58a6ff" : "#30363d"
                                                        border.width: 1
                                                        Text {
                                                            id: cellTkAppSprintText
                                                            anchors.centerIn: parent
                                                            text: "📊"
                                                            font.pixelSize: 9
                                                        }
                                                        ToolTip.visible: cellTkAppSprintMa.containsMouse
                                                        ToolTip.text: "View in App Sprint Report (" + (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : (modelData.iteration_path || "Sprint")) + ")"
                                                        MouseArea {
                                                            id: cellTkAppSprintMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                var sName = (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "") || modelData.iteration_name || modelData.iteration_path;
                                                                if (typeof window !== "undefined" && typeof window.navigateToSprint === "function") {
                                                                    window.navigateToSprint(sName);
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Move Iteration Button
                                                    Rectangle {
                                                        implicitHeight: 18
                                                        implicitWidth: cellTkSprintText.implicitWidth + 8
                                                        radius: 9
                                                        color: "#21262d"
                                                        border.color: cellTkMoveMa.containsMouse ? "#58a6ff" : "#30363d"
                                                        Text {
                                                            id: cellTkSprintText
                                                            anchors.centerIn: parent
                                                            text: "🔄"
                                                            font.pixelSize: 9
                                                        }
                                                        ToolTip.visible: cellTkMoveMa.containsMouse
                                                        ToolTip.text: "Reschedule task #" + modelData.id
                                                        MouseArea {
                                                            id: cellTkMoveMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                sidebarIterationPickerModal.openForWorkItem(
                                                                    modelData.id,
                                                                    modelData.title,
                                                                    modelData.iteration_path || (rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : "")
                                                                );
                                                            }
                                                        }
                                                    }

                                                    // Deadline Button
                                                    Rectangle {
                                                        implicitHeight: 18
                                                        implicitWidth: cellTkDlText.implicitWidth + 8
                                                        radius: 9
                                                        property bool hasDate: (modelData.deadline_str || "") !== ""
                                                        color: Qt.rgba((modelData.urgency_color ? modelData.urgency_color.r : 0.5), (modelData.urgency_color ? modelData.urgency_color.g : 0.5), (modelData.urgency_color ? modelData.urgency_color.b : 0.5), 0.15)
                                                        border.color: cellTkDlMa.containsMouse ? "#58a6ff" : Qt.rgba((modelData.urgency_color ? modelData.urgency_color.r : 0.5), (modelData.urgency_color ? modelData.urgency_color.g : 0.5), (modelData.urgency_color ? modelData.urgency_color.b : 0.5), 0.4)
                                                        Text {
                                                            id: cellTkDlText
                                                            anchors.centerIn: parent
                                                            text: parent.hasDate ? (modelData.urgency_badge || modelData.deadline_str) : "📅"
                                                            font.pixelSize: 9
                                                            color: modelData.urgency_color || "#8b949e"
                                                        }
                                                        ToolTip.visible: cellTkDlMa.containsMouse
                                                        ToolTip.text: "Deadline: " + (modelData.deadline_str || "None") + "\n(Click to edit)"
                                                        MouseArea {
                                                            id: cellTkDlMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                sidebarDeadlineDialog.openForWorkItem(
                                                                    modelData.id,
                                                                    modelData.title,
                                                                    modelData.deadline_str,
                                                                    rightSidebarRoot.sidebarData ? rightSidebarRoot.sidebarData.sprint_name : ""
                                                                );
                                                            }
                                                        }
                                                    }

                                                    // Milestone Pill
                                                    Rectangle {
                                                        visible: (modelData.milestone_name || "") !== ""
                                                        implicitHeight: 18
                                                        implicitWidth: cellTkMStoneRow.implicitWidth + 8
                                                        radius: 9
                                                        color: modelData.milestone_bg || "#16243b"
                                                        border.color: modelData.milestone_color || "#1f6feb"
                                                        Row {
                                                            id: cellTkMStoneRow
                                                            anchors.centerIn: parent
                                                            spacing: 2
                                                            Text {
                                                                text: modelData.milestone_icon || "🚩"
                                                                font.pixelSize: 8
                                                            }
                                                            Text {
                                                                text: modelData.milestone_name
                                                                font.pixelSize: 8
                                                                font.weight: Font.DemiBold
                                                                color: modelData.milestone_color || "#79c0ff"
                                                            }
                                                        }
                                                        ToolTip.visible: cellTkMStoneMa.containsMouse
                                                        ToolTip.text: "Milestone: " + (modelData.milestone_name || "") + " (" + (modelData.milestone_category || "") + ")"
                                                        MouseArea {
                                                            id: cellTkMStoneMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (typeof window !== "undefined" && window.openMilestonesManager) {
                                                                    window.openMilestonesManager();
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Hidden closed indicator
                                        Text {
                                            visible: rightSidebarRoot.cellHideClosedTasks && (modelData.completed_tasks_count || 0) > 0
                                            text: "✓ " + modelData.completed_tasks_count + " closed task(s) hidden in this story"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#3fb950"
                                        }

                                        // Placeholder if no tasks exist
                                        Text {
                                            visible: (!modelData.tasks || modelData.tasks.length === 0)
                                            text: modelData.id > 0 ? "ℹ️ Direct Story Item (No subtasks)" : "No tasks"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.italic: true
                                            color: "#6e7681"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Empty state if no items
                    Rectangle {
                        visible: !rightSidebarRoot.sidebarData || !rightSidebarRoot.sidebarData.items || rightSidebarRoot.sidebarData.items.length === 0
                        Layout.fillWidth: true
                        implicitHeight: 90
                        radius: 6
                        color: "#0d1117"
                        border.color: "#21262d"
                        border.width: 1

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "📋 No Tasks in This Sprint Cell"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#8b949e"
                            }
                        }
                    }

                    Item { height: 16 }
                }
            }
        }
    }

    // ==========================================
    // Modals for Work Item Quick Actions
    // ==========================================
    DeadlineEditorDialog {
        id: sidebarDeadlineDialog
        onDeadlineUpdated: function(id, newDate, result) {
            rightSidebarRoot.showToast("Deadline updated for #" + id);
            rightSidebarRoot.actionTriggered("workload_refresh", { id: id });
        }
    }

    IterationPickerModal {
        id: sidebarIterationPickerModal
        onIterationUpdated: function(id, newIteration, result) {
            rightSidebarRoot.showToast("Sprint rescheduled for #" + id);
            rightSidebarRoot.actionTriggered("workload_refresh", { id: id });
        }
    }
}
