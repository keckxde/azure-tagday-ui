import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: rightSidebarRoot

    // Public Properties
    property bool isOpen: false
    property string mode: "workload_member" // "workload_member", "report_preview", "contributor_profile", "raw_file"
    property string sidebarTitle: "Context Details"
    property string sidebarSubtitle: ""
    property var sidebarData: null
    property real preferredWidth: 440
    property real minWidth: 340
    property real maxWidth: 760

    // Report View State
    property int reportViewMode: 0 // 0: Formatted Markdown, 1: Raw Text, 2: Data Table
    property var reportParsedTable: null
    property string reportRawText: ""
    property var reportMeta: null
    property string toastMessage: ""

    signal closeRequested()
    signal actionTriggered(string action, var params)

    Layout.preferredWidth: isOpen ? preferredWidth : 0
    Layout.fillHeight: true
    visible: isOpen || Layout.preferredWidth > 0
    color: "#161b22"
    border.color: "#30363d"
    border.width: 1
    clip: true
    z: 10

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
                        if (rightSidebarRoot.mode === "workload_member") return "#1f6feb";
                        if (rightSidebarRoot.mode === "contributor_profile") return "#a371f7";
                        return "#238636";
                    }
                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (rightSidebarRoot.mode === "workload_member") return "📊";
                            if (rightSidebarRoot.mode === "contributor_profile") return "👤";
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
                        text: rightSidebarRoot.sidebarSubtitle || (rightSidebarRoot.mode === "workload_member" ? "Team Member Workload" : (rightSidebarRoot.mode === "contributor_profile" ? "Contributor Gamification Profile" : "Report Preview"))
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
                        if (rightSidebarRoot.preferredWidth > 500) {
                            rightSidebarRoot.preferredWidth = 440;
                        } else {
                            rightSidebarRoot.preferredWidth = 640;
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

                            Text {
                                text: "🏆 Earned Badges & Medals"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }

                            Repeater {
                                model: (rightSidebarRoot.sidebarData && rightSidebarRoot.sidebarData.badges) ? rightSidebarRoot.sidebarData.badges : []
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: 36
                                    radius: 6
                                    color: "#161b22"
                                    border.color: "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Text {
                                            text: modelData.icon || "🏅"
                                            font.pixelSize: 16
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: modelData.name || "Achievement"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: modelData.description || "Completed milestone"
                                                font.pixelSize: 9
                                                color: "#8b949e"
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            text: "+" + (modelData.xp || 50) + " XP"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: "#e3b341"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { height: 12 }
                }
            }
        }
    }
}
