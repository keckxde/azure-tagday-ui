import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

            Item {
    id: shiftsTabRoot
    property var root: null

    readonly property string curReviewFilter: (root && root.shiftReviewFilter) ? root.shiftReviewFilter : "all"
    readonly property string curSourceFilter: (root && root.shiftSourceFilter) ? root.shiftSourceFilter : "all"
    readonly property bool curSprintOnly: !!(root && root.shiftSprintOnlyFilter)
    readonly property string curSearch: (root && root.shiftSearchQuery) ? root.shiftSearchQuery : ""

                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14

                    // Subheader & Action Toolbar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Sprint Rescheduling & Postponement Impact"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Text {
                                text: "Audit log of work item iteration moves, review policy approval workflow, and exportable reports"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Export & Bulk Action Buttons
                        Row {
                            spacing: 6

                            Button {
                                text: "⚡ Export Report (MD)"
                                enabled: backend ? !backend.isBusy : false
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                contentItem: Text { text: parent.text; font: parent.font; color: "#ffffff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle {
                                    implicitHeight: 28; implicitWidth: 145; radius: 6
                                    color: parent.enabled ? (parent.hovered ? "#388bfd" : "#1f6feb") : "#30363d"
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: "Generate exportable Markdown wiki report of sprint-to-sprint rescheduled items"
                                onClicked: {
                                    if (backend) backend.generate_rescheduling_report_async(shiftsTabRoot.curReviewFilter);
                                }
                            }

                            Button {
                                text: "📊 Export CSV"
                                enabled: backend ? !backend.isBusy : false
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                contentItem: Text { text: parent.text; font: parent.font; color: "#f0f6fc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle {
                                    implicitHeight: 28; implicitWidth: 95; radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: "Export sprint-to-sprint rescheduled items to CSV file"
                                onClicked: {
                                    if (backend) backend.generate_rescheduling_report_async(shiftsTabRoot.curReviewFilter);
                                }
                            }

                            Button {
                                text: "📑 Open Report"
                                font.pixelSize: 11
                                contentItem: Text { text: parent.text; font: parent.font; color: "#f0f6fc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle {
                                    implicitHeight: 28; implicitWidth: 100; radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: "Open RESCHEDULING_REPORT.md in system default editor"
                                onClicked: {
                                    if (backend) backend.open_rescheduling_report_markdown();
                                }
                            }

                            Button {
                                text: "✓ Accept All"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                contentItem: Text { text: parent.text; font: parent.font; color: "#3fb950"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle {
                                    implicitHeight: 28; implicitWidth: 95; radius: 6
                                    color: parent.hovered ? "#16281e" : "#0d1f16"
                                    border.color: "#238636"
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: "Acknowledge and mark all pending shift events as Accepted"
                                onClicked: {
                                    if (backend) backend.bulk_set_all_shifts_review_status("accepted");
                                }
                            }
                        }
                    }

                    // Filter Bar (Review Policy, Source, Sprint-Only Scope, Search)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Review Policy Filter
                        Row {
                            spacing: 4
                            Repeater {
                                model: [
                                    { label: "All Shifts", value: "all" },
                                    { label: "⏳ Pending (" + (backend && backend.shiftImpactMetrics ? (backend.shiftImpactMetrics.pending_shifts_count || 0) : 0) + ")", value: "pending" },
                                    { label: "✅ Accepted (" + (backend && backend.shiftImpactMetrics ? (backend.shiftImpactMetrics.accepted_shifts_count || 0) : 0) + ")", value: "accepted" }
                                ]
                                Button {
                                    text: modelData.label
                                    checkable: true
                                    checked: shiftsTabRoot.curReviewFilter === modelData.value
                                    font.pixelSize: 11
                                    font.weight: checked ? Font.DemiBold : Font.Normal
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: parent.checked ? "#ffffff" : (modelData.value === "pending" ? "#d29922" : (modelData.value === "accepted" ? "#3fb950" : "#8b949e"))
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: modelData.value === "all" ? 80 : 110
                                        radius: 6
                                        color: parent.checked ? (modelData.value === "accepted" ? "#238636" : (modelData.value === "pending" ? "#8250df" : "#1f6feb")) : (parent.hovered ? "#21262d" : "#161b22")
                                        border.color: parent.checked ? "#58a6ff" : "#30363d"
                                    }
                                    onClicked: {
                                        if (root) root.shiftReviewFilter = modelData.value;
                                    }
                                }
                            }
                        }

                        // Source Filter (All / GUI / TFS Sync)
                        Row {
                            spacing: 4
                            Repeater {
                                model: [
                                    { label: "All Sources", value: "all" },
                                    { label: "🖥️ GUI", value: "user_gui" },
                                    { label: "🔄 Sync", value: "tfs_sync" }
                                ]
                                Button {
                                    text: modelData.label
                                    checkable: true
                                    checked: shiftsTabRoot.curSourceFilter === modelData.value
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
                                        implicitHeight: 28
                                        implicitWidth: 80
                                        radius: 6
                                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                                        border.color: parent.checked ? "#388bfd" : "#30363d"
                                    }
                                    onClicked: {
                                        if (root) root.shiftSourceFilter = modelData.value;
                                    }
                                }
                            }
                        }

                        // Scope Toggle: Sprint-to-Sprint Only (ignore Backlog moves)
                        Button {
                            text: shiftsTabRoot.curSprintOnly ? "🏃 Sprints Only (Active)" : "📋 All Moves"
                            checkable: true
                            checked: shiftsTabRoot.curSprintOnly
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
                                implicitHeight: 28
                                implicitWidth: 120
                                radius: 6
                                color: parent.checked ? "#8250df" : (parent.hovered ? "#21262d" : "#161b22")
                                border.color: parent.checked ? "#a371f7" : "#30363d"
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: shiftsTabRoot.curSprintOnly ? "Showing sprint-to-sprint rescheduled items only (initial Backlog scheduling ignored)." : "Click to filter to sprint-to-sprint rescheduled items only."
                            onClicked: {
                                if (root) root.shiftSprintOnlyFilter = !root.shiftSprintOnlyFilter;
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Search Filter
                        SearchBar {
                            placeholder: "Search item #, title, sprint..."
                            onSearchUpdated: function(query) {
                                if (root) root.shiftSearchQuery = (query || "").toLowerCase();
                            }
                        }
                    }

                    // KPI Metrics Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Total Shift Events
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 65
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Text { text: "🔄"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "TOTAL SHIFTS"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: backend && backend.shiftImpactMetrics ? (backend.shiftImpactMetrics.total_shifts || 0).toString() : "0"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                    }
                                }
                            }
                        }

                        // Rescheduled Work Items
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 65
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Text { text: "📋"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "RESCHEDULED ITEMS"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: backend && backend.shiftImpactMetrics ? (backend.shiftImpactMetrics.total_shifted_items || 0).toString() : "0"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                }
                            }
                        }

                        // Review Policy Breakdown
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 65
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Text { text: "🛡️"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "REVIEW POLICY STATUS"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    RowLayout {
                                        spacing: 6
                                        Text {
                                            text: "⏳ " + (backend && backend.shiftImpactMetrics ? (backend.shiftImpactMetrics.pending_shifts_count || 0) : 0) + " Pending"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: (backend && backend.shiftImpactMetrics && backend.shiftImpactMetrics.pending_shifts_count > 0) ? "#d29922" : "#8b949e"
                                        }
                                        Text { text: "·"; color: "#30363d" }
                                        Text {
                                            text: "✅ " + (backend && backend.shiftImpactMetrics ? (backend.shiftImpactMetrics.accepted_shifts_count || 0) : 0) + " Accepted"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#3fb950"
                                        }
                                    }
                                }
                            }
                        }

                        // Net Delay Weeks
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 65
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Text { text: "⏳"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "NET DELAY / POSTPONED"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        property int netDelay: backend && backend.shiftImpactMetrics ? (backend.shiftImpactMetrics.net_delay_weeks || 0) : 0
                                        text: (netDelay > 0 ? ("+" + netDelay) : netDelay.toString()) + " Weeks"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: netDelay > 0 ? "#f85149" : "#3fb950"
                                    }
                                }
                            }
                        }

                        // Most Delayed Item
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 65
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Text { text: "⚠️"; font.pixelSize: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "MOST POSTPONED ITEM"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        property var mdi: backend && backend.shiftImpactMetrics ? backend.shiftImpactMetrics.most_delayed_item : null
                                        text: mdi ? ("#" + mdi.id + " (+" + mdi.total_delayed_weeks + "w)") : "None"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: "#d29922"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    // Main Content Split: Top Delayed Items (Left) + Shift Events Audit Log (Right)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 14

                        // Left Box: Top Rescheduled & Postponed Work Items
                        Rectangle {
                            Layout.preferredWidth: 440
                            Layout.fillHeight: true
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "🎯 Postponed User Stories & Bugs"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: "Click item to view in ADO"
                                        font.pixelSize: 10
                                        color: "#58a6ff"
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                                ListView {
                                    id: topShiftedList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 6

                                    readonly property var filteredItems: {
                                        if (!backend || !backend.shiftImpactMetrics || !backend.shiftImpactMetrics.top_delayed_items)
                                            return [];
                                        var list = backend.shiftImpactMetrics.top_delayed_items;

                                        // Review Policy Filter
                                        var rf = shiftsTabRoot.curReviewFilter;
                                        if (rf === "pending") {
                                            list = list.filter(function(it) {
                                                return (it.pending_count || 0) > 0 || it.review_status === "pending";
                                            });
                                        } else if (rf === "accepted") {
                                            list = list.filter(function(it) {
                                                return (it.pending_count || 0) === 0 || it.review_status === "accepted";
                                            });
                                        }

                                        // Search Filter
                                        var q = shiftsTabRoot.curSearch;
                                        if (!q) return list;
                                        return list.filter(function(it) {
                                            return (it.id && it.id.toString().indexOf(q) !== -1) ||
                                                   (it.title && it.title.toLowerCase().indexOf(q) !== -1) ||
                                                   (it.assigned_to && it.assigned_to.toLowerCase().indexOf(q) !== -1) ||
                                                   (it.type && it.type.toLowerCase().indexOf(q) !== -1);
                                        });
                                    }

                                    model: filteredItems

                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: Rectangle {
                                        id: delayedCard
                                        width: topShiftedList.width - 6
                                        height: delayedItemCol.implicitHeight + 14
                                        radius: 6
                                        color: delayedCardMa.containsMouse ? "#1c2128" : "#0d1117"
                                        border.color: delayedCardMa.containsMouse ? "#58a6ff" : (modelData.review_status === "accepted" ? "#238636" : "#30363d")
                                        border.width: 1

                                        MouseArea {
                                            id: delayedCardMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (backend && modelData.id) {
                                                    backend.open_work_item_in_browser(modelData.id);
                                                }
                                            }
                                        }

                                        ToolTip.visible: delayedCardMa.containsMouse
                                        ToolTip.text: "Click to open Work Item #" + modelData.id + " in Azure DevOps / TFS browser"

                                        ColumnLayout {
                                            id: delayedItemCol
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Text {
                                                    text: "#" + modelData.id
                                                    font.family: "Consolas, monospace"
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    color: "#58a6ff"
                                                }

                                                Rectangle {
                                                    implicitHeight: 16
                                                    implicitWidth: dTypeLabel.implicitWidth + 8
                                                    radius: 8
                                                    color: "#161b22"
                                                    border.color: "#30363d"
                                                    Text {
                                                        id: dTypeLabel
                                                        anchors.centerIn: parent
                                                        text: modelData.type || "Story"
                                                        font.pixelSize: 9
                                                        color: "#8b949e"
                                                    }
                                                }

                                                // Review Status Badge
                                                Rectangle {
                                                    implicitHeight: 16
                                                    implicitWidth: dRevText.implicitWidth + 8
                                                    radius: 8
                                                    color: modelData.review_status === "accepted" ? "#0d3525" : "#3d2200"
                                                    border.color: modelData.review_status === "accepted" ? "#238636" : "#d29922"
                                                    Text {
                                                        id: dRevText
                                                        anchors.centerIn: parent
                                                        text: modelData.review_status === "accepted" ? "✅ Accepted" : "⏳ Pending"
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        color: modelData.review_status === "accepted" ? "#3fb950" : "#d29922"
                                                    }
                                                }

                                                Item { Layout.fillWidth: true }

                                                // Delay Badge
                                                Rectangle {
                                                    implicitHeight: 18
                                                    implicitWidth: delayPillText.implicitWidth + 10
                                                    radius: 9
                                                    color: modelData.total_delayed_weeks > 0 ? "#3d2200" : "#0d3525"
                                                    border.color: modelData.total_delayed_weeks > 0 ? "#d29922" : "#3fb950"
                                                    border.width: 1
                                                    Text {
                                                        id: delayPillText
                                                        anchors.centerIn: parent
                                                        text: (modelData.total_delayed_weeks > 0 ? ("+" + modelData.total_delayed_weeks + "w") : (modelData.total_delayed_weeks + "w")) + " (" + modelData.shift_count + " moves)"
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        color: modelData.total_delayed_weeks > 0 ? "#f2cc60" : "#3fb950"
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title || ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                color: "#f0f6fc"
                                                elide: Text.ElideRight
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Text {
                                                    text: "👤 " + (modelData.assigned_to || "Unassigned")
                                                    font.pixelSize: 10
                                                    color: "#8b949e"
                                                }

                                                Item { Layout.fillWidth: true }

                                                // Review Policy Action Button (Accept / Reset)
                                                Button {
                                                    text: modelData.review_status === "accepted" ? "↩ Reset" : "✓ Accept"
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: modelData.review_status === "accepted" ? "#8b949e" : "#3fb950"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 20
                                                        implicitWidth: 60
                                                        radius: 4
                                                        color: parent.hovered ? "#30363d" : "#21262d"
                                                        border.color: modelData.review_status === "accepted" ? "#30363d" : "#238636"
                                                    }
                                                    onClicked: {
                                                        var targetStatus = modelData.review_status === "accepted" ? "pending" : "accepted";
                                                        if (backend) backend.set_work_item_shifts_review_status(modelData.id, targetStatus);
                                                    }
                                                }

                                                // Direct ADO browser button
                                                Button {
                                                    text: "🔗 ADO"
                                                    font.pixelSize: 9
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: "#58a6ff"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 20
                                                        implicitWidth: 46
                                                        radius: 4
                                                        color: parent.hovered ? "#1f6feb" : "#161b22"
                                                        border.color: "#388bfd"
                                                    }
                                                    onClicked: {
                                                        if (backend) backend.open_work_item_in_browser(modelData.id);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Right Box: Chronological Shift Event Stream
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#161b22"
                            radius: 8
                            border.color: "#30363d"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "📜 Rescheduling Audit Log"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: "Click entry to view original task in ADO"
                                        font.pixelSize: 10
                                        color: "#58a6ff"
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                                ListView {
                                    id: shiftEventsList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 6

                                    readonly property var filteredEvents: {
                                        if (!backend || !backend.iterationShifts) return [];
                                        var list = backend.iterationShifts;

                                        // Source Filter
                                        var sf = shiftsTabRoot.curSourceFilter;
                                        if (sf !== "all") {
                                            list = list.filter(function(ev) {
                                                return ev.source === sf;
                                            });
                                        }

                                        // Review Policy Filter
                                        var rf = shiftsTabRoot.curReviewFilter;
                                        if (rf !== "all") {
                                            list = list.filter(function(ev) {
                                                return (ev.review_status || "pending") === rf;
                                            });
                                        }

                                        // Sprint-to-Sprint Only Filter (ignore initial moves from Backlog/root)
                                        if (shiftsTabRoot.curSprintOnly) {
                                            list = list.filter(function(ev) {
                                                var os = (ev.old_sprint || ev.old_iteration || "").toLowerCase();
                                                return os !== "" && os !== "none" && os !== "backlog" && os !== "unassigned";
                                            });
                                        }

                                        // Search Query Filter
                                        var q = shiftsTabRoot.curSearch;
                                        if (!q) return list;
                                        return list.filter(function(ev) {
                                            return (ev.work_item_id && ev.work_item_id.toString().indexOf(q) !== -1) ||
                                                   (ev.title && ev.title.toLowerCase().indexOf(q) !== -1) ||
                                                   (ev.old_sprint && ev.old_sprint.toLowerCase().indexOf(q) !== -1) ||
                                                   (ev.new_sprint && ev.new_sprint.toLowerCase().indexOf(q) !== -1) ||
                                                   (ev.assigned_to && ev.assigned_to.toLowerCase().indexOf(q) !== -1);
                                        });
                                    }

                                    model: filteredEvents

                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: Rectangle {
                                        id: eventCard
                                        width: shiftEventsList.width - 6
                                        height: eventCol.implicitHeight + 14
                                        radius: 6
                                        color: eventCardMa.containsMouse ? "#1c2128" : "#0d1117"
                                        border.color: eventCardMa.containsMouse ? "#58a6ff" : (modelData.review_status === "accepted" ? "#238636" : "#30363d")
                                        border.width: 1

                                        MouseArea {
                                            id: eventCardMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (backend && modelData.work_item_id) {
                                                    backend.open_work_item_in_browser(modelData.work_item_id);
                                                }
                                            }
                                        }

                                        ToolTip.visible: eventCardMa.containsMouse
                                        ToolTip.text: "Click to open Work Item #" + modelData.work_item_id + " in Azure DevOps / TFS browser"

                                        ColumnLayout {
                                            id: eventCol
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    text: "#" + modelData.work_item_id
                                                    font.family: "Consolas, monospace"
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    color: "#58a6ff"
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.title || ""
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 11
                                                    color: "#f0f6fc"
                                                    elide: Text.ElideRight
                                                }

                                                // Source Badge
                                                Rectangle {
                                                    implicitHeight: 18
                                                    implicitWidth: srcText.implicitWidth + 8
                                                    radius: 9
                                                    color: modelData.source === "user_gui" ? "#0d2344" : "#21262d"
                                                    border.color: modelData.source === "user_gui" ? "#1f6feb" : "#30363d"
                                                    Text {
                                                        id: srcText
                                                        anchors.centerIn: parent
                                                        text: modelData.source === "user_gui" ? "🖥️ GUI" : "🔄 Sync"
                                                        font.pixelSize: 9
                                                        color: modelData.source === "user_gui" ? "#58a6ff" : "#8b949e"
                                                    }
                                                }

                                                // Review Status Badge
                                                Rectangle {
                                                    implicitHeight: 18
                                                    implicitWidth: evRevBadge.implicitWidth + 8
                                                    radius: 9
                                                    color: modelData.review_status === "accepted" ? "#0d3525" : "#3d2200"
                                                    border.color: modelData.review_status === "accepted" ? "#238636" : "#d29922"
                                                    Text {
                                                        id: evRevBadge
                                                        anchors.centerIn: parent
                                                        text: modelData.review_status === "accepted" ? "✅ Accepted" : "⏳ Pending"
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        color: modelData.review_status === "accepted" ? "#3fb950" : "#d29922"
                                                    }
                                                }

                                                // Delta Badge
                                                Rectangle {
                                                    implicitHeight: 18
                                                    implicitWidth: evDeltaText.implicitWidth + 8
                                                    radius: 9
                                                    color: modelData.delta_weeks > 0 ? "#3d2200" : (modelData.delta_weeks < 0 ? "#0d3525" : "#21262d")
                                                    border.color: modelData.delta_weeks > 0 ? "#d29922" : (modelData.delta_weeks < 0 ? "#3fb950" : "#30363d")
                                                    border.width: 1
                                                    Text {
                                                        id: evDeltaText
                                                        anchors.centerIn: parent
                                                        text: modelData.delta_weeks > 0 ? ("+" + modelData.delta_weeks + "w") : (modelData.delta_weeks + "w")
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        color: modelData.delta_weeks > 0 ? "#f2cc60" : (modelData.delta_weeks < 0 ? "#3fb950" : "#8b949e")
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Text {
                                                    text: "Sprint: " + (modelData.old_sprint || "None") + "  ➔  " + (modelData.new_sprint || "None")
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    color: "#58a6ff"
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: "👤 " + (modelData.assigned_to || "Unassigned")
                                                    font.pixelSize: 10
                                                    color: "#8b949e"
                                                }

                                                Text {
                                                    text: "•"
                                                    font.pixelSize: 10
                                                    color: "#30363d"
                                                }

                                                Text {
                                                    text: (modelData.recorded_at || "").replace("T", " ").substring(0, 19)
                                                    font.pixelSize: 9
                                                    color: "#8b949e"
                                                }

                                                // Review Status Toggle Action Button
                                                Button {
                                                    text: modelData.review_status === "accepted" ? "↩ Reset" : "✓ Accept"
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: modelData.review_status === "accepted" ? "#8b949e" : "#3fb950"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 20
                                                        implicitWidth: 60
                                                        radius: 4
                                                        color: parent.hovered ? "#30363d" : "#21262d"
                                                        border.color: modelData.review_status === "accepted" ? "#30363d" : "#238636"
                                                    }
                                                    onClicked: {
                                                        var targetStatus = modelData.review_status === "accepted" ? "pending" : "accepted";
                                                        if (backend) backend.set_shift_review_status(modelData.id, targetStatus);
                                                    }
                                                }

                                                // ADO Link Button
                                                Button {
                                                    text: "🔗 ADO"
                                                    font.pixelSize: 9
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: "#58a6ff"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 20
                                                        implicitWidth: 46
                                                        radius: 4
                                                        color: parent.hovered ? "#1f6feb" : "#161b22"
                                                        border.color: "#388bfd"
                                                    }
                                                    onClicked: {
                                                        if (backend && modelData.work_item_id) {
                                                            backend.open_work_item_in_browser(modelData.work_item_id);
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
                }
            }
