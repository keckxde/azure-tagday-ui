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

            Item { width: 8 }

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

                    Text {
                        text: "Sprint: " + (root.selectedCell ? root.selectedCell.sprint_name : "") + " (" + (root.selectedCell ? root.selectedCell.total_count : 0) + " items)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#58a6ff"
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

            // Items List
            ListView {
                id: drawerItemsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8

                model: root.selectedCell ? (root.selectedCell.items || []) : []

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    width: drawerItemsList.width - 6
                    height: itemCol.implicitHeight + 16
                    radius: 6
                    color: itemBoxMa.containsMouse ? "#21262d" : "#0d1117"
                    border.color: {
                        if (modelData.urgency_status === "overdue") return "#f85149"
                        if (itemBoxMa.containsMouse) return "#388bfd"
                        return "#30363d"
                    }
                    border.width: 1

                    MouseArea {
                        id: itemBoxMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: (modelData.tfs_url || "") !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (backend && (modelData.tfs_url || "") !== "") {
                                backend.open_url(modelData.tfs_url)
                            }
                        }
                    }

                    ColumnLayout {
                        id: itemCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "#" + modelData.id
                                font.family: "Consolas, monospace"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#58a6ff"
                            }

                            // Type badge
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: dtLabel.implicitWidth + 12
                                radius: 9
                                color: "#161b22"
                                border.color: "#30363d"
                                Text {
                                    id: dtLabel
                                    anchors.centerIn: parent
                                    text: modelData.type || "Task"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                }
                            }

                            // State badge
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: dsLabel.implicitWidth + 12
                                radius: 9
                                color: modelData.is_done ? "#0d3525" : "#161b22"
                                border.color: modelData.is_done ? "#3fb950" : "#30363d"
                                Text {
                                    id: dsLabel
                                    anchors.centerIn: parent
                                    text: modelData.state || "Active"
                                    font.pixelSize: 10
                                    color: modelData.is_done ? "#3fb950" : "#d29922"
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Deadline Pill
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: ddLabel.implicitWidth + 12
                                radius: 9
                                visible: (modelData.deadline_str || "") !== ""
                                color: Qt.rgba(modelData.urgency_color.r, modelData.urgency_color.g, modelData.urgency_color.b, 0.15)
                                border.color: Qt.rgba(modelData.urgency_color.r, modelData.urgency_color.g, modelData.urgency_color.b, 0.5)
                                Text {
                                    id: ddLabel
                                    anchors.centerIn: parent
                                    text: modelData.urgency_badge || modelData.deadline_str
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: modelData.urgency_color || "#8b949e"
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.title || ""
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#f0f6fc"
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
