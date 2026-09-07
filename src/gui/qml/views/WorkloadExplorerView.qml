import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root

    property int selectedHorizon: 4 // 4, 8, or 12 weeks
    property string searchQuery: ""
    property var matrixData: null
    property var selectedCell: null // { assignee: "...", sprint_name: "...", items: [...] }
    property bool hideClosedTasks: false

    function getFilteredContainers(containers) {
        if (!containers) return [];
        if (!root.hideClosedTasks) return containers;
        var res = [];
        for (var i = 0; i < containers.length; i++) {
            var c = containers[i];
            var openTasks = getFilteredTasks(c.tasks || []);
            // Keep container if it has open child tasks, or if the parent container itself is not done/closed
            if (openTasks.length > 0 || !c.is_done) {
                res.push(c);
            }
        }
        return res;
    }

    function getFilteredTasks(tasksList) {
        if (!tasksList) return [];
        if (!root.hideClosedTasks) return tasksList;
        var res = [];
        for (var i = 0; i < tasksList.length; i++) {
            if (!tasksList[i].is_done) {
                res.push(tasksList[i]);
            }
        }
        return res;
    }

    function refreshMatrix() {
        if (!backend) return
        matrixData = backend.getWorkloadMatrix(root.selectedHorizon)
    }

    onSelectedHorizonChanged: refreshMatrix()

    Connections {
        target: backend
        function onWorkItemsChanged() {
            root.refreshMatrix()
        }
        function onWorkloadMatrixChanged() {
            root.refreshMatrix()
        }
    }

    Component.onCompleted: {
        refreshMatrix()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // ====================== Top Header & Controls ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 2
                Text {
                    text: "Team Workload & Capacity Explorer"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }
                Text {
                    text: "Sprint-by-sprint distribution of User Stories, Bugs, and Tasks across team members"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                }
            }

            Item { Layout.fillWidth: true }

            // Horizon Selector Buttons (4, 8, 12 Sprints)
            Row {
                spacing: 6
                Text {
                    text: "Horizon:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: [
                        { label: "4 Sprints (1 Mo)", value: 4 },
                        { label: "8 Sprints (2 Mo)", value: 8 },
                        { label: "12 Sprints (1 Qtr)", value: 12 }
                    ]
                    Button {
                        text: modelData.label
                        checkable: true
                        checked: root.selectedHorizon === modelData.value
                        font.pixelSize: 11
                        font.weight: checked ? Font.DemiBold : Font.Normal
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.checked ? "#ffffff" : "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 30
                            implicitWidth: 125
                            radius: 6
                            color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? "#388bfd" : "#30363d"
                        }
                        onClicked: {
                            root.selectedHorizon = modelData.value
                        }
                    }
                }
            }

            Item { width: 4 }

            // Bug Hierarchy Mode Switcher
            Row {
                spacing: 4
                Text {
                    text: "🪲 Bugs:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Repeater {
                    model: [
                        { label: "As Stories", value: "like_user_story", tip: "Bugs are top-level containers that can contain tasks" },
                        { label: "As Tasks", value: "like_task", tip: "Bugs are child tasks nested inside parent stories" }
                    ]
                    Button {
                        text: modelData.label
                        checkable: true
                        checked: backend && backend.bugHierarchyMode === modelData.value
                        font.pixelSize: 10
                        font.weight: checked ? Font.DemiBold : Font.Normal
                        ToolTip.visible: hovered
                        ToolTip.text: modelData.tip
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.checked ? "#ffffff" : "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 30
                            implicitWidth: 86
                            radius: 6
                            color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? "#388bfd" : "#30363d"
                        }
                        onClicked: {
                            if (backend) {
                                backend.setBugHierarchyMode(modelData.value);
                            }
                        }
                    }
                }
            }

            Item { width: 4 }

            // Hide Closed Tasks Toggle in Top Header
            Button {
                text: root.hideClosedTasks ? "⚡ Active Only" : "📋 All Tasks"
                checkable: true
                checked: root.hideClosedTasks
                font.pixelSize: 11
                font.weight: Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: root.hideClosedTasks ? "Showing active/open tasks only. Click to show closed items." : "Showing all tasks (active & closed). Click to hide completed tasks."
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: parent.checked ? "#3fb950" : "#8b949e"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 30
                    implicitWidth: 105
                    radius: 6
                    color: parent.checked ? "#0d3525" : (parent.hovered ? "#21262d" : "#161b22")
                    border.color: parent.checked ? "#238636" : "#30363d"
                }
                onClicked: { root.hideClosedTasks = !root.hideClosedTasks }
            }

            Item { width: 4 }

            // Search Bar
            SearchBar {
                placeholder: "Filter team member..."
                onSearchUpdated: function(query) {
                    root.searchQuery = (query || "").toLowerCase()
                }
            }

            // Refresh Button
            Button {
                text: "🔄 Refresh"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#f0f6fc"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 30
                    implicitWidth: 80
                    radius: 6
                    color: parent.hovered ? "#30363d" : "#21262d"
                    border.color: "#30363d"
                }
                onClicked: root.refreshMatrix()
            }
        }

        // ====================== KPI Summary Cards ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Total Planned
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Text { text: "📦"; font.pixelSize: 24 }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "TOTAL PLANNED"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                        Text {
                            text: root.matrixData ? (root.matrixData.total_items || 0).toString() : "0"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                    }
                }
            }

            // Stories & Requirements
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Text { text: "🎯"; font.pixelSize: 24 }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "STORIES & REQS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                        Text {
                            text: root.matrixData ? (root.matrixData.total_stories || 0).toString() : "0"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: "#3fb950"
                        }
                    }
                }
            }

            // Bugs & Defects
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Text { text: "🐛"; font.pixelSize: 24 }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "BUGS & DEFECTS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                        Text {
                            text: root.matrixData ? (root.matrixData.total_bugs || 0).toString() : "0"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: "#f85149"
                        }
                    }
                }
            }

            // Technical Tasks
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Text { text: "🛠️"; font.pixelSize: 24 }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "TASKS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                        Text {
                            text: root.matrixData ? (root.matrixData.total_tasks || 0).toString() : "0"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: "#d29922"
                        }
                    }
                }
            }

            // Overdue Warnings
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: root.matrixData && root.matrixData.total_overdue > 0 ? "#261315" : "#161b22"
                radius: 8
                border.color: root.matrixData && root.matrixData.total_overdue > 0 ? "#da3633" : "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Text { text: "🚨"; font.pixelSize: 24 }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "OVERDUE DEADLINES"; font.pixelSize: 10; font.weight: Font.Bold; color: root.matrixData && root.matrixData.total_overdue > 0 ? "#ff7b72" : "#8b949e" }
                        Text {
                            text: root.matrixData ? (root.matrixData.total_overdue || 0).toString() : "0"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: root.matrixData && root.matrixData.total_overdue > 0 ? "#f85149" : "#8b949e"
                        }
                    }
                }
            }
        }

        // ====================== Main Workload Heatmap Matrix ======================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: "#0d1117"
                radius: 8
                border.color: "#30363d"
                border.width: 1
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // ---- Matrix Header (Sprint Columns) ----
                    Rectangle {
                        Layout.fillWidth: true
                        height: 48
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Assignee Header Column
                            Item {
                                Layout.preferredWidth: 220
                                Layout.fillHeight: true
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    Text {
                                        text: "TEAM MEMBER"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#8b949e"
                                    }
                                }
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 1
                                    color: "#30363d"
                                }
                            }

                            // Sprint Column Headers
                            Repeater {
                                model: root.matrixData ? (root.matrixData.sprint_columns || []) : []
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text {
                                            text: modelData.short_label || modelData.sprint_name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#f0f6fc"
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Text {
                                            text: modelData.start_date ? (modelData.start_date.substring(5) + " · " + modelData.end_date.substring(5)) : ""
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 1
                                        color: "#30363d"
                                    }
                                }
                            }

                            // Total column header
                            Item {
                                Layout.preferredWidth: 100
                                Layout.fillHeight: true
                                Text {
                                    anchors.centerIn: parent
                                    text: "TOTAL"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                }
                            }
                        }
                    }

                    // ---- Matrix Body (Assignee Rows) ----
                    ListView {
                        id: matrixListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 1

                        model: {
                            if (!root.matrixData || !root.matrixData.assignee_rows) return []
                            var rows = root.matrixData.assignee_rows || []
                            if (!root.searchQuery) return rows
                            return rows.filter(function(r) {
                                return (r.assignee || "").toLowerCase().indexOf(root.searchQuery) !== -1
                            })
                        }

                        delegate: Rectangle {
                            width: matrixListView.width
                            height: 48
                            color: rowMa.containsMouse ? "#1c2128" : "#0d1117"
                            border.color: "#21262d"
                            border.width: 1

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 0

                                // Assignee Info Column
                                Item {
                                    Layout.preferredWidth: 220
                                    Layout.fillHeight: true

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 8
                                        spacing: 10

                                        // Avatar pill
                                        Rectangle {
                                            width: 28
                                            height: 28
                                            radius: 14
                                            color: modelData.assignee === "Unassigned" ? "#30363d" : "#1f6feb"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.initials || "U"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: "#ffffff"
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.assignee
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            color: modelData.assignee === "Unassigned" ? "#8b949e" : "#f0f6fc"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 1
                                        color: "#21262d"
                                    }
                                }

                                // Sprint Cells
                                Repeater {
                                    model: modelData.cells || []
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        property bool hasItems: modelData.total_count > 0
                                        property bool hasOverdue: modelData.overdue_count > 0
                                        property bool isSelected: root.selectedCell && root.selectedCell.assignee === modelData.assignee && root.selectedCell.sprint_name === modelData.sprint_name

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            radius: 6
                                            color: {
                                                if (isSelected) return "#1f6feb"
                                                if (cellMa.containsMouse) return "#262c36"
                                                if (!hasItems) return "transparent"
                                                if (hasOverdue) return "#381e1e"
                                                if (modelData.total_count >= 8) return "#0d3525"
                                                if (modelData.total_count >= 4) return "#0d2344"
                                                return "#161b22"
                                            }
                                            border.color: {
                                                if (isSelected) return "#58a6ff"
                                                if (hasOverdue) return "#f85149"
                                                if (hasItems) return "#30363d"
                                                return "transparent"
                                            }
                                            border.width: 1

                                            // Cell content
                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                visible: hasItems

                                                // Total items pill
                                                Text {
                                                    text: modelData.total_count.toString()
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    color: hasOverdue ? "#ff7b72" : (isSelected ? "#ffffff" : "#f0f6fc")
                                                }

                                                // Type tags breakdown
                                                Row {
                                                    spacing: 3
                                                    Text { text: "🎯" + modelData.stories_count; font.pixelSize: 10; visible: modelData.stories_count > 0 }
                                                    Text { text: "🐛" + modelData.bugs_count; font.pixelSize: 10; visible: modelData.bugs_count > 0 }
                                                    Text { text: "🚨" + modelData.overdue_count; font.pixelSize: 10; visible: modelData.overdue_count > 0 }
                                                }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "—"
                                                font.pixelSize: 12
                                                color: "#30363d"
                                                visible: !hasItems
                                            }

                                            MouseArea {
                                                id: cellMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: hasItems ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    if (hasItems) {
                                                        root.selectedCell = {
                                                            assignee: modelData.assignee || "Team Member",
                                                            sprint_name: modelData.sprint_name,
                                                            total_count: modelData.total_count,
                                                            stories_count: modelData.stories_count,
                                                            bugs_count: modelData.bugs_count,
                                                            tasks_count: modelData.tasks_count,
                                                            overdue_count: modelData.overdue_count,
                                                            items: modelData.items || []
                                                        }
                                                    }
                                                }
                                            }

                                            ToolTip.visible: cellMa.containsMouse && hasItems
                                            ToolTip.text: (modelData.assignee || "") + " @ " + (modelData.sprint_name || "") + "\n" +
                                                          "Total: " + modelData.total_count + " items\n" +
                                                          "Stories: " + modelData.stories_count + " | Bugs: " + modelData.bugs_count + " | Tasks: " + modelData.tasks_count +
                                                          (hasOverdue ? ("\n🚨 Overdue: " + modelData.overdue_count) : "")
                                        }

                                        Rectangle {
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 1
                                            color: "#21262d"
                                        }
                                    }
                                }

                                // Assignee Horizon Total
                                Item {
                                    Layout.preferredWidth: 100
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 60
                                        height: 24
                                        radius: 12
                                        color: "#161b22"
                                        border.color: "#30363d"
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.stats ? modelData.stats.total.toString() : "0"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Matrix Column Totals Footer ----
                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            Item {
                                Layout.preferredWidth: 220
                                Layout.fillHeight: true
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "TOTAL CAPACITY"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }
                                Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: "#30363d" }
                            }

                            Repeater {
                                model: root.matrixData ? (root.matrixData.column_totals || []) : []
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Text {
                                        anchors.centerIn: parent
                                        text: (modelData.total_count || 0) + " items"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                    Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: "#30363d" }
                                }
                            }

                            Item {
                                Layout.preferredWidth: 100
                                Layout.fillHeight: true
                                Text {
                                    anchors.centerIn: parent
                                    text: root.matrixData ? (root.matrixData.total_items || 0).toString() : "0"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#3fb950"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ====================== Drilldown Drawer / Detail Slideout ======================
    Rectangle {
        id: detailDrawer
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 480
        visible: root.selectedCell !== null
        color: "#161b22"
        border.color: "#30363d"
        border.width: 1

        // Slide animation
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Drawer Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.selectedCell ? root.selectedCell.assignee : ""
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        spacing: 8
                        Text {
                            text: "Sprint: " + (root.selectedCell ? root.selectedCell.sprint_name : "") + " (" + (root.selectedCell ? root.selectedCell.total_count : 0) + " items)"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#58a6ff"
                        }

                        Text {
                            text: "• Grouped by Parent Container"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                        }
                    }
                }

                Button {
                    text: "✕"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitWidth: 28; implicitHeight: 28; radius: 14; color: parent.hovered ? "#30363d" : "transparent" }
                    onClicked: { root.selectedCell = null }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#30363d" }

            // Filter Bar in Drawer
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 6
                color: "#161b22"
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
                        implicitWidth: allBtnText.implicitWidth + 14
                        radius: 11
                        color: !root.hideClosedTasks ? "#1f6feb" : "#21262d"
                        border.color: !root.hideClosedTasks ? "#388bfd" : "#30363d"
                        Text {
                            id: allBtnText
                            anchors.centerIn: parent
                            text: "Show All (" + (root.selectedCell ? root.selectedCell.total_count : 0) + ")"
                            font.pixelSize: 10
                            font.weight: !root.hideClosedTasks ? Font.Bold : Font.Normal
                            color: !root.hideClosedTasks ? "#ffffff" : "#8b949e"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.hideClosedTasks = false }
                        }
                    }

                    // Hide Closed Button
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: actBtnText.implicitWidth + 14
                        radius: 11
                        color: root.hideClosedTasks ? "#238636" : "#21262d"
                        border.color: root.hideClosedTasks ? "#3fb950" : "#30363d"
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "⚡"
                                font.pixelSize: 10
                            }
                            Text {
                                id: actBtnText
                                text: "Hide Closed (" + (root.selectedCell ? (root.selectedCell.total_count - root.selectedCell.completed_count) : 0) + " open)"
                                font.pixelSize: 10
                                font.weight: root.hideClosedTasks ? Font.Bold : Font.Normal
                                color: root.hideClosedTasks ? "#ffffff" : "#8b949e"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.hideClosedTasks = true }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: root.hideClosedTasks && root.selectedCell && root.selectedCell.completed_count > 0
                        text: "✓ " + root.selectedCell.completed_count + " closed hidden"
                        font.pixelSize: 10
                        color: "#3fb950"
                    }
                }
            }

            // Parent Container Cards List
            ListView {
                id: drawerItemsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 12

                model: root.getFilteredContainers(root.selectedCell ? (root.selectedCell.grouped_containers || root.selectedCell.items || []) : [])

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    width: drawerItemsList.width - 6
                    implicitHeight: containerCol.implicitHeight + 18
                    radius: 8
                    color: "#0d1117"
                    border.color: {
                        if (modelData.urgency_status === "overdue") return "#f85149"
                        if (cardHeaderMa.containsMouse) return "#388bfd"
                        return "#30363d"
                    }
                    border.width: 1

                    ColumnLayout {
                        id: containerCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // Container Card Top Header (User Story / Bug / Requirement / Standalone)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Container Type Icon & ID
                            RowLayout {
                                spacing: 4
                                Text {
                                    text: {
                                        var t = (modelData.type || "").toLowerCase();
                                        if (t.indexOf("bug") !== -1 || t.indexOf("defect") !== -1) return "🐛";
                                        if (t.indexOf("req") !== -1) return "📋";
                                        if (t.indexOf("standalone") !== -1) return "🛠️";
                                        return "🎯";
                                    }
                                    font.pixelSize: 15
                                }

                                Text {
                                    text: modelData.id > 0 ? ("#" + modelData.id) : "Direct"
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: modelData.id > 0 ? "#58a6ff" : "#8b949e"

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: (modelData.tfs_url || "") !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (backend && (modelData.tfs_url || "") !== "") {
                                                backend.open_url(modelData.tfs_url)
                                            }
                                        }
                                    }
                                }
                            }

                            // Type badge
                            Rectangle {
                                implicitHeight: 20
                                implicitWidth: cTypeLabel.implicitWidth + 10
                                radius: 10
                                color: "#161b22"
                                border.color: "#30363d"
                                Text {
                                    id: cTypeLabel
                                    anchors.centerIn: parent
                                    text: modelData.type || "Story"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: "#c9d1d9"
                                }
                            }

                            // State badge
                            Rectangle {
                                visible: modelData.id > 0
                                implicitHeight: 20
                                implicitWidth: cStateLabel.implicitWidth + 10
                                radius: 10
                                color: modelData.is_done ? "#0d3525" : "#161b22"
                                border.color: modelData.is_done ? "#3fb950" : "#30363d"
                                Text {
                                    id: cStateLabel
                                    anchors.centerIn: parent
                                    text: modelData.state || "Active"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: modelData.is_done ? "#3fb950" : "#d29922"
                                }
                            }

                            // External Parent Indicator if assigned to someone else
                            Rectangle {
                                visible: !modelData.is_parent_in_cell && modelData.id > 0
                                implicitHeight: 20
                                implicitWidth: extParentText.implicitWidth + 10
                                radius: 10
                                color: "#1a1e24"
                                border.color: "#30363d"
                                Text {
                                    id: extParentText
                                    anchors.centerIn: parent
                                    text: "👤 " + (modelData.assigned_to || "Unassigned")
                                    font.pixelSize: 9
                                    color: "#8b949e"
                                }
                                ToolTip.visible: extMa.containsMouse
                                ToolTip.text: "Parent Story is assigned to " + modelData.assigned_to
                                MouseArea { id: extMa; anchors.fill: parent; hoverEnabled: true }
                            }

                            Item { Layout.fillWidth: true }

                            // Move Sprint Pill (for parent story/bug)
                            Rectangle {
                                visible: modelData.id > 0
                                implicitHeight: 22
                                implicitWidth: cSprintRow.implicitWidth + 12
                                radius: 11
                                color: "#21262d"
                                border.color: cEditSprintMa.containsMouse ? "#58a6ff" : "#30363d"
                                border.width: 1

                                RowLayout {
                                    id: cSprintRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "🔄 " + (modelData.iteration_path ? modelData.iteration_path.split("\\").pop() : (root.selectedCell ? root.selectedCell.sprint_name : "Sprint"))
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: "#58a6ff"
                                    }
                                }
                                ToolTip.visible: cEditSprintMa.containsMouse
                                ToolTip.text: "Reschedule Parent Story / Container to another sprint"

                                MouseArea {
                                    id: cEditSprintMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        workloadIterationPickerModal.openForWorkItem(
                                            modelData.id,
                                            modelData.title,
                                            modelData.iteration_path || (root.selectedCell ? root.selectedCell.sprint_name : "")
                                        );
                                    }
                                }
                            }

                            // Deadline Pill (for parent story/bug)
                            Rectangle {
                                visible: modelData.id > 0
                                implicitHeight: 22
                                implicitWidth: cDdRow.implicitWidth + 12
                                radius: 11
                                property bool hasDate: (modelData.deadline_str || "") !== ""
                                color: Qt.rgba(modelData.urgency_color.r, modelData.urgency_color.g, modelData.urgency_color.b, 0.15)
                                border.color: cEditDlMa.containsMouse ? "#58a6ff" : Qt.rgba(modelData.urgency_color.r, modelData.urgency_color.g, modelData.urgency_color.b, 0.5)
                                border.width: 1

                                RowLayout {
                                    id: cDdRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: parent.parent.hasDate ? (modelData.urgency_badge || modelData.deadline_str) : "➕ Date"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: modelData.urgency_color || "#8b949e"
                                    }
                                }
                                ToolTip.visible: cEditDlMa.containsMouse
                                ToolTip.text: "Deadline: " + (modelData.deadline_str || "None") + "\n(Click to edit)"

                                MouseArea {
                                    id: cEditDlMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        workloadDeadlineDialog.openForWorkItem(
                                            modelData.id,
                                            modelData.title,
                                            modelData.deadline_str,
                                            root.selectedCell ? root.selectedCell.sprint_name : ""
                                        );
                                    }
                                }
                            }
                        }

                        // Container Title
                        Text {
                            Layout.fillWidth: true
                            text: modelData.title || ""
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                            wrapMode: Text.WordWrap

                            MouseArea {
                                id: cardHeaderMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: (modelData.tfs_url || "") !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (backend && (modelData.tfs_url || "") !== "") {
                                        backend.open_url(modelData.tfs_url)
                                    }
                                }
                            }
                        }

                        // Tasks Progress Bar (if container has child tasks)
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: (modelData.total_tasks_count || 0) > 0
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: (modelData.completed_tasks_count || 0) + " / " + (modelData.total_tasks_count || 0) + " tasks completed"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (modelData.progress_percent || 0) + "%"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: modelData.progress_percent === 100 ? "#3fb950" : "#58a6ff"
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 2.5
                                color: "#21262d"
                                Rectangle {
                                    width: parent.width * ((modelData.progress_percent || 0) / 100)
                                    height: parent.height
                                    radius: 2.5
                                    color: modelData.progress_percent === 100 ? "#3fb950" : "#1f6feb"
                                }
                            }
                        }

                        // Nested Child Tasks Area (Recessed Container Box)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: childTasksCol.implicitHeight + 14
                            radius: 6
                            color: "#161b22"
                            border.color: "#21262d"
                            border.width: 1
                            visible: (modelData.tasks && modelData.tasks.length > 0) || modelData.id === 0

                            ColumnLayout {
                                id: childTasksCol
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5

                                Repeater {
                                    model: root.getFilteredTasks(modelData.tasks || [])

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: taskRow.implicitHeight + 10
                                        radius: 4
                                        color: taskMa.containsMouse ? "#21262d" : "#0d1117"
                                        border.color: taskMa.containsMouse ? "#388bfd" : "#30363d"
                                        border.width: 1

                                        RowLayout {
                                            id: taskRow
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            // Status Icon
                                            Text {
                                                text: modelData.is_done ? "✓" : "○"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: modelData.is_done ? "#3fb950" : "#58a6ff"
                                            }

                                            // Task ID
                                            Text {
                                                text: "#" + modelData.id
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: "#58a6ff"
                                            }

                                            // Task Title
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title || ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                color: modelData.is_done ? "#8b949e" : "#e6edf3"
                                                elide: Text.ElideRight
                                            }

                                            // Type Pill (Task vs Bug)
                                            Rectangle {
                                                implicitHeight: 16
                                                implicitWidth: tkTypeLabel.implicitWidth + 8
                                                radius: 8
                                                color: (modelData.type || "").toLowerCase().indexOf("bug") !== -1 ? "#3d1417" : "#161b22"
                                                border.color: (modelData.type || "").toLowerCase().indexOf("bug") !== -1 ? "#f85149" : "#30363d"
                                                Text {
                                                    id: tkTypeLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.type || "Task"
                                                    font.pixelSize: 9
                                                    color: (modelData.type || "").toLowerCase().indexOf("bug") !== -1 ? "#ff7b72" : "#8b949e"
                                                }
                                            }

                                            // State Pill
                                            Rectangle {
                                                implicitHeight: 16
                                                implicitWidth: tkStateLabel.implicitWidth + 8
                                                radius: 8
                                                color: modelData.is_done ? "#0d3525" : "#161b22"
                                                border.color: modelData.is_done ? "#3fb950" : "#30363d"
                                                Text {
                                                    id: tkStateLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.state || "Active"
                                                    font.pixelSize: 9
                                                    color: modelData.is_done ? "#3fb950" : "#d29922"
                                                }
                                            }

                                            // Task Sprint Move
                                            Rectangle {
                                                implicitHeight: 18
                                                implicitWidth: tkSprintText.implicitWidth + 8
                                                radius: 9
                                                color: "#21262d"
                                                border.color: tkMoveMa.containsMouse ? "#58a6ff" : "#30363d"
                                                Text {
                                                    id: tkSprintText
                                                    anchors.centerIn: parent
                                                    text: "🔄"
                                                    font.pixelSize: 9
                                                }
                                                ToolTip.visible: tkMoveMa.containsMouse
                                                ToolTip.text: "Reschedule task #" + modelData.id
                                                MouseArea {
                                                    id: tkMoveMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        workloadIterationPickerModal.openForWorkItem(
                                                            modelData.id,
                                                            modelData.title,
                                                            modelData.iteration_path || (root.selectedCell ? root.selectedCell.sprint_name : "")
                                                        );
                                                    }
                                                }
                                            }

                                            // Task Deadline
                                            Rectangle {
                                                implicitHeight: 18
                                                implicitWidth: tkDlText.implicitWidth + 8
                                                radius: 9
                                                property bool hasDate: (modelData.deadline_str || "") !== ""
                                                color: Qt.rgba(modelData.urgency_color.r, modelData.urgency_color.g, modelData.urgency_color.b, 0.15)
                                                border.color: tkDlMa.containsMouse ? "#58a6ff" : Qt.rgba(modelData.urgency_color.r, modelData.urgency_color.g, modelData.urgency_color.b, 0.4)
                                                Text {
                                                    id: tkDlText
                                                    anchors.centerIn: parent
                                                    text: parent.hasDate ? (modelData.urgency_badge || modelData.deadline_str) : "📅"
                                                    font.pixelSize: 9
                                                    color: modelData.urgency_color || "#8b949e"
                                                }
                                                ToolTip.visible: tkDlMa.containsMouse
                                                ToolTip.text: "Deadline: " + (modelData.deadline_str || "None") + "\n(Click to edit)"
                                                MouseArea {
                                                    id: tkDlMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        workloadDeadlineDialog.openForWorkItem(
                                                            modelData.id,
                                                            modelData.title,
                                                            modelData.deadline_str,
                                                            root.selectedCell ? root.selectedCell.sprint_name : ""
                                                        );
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: taskMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: (modelData.tfs_url || "") !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (backend && (modelData.tfs_url || "") !== "") {
                                                    backend.open_url(modelData.tfs_url)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Indicator when closed tasks in this container are hidden
                                Text {
                                    visible: root.hideClosedTasks && (modelData.completed_tasks_count || 0) > 0
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
        }
    }

    DeadlineEditorDialog {
        id: workloadDeadlineDialog
        onDeadlineUpdated: function(id, newDate, result) {
            root.refreshMatrix();
        }
    }

    IterationPickerModal {
        id: workloadIterationPickerModal
        onIterationUpdated: function(id, newIteration, result) {
            root.refreshMatrix();
        }
    }
}

