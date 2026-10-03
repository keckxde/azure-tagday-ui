import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

            Item {
    property var root: null

                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14

                    // Sprint Selector & Actions Bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 54
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Text {
                                text: "🎯 Target Sprint:"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: "#8b949e"
                            }

                            ComboBox {
                                id: sprintExplorerCombo
                                implicitWidth: 200
                                implicitHeight: 32
                                font.pixelSize: 12
                                model: (backend && backend.availableSprintList) ? backend.availableSprintList : []
                                currentIndex: {
                                    if (!backend || !backend.availableSprintList || backend.availableSprintList.length === 0) return 0;
                                    var target = root.selectedSprintReport || root.getDefaultSprint();
                                    var idx = backend.availableSprintList.indexOf(target);
                                    return idx >= 0 ? idx : 0;
                                }
                                background: Rectangle {
                                    color: "#0d1117"
                                    radius: 6
                                    border.color: "#388bfd"
                                }
                                contentItem: Text {
                                    leftPadding: 10
                                    text: sprintExplorerCombo.currentText ? ("🎯 " + sprintExplorerCombo.currentText) : "Select Sprint..."
                                    font: sprintExplorerCombo.font
                                    color: "#58a6ff"
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onActivated: function(index) {
                                    var s = backend.availableSprintList[index];
                                    root.selectedSprintReport = s;
                                    root.sprintReportData = backend.get_sprint_report_data(s);
                                }
                            }

                            // Timeframe badge
                            Rectangle {
                                implicitHeight: 24
                                implicitWidth: tfLabel.implicitWidth + 16
                                radius: 12
                                color: "#0d2344"
                                border.color: "#1f6feb"
                                visible: root.sprintReportData && root.sprintReportData.start_date !== "N/A"
                                Text {
                                    id: tfLabel
                                    anchors.centerIn: parent
                                    text: "📅 " + (root.sprintReportData ? (root.sprintReportData.start_date + " → " + root.sprintReportData.end_date) : "")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#58a6ff"
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Action buttons
                            Button {
                                text: "⚡ Generate Markdown"
                                enabled: backend ? !backend.isBusy : false
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                contentItem: Text { text: parent.text; font: parent.font; color: "#ffffff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle {
                                    implicitHeight: 32; implicitWidth: 155; radius: 6
                                    color: parent.enabled ? (parent.hovered ? "#388bfd" : "#1f6feb") : "#30363d"
                                }
                                onClicked: {
                                    if (backend && root.selectedSprintReport) {
                                        backend.generate_sprint_report_async(root.selectedSprintReport);
                                    }
                                }
                            }

                            Button {
                                text: "📊 Export CSV"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                contentItem: Text { text: parent.text; font: parent.font; color: "#f0f6fc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle {
                                    implicitHeight: 32; implicitWidth: 110; radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                }
                                onClicked: {
                                    if (backend && root.selectedSprintReport) {
                                        backend.generate_sprint_report_async(root.selectedSprintReport);
                                    }
                                }
                            }

                            Button {
                                text: "📑 Open File"
                                font.pixelSize: 11
                                contentItem: Text { text: parent.text; font: parent.font; color: "#f0f6fc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle {
                                    implicitHeight: 32; implicitWidth: 95; radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                }
                                onClicked: {
                                    if (backend && root.selectedSprintReport) {
                                        backend.open_sprint_report_file(root.selectedSprintReport);
                                    }
                                }
                            }
                        }
                    }

                    // Sprint KPI Metric Cards
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Total Planned Items
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                Text { text: "📦"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "TOTAL ITEMS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: root.sprintReportData ? (root.sprintReportData.total_items || 0).toString() : "0"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 17
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                    }
                                }
                            }
                        }

                        // User Stories & Requirements
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                Text { text: "🎯"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "STORIES & REQS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: root.sprintReportData ? (root.sprintReportData.stories ? root.sprintReportData.stories.length : 0).toString() : "0"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 17
                                        font.weight: Font.Bold
                                        color: "#3fb950"
                                    }
                                }
                            }
                        }

                        // Bugs & Defects
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                Text { text: "🐛"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "BUGS / DEFECTS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: root.sprintReportData ? (root.sprintReportData.bugs ? root.sprintReportData.bugs.length : 0).toString() : "0"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 17
                                        font.weight: Font.Bold
                                        color: "#f85149"
                                    }
                                }
                            }
                        }

                        // Tasks
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                Text { text: "🛠️"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "TASKS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: root.sprintReportData ? (root.sprintReportData.tasks ? root.sprintReportData.tasks.length : 0).toString() : "0"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 17
                                        font.weight: Font.Bold
                                        color: "#d29922"
                                    }
                                }
                            }
                        }

                        // Velocity & Completion Rate
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                Text { text: "⚡"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "COMPLETION RATE"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: (root.sprintReportData ? (root.sprintReportData.completion_rate || 0) : 0) + "%"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 17
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                }
                            }
                        }
                    }

                    // Filter Tab Buttons (Stories, Bugs, Tasks, Assignees)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "All Items", count: root.sprintReportData ? root.sprintReportData.total_items : 0 },
                                { label: "🎯 Stories & Reqs", count: root.sprintReportData && root.sprintReportData.stories ? root.sprintReportData.stories.length : 0 },
                                { label: "🐛 Bugs & Defects", count: root.sprintReportData && root.sprintReportData.bugs ? root.sprintReportData.bugs.length : 0 },
                                { label: "🛠️ Tasks", count: root.sprintReportData && root.sprintReportData.tasks ? root.sprintReportData.tasks.length : 0 },
                                { label: "👥 Team Workload", count: root.sprintReportData && root.sprintReportData.assignee_stats ? Object.keys(root.sprintReportData.assignee_stats).length : 0 }
                            ]

                            Button {
                                text: modelData.label + " (" + modelData.count + ")"
                                checkable: true
                                checked: root.sprintFilterType === index
                                font.pixelSize: 11
                                font.weight: checked ? Font.DemiBold : Font.Normal
                                contentItem: Text {
                                    text: parent.text; font: parent.font
                                    color: parent.checked ? "#ffffff" : "#8b949e"
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28; implicitWidth: 145; radius: 14
                                    color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                                    border.color: parent.checked ? "#388bfd" : "#30363d"
                                }
                                onClicked: root.sprintFilterType = index
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // Main Work Item / Assignee Table Area
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#0d1117"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1
                        clip: true

                        // Content if viewing Work Items (0, 1, 2, 3)
                        ListView {
                            id: sprintItemsListView
                            anchors.fill: parent
                            anchors.margins: 10
                            clip: true
                            spacing: 4
                            visible: root.sprintFilterType !== 4

                            model: {
                                if (!root.sprintReportData) return [];
                                if (root.sprintFilterType === 1) return root.sprintReportData.stories || [];
                                if (root.sprintFilterType === 2) return root.sprintReportData.bugs || [];
                                if (root.sprintFilterType === 3) return root.sprintReportData.tasks || [];
                                return (root.sprintReportData.stories || []).concat(root.sprintReportData.bugs || []).concat(root.sprintReportData.tasks || []).concat(root.sprintReportData.features || []).concat(root.sprintReportData.others || []);
                            }

                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            delegate: Rectangle {
                                width: sprintItemsListView.width - 6
                                height: 48
                                radius: 6
                                color: sprintRowMa.containsMouse ? "#1c2128" : "#161b22"
                                border.color: {
                                    if (modelData.urgency && modelData.urgency.status === "overdue") return "#da3633";
                                    if (sprintRowMa.containsMouse) return "#388bfd";
                                    return "#21262d";
                                }
                                border.width: 1

                                MouseArea {
                                    id: sprintRowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var sName = modelData.iteration_name || modelData.iteration_path || root.selectedSprintReport || "";
                                        if (backend) {
                                            backend.open_sprint_in_browser(modelData.id || sName, sName);
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    // ID (Click opens Work Item Editor)
                                    Rectangle {
                                        implicitHeight: 20
                                        implicitWidth: rptIdText.implicitWidth + 8
                                        radius: 4
                                        color: rptIdMa.containsMouse ? "#1f6feb" : "#161b22"
                                        border.color: rptIdMa.containsMouse ? "#58a6ff" : "#30363d"
                                        border.width: 1

                                        Text {
                                            id: rptIdText
                                            anchors.centerIn: parent
                                            text: "#" + modelData.id
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: rptIdMa.containsMouse ? "#ffffff" : "#58a6ff"
                                        }
                                        ToolTip.visible: rptIdMa.containsMouse
                                        ToolTip.text: "Click to open Work Item Editor in TFS (#" + modelData.id + ")"
                                        MouseArea {
                                            id: rptIdMa
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

                                    // Type Pill
                                    Rectangle {
                                        Layout.preferredWidth: 88
                                        height: 20
                                        radius: 10
                                        color: "#0d2344"
                                        border.color: "#1f6feb"
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.wi_type || modelData.type || "Task"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: "#58a6ff"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Title (Click opens Sprint View)
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || ""
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
                                        ToolTip.visible: sprintRowMa.containsMouse
                                        ToolTip.text: (modelData.title || "") + "\n• Left-Click: Open Sprint Taskboard in TFS\n• Click #" + modelData.id + ": Open Work Item Editor"
                                    }

                                    // State
                                    Rectangle {
                                        Layout.preferredWidth: 84
                                        height: 20
                                        radius: 10
                                        color: modelData.is_done ? "#0d3525" : "#161b22"
                                        border.color: modelData.is_done ? "#3fb950" : "#30363d"
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.wi_state || modelData.state || "Active"
                                            font.pixelSize: 10
                                            color: modelData.is_done ? "#3fb950" : "#d29922"
                                        }
                                    }

                                    // Deadline Badge
                                    Rectangle {
                                        id: rptDlBadge
                                        Layout.preferredWidth: 110
                                        height: 20
                                        radius: 10
                                        property var urg: (modelData && modelData.urgency) ? modelData.urgency : {}
                                        visible: (modelData && modelData.deadline_str || "") !== ""
                                        color: Qt.rgba(139 / 255, 148 / 255, 158 / 255, 0.15)
                                        border.color: (rptDlBadge.urg && rptDlBadge.urg.badge_color) ? rptDlBadge.urg.badge_color : "#30363d"
                                        Text {
                                            anchors.centerIn: parent
                                            text: (rptDlBadge.urg && rptDlBadge.urg.badge_text) ? rptDlBadge.urg.badge_text : (modelData.deadline_str || "—")
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: (rptDlBadge.urg && rptDlBadge.urg.badge_color) ? rptDlBadge.urg.badge_color : "#8b949e"
                                        }
                                    }

                                    // Assignee
                                    Text {
                                        text: modelData.assignee || modelData.assigned_to || "Unassigned"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                        Layout.preferredWidth: 110
                                        elide: Text.ElideRight
                                    }

                                    // Quick Sprint Taskboard Button
                                    Button {
                                        text: "🏃 Sprint"
                                        font.pixelSize: 10
                                        Layout.preferredWidth: 62
                                        contentItem: Text { text: parent.text; font: parent.font; color: "#79c0ff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { implicitHeight: 22; radius: 4; color: parent.hovered ? "#1f6feb" : "#16243b"; border.color: "#1f6feb" }
                                        ToolTip.visible: hovered
                                        ToolTip.text: "Open Sprint Taskboard in TFS Browser"
                                        onClicked: {
                                            var sName = modelData.iteration_name || modelData.iteration_path || root.selectedSprintReport || "";
                                            if (backend) {
                                                backend.open_sprint_in_browser(modelData.id || sName, sName);
                                            }
                                        }
                                    }

                                    // Quick Work Item Editor Button
                                    Button {
                                        text: "📝 Edit"
                                        font.pixelSize: 10
                                        Layout.preferredWidth: 50
                                        contentItem: Text { text: parent.text; font: parent.font; color: "#7ee787"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { implicitHeight: 22; radius: 4; color: parent.hovered ? "#238636" : "#0d3525"; border.color: "#3fb950" }
                                        ToolTip.visible: hovered
                                        ToolTip.text: "Open Work Item Editor in TFS (#" + modelData.id + ")"
                                        onClicked: {
                                            if (backend) {
                                                backend.open_work_item_in_browser(modelData.id);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Content if viewing Team Workload (4)
                        ListView {
                            id: sprintAssigneeListView
                            anchors.fill: parent
                            anchors.margins: 10
                            clip: true
                            spacing: 6
                            visible: root.sprintFilterType === 4

                            model: {
                                if (!root.sprintReportData || !root.sprintReportData.assignee_stats) return [];
                                var stats = root.sprintReportData.assignee_stats;
                                var res = [];
                                for (var k in stats) {
                                    res.push({
                                        name: k,
                                        total: stats[k].total || 0,
                                        closed: stats[k].closed || 0,
                                        active: stats[k].active || 0,
                                        stories: stats[k].stories || 0,
                                        bugs: stats[k].bugs || 0,
                                        tasks: stats[k].tasks || 0,
                                        rate: (stats[k].total > 0 ? Math.round(stats[k].closed / stats[k].total * 100) : 0)
                                    });
                                }
                                return res.sort(function(a, b) { return b.total - a.total; });
                            }

                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            delegate: Rectangle {
                                width: sprintAssigneeListView.width - 6
                                height: 56
                                radius: 6
                                color: "#161b22"
                                border.color: "#30363d"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    spacing: 14

                                    // Member Avatar & Name
                                    RowLayout {
                                        Layout.preferredWidth: 200
                                        spacing: 10
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: modelData.name === "Unassigned" ? "#30363d" : "#1f6feb"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.name.substring(0, 2).toUpperCase()
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: "#ffffff"
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            color: "#f0f6fc"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Metric breakdown pills
                                    Row {
                                        Layout.preferredWidth: 280
                                        spacing: 8
                                        Rectangle {
                                            implicitHeight: 22; implicitWidth: stText.implicitWidth + 14; radius: 11; color: "#0d2344"; border.color: "#1f6feb"
                                            Text { id: stText; anchors.centerIn: parent; text: "🎯 " + modelData.stories + " Stories"; font.pixelSize: 10; color: "#58a6ff" }
                                        }
                                        Rectangle {
                                            implicitHeight: 22; implicitWidth: bgText.implicitWidth + 14; radius: 11; color: "#2d1517"; border.color: "#f85149"
                                            Text { id: bgText; anchors.centerIn: parent; text: "🐛 " + modelData.bugs + " Bugs"; font.pixelSize: 10; color: "#ff7b72" }
                                        }
                                        Rectangle {
                                            implicitHeight: 22; implicitWidth: tkText.implicitWidth + 14; radius: 11; color: "#271c0d"; border.color: "#d29922"
                                            Text { id: tkText; anchors.centerIn: parent; text: "🛠️ " + modelData.tasks + " Tasks"; font.pixelSize: 10; color: "#e3b341" }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Completion Progress Bar
                                    ColumnLayout {
                                        Layout.preferredWidth: 130
                                        spacing: 3
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: modelData.closed + " / " + modelData.total + " closed"; font.pixelSize: 10; color: "#8b949e" }
                                            Item { Layout.fillWidth: true }
                                            Text { text: modelData.rate + "%"; font.pixelSize: 10; font.weight: Font.Bold; color: "#3fb950" }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 6
                                            radius: 3
                                            color: "#21262d"
                                            Rectangle {
                                                width: parent.width * (modelData.rate / 100)
                                                height: parent.height
                                                radius: 3
                                                color: "#3fb950"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
