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
    property string filterLevel1: "ALL"
    property string filterLevel2: "ALL"
    property string filterMilestone: "ALL" // "ALL", "PLANNED", "UNPLANNED", or specific milestone name
    property bool prio1Only: false
    property bool groupedOnly: false
    property bool overdueOnly: false
    property real drawerWidth: 420
    property int historyOffset: 0  // 0 = current window, N = N sprints back into history
    property var level1List: ["ALL"]
    property var level2List: ["ALL"]
    property var milestonesList: ["ALL"]

    // Horizontal Matrix Scrolling Properties
    property real matrixContentX: 0
    property int matrixSprintCount: root.matrixData && root.matrixData.sprint_columns ? root.matrixData.sprint_columns.length : 0
    property real minSprintColWidth: 175
    property real teamMemberColWidth: 180
    property real totalColWidth: 80
    property int matrixRowHeight: 72
    property real sprintViewportWidth: Math.max(100, (matrixTableContainer.width - root.teamMemberColWidth - root.totalColWidth))
    property real sprintColWidth: Math.max(root.minSprintColWidth, root.matrixSprintCount > 0 ? (root.sprintViewportWidth / root.matrixSprintCount) : root.minSprintColWidth)
    property real totalSprintContentWidth: root.matrixSprintCount * root.sprintColWidth
    property real maxMatrixScrollX: Math.max(0, root.totalSprintContentWidth - root.sprintViewportWidth)

    onMaxMatrixScrollXChanged: {
        if (matrixContentX > maxMatrixScrollX) {
            matrixContentX = maxMatrixScrollX;
        }
    }

    function jumpToCurrentWeek() {
        if (root.historyOffset !== 0) {
            root.historyOffset = 0;
        }
        if (root.matrixData && root.matrixData.current_sprint_index >= 0) {
            var idx = root.matrixData.current_sprint_index;
            var targetX = Math.max(0, Math.min(root.maxMatrixScrollX, (idx * root.sprintColWidth) - (root.sprintViewportWidth - root.sprintColWidth) / 2));
            root.matrixContentX = targetX;
        }
    }

    function refreshHierarchyLists() {
        if (!backend) return;
        var l1 = backend.workItemLevel1List || [];
        level1List = ["ALL"].concat(l1).concat(["[ WITHOUT [<NR>] SYNTAX ]", "UNGROUPED"]);
        var l2 = backend.workItemLevel2List || [];
        level2List = ["ALL"].concat(l2).concat(["[ WITHOUT [<NR>] SYNTAX ]", "UNGROUPED"]);
        var ms = backend.workItemMilestones || [];
        milestonesList = ["ALL", "PLANNED", "UNPLANNED"].concat(ms);
    }

    function getFilteredContainers(containers) {
        if (!containers) return [];
        var res = [];
        for (var i = 0; i < containers.length; i++) {
            var c = containers[i];

            // Level 1 Sub-System filter
            if (root.filterLevel1 !== "ALL") {
                var f1 = (root.filterLevel1 || "").toUpperCase();
                if (f1 === "UNGROUPED" || f1 === "[ UNGROUPED ]" || f1.indexOf("WITHOUT") !== -1 || f1.indexOf("NO_PBS") !== -1 || f1.indexOf("NO PBS") !== -1 || f1.indexOf("!PBS") !== -1 || f1 === "NON_PBS") {
                    if (c.level1_pbs && c.level1_pbs !== "") continue;
                } else {
                    var l1Target = root.filterLevel1.toLowerCase();
                    var l1Disp = (c.level1_display || "").toLowerCase();
                    var l1Title = (c.level1_title || "").toLowerCase();
                    var l1Pbs = (c.level1_pbs || "").toLowerCase();
                    var l1Name = (c.level1_name || "").toLowerCase();
                    if (l1Disp.indexOf(l1Target) === -1 && l1Title.indexOf(l1Target) === -1 && l1Pbs.indexOf(l1Target) === -1 && l1Name.indexOf(l1Target) === -1) {
                        continue;
                    }
                }
            }

            // Level 2 Component filter
            if (root.filterLevel2 !== "ALL") {
                var f2 = (root.filterLevel2 || "").toUpperCase();
                if (f2 === "UNGROUPED" || f2 === "[ UNGROUPED ]" || f2.indexOf("WITHOUT") !== -1 || f2.indexOf("NO_PBS") !== -1 || f2.indexOf("NO PBS") !== -1 || f2.indexOf("!PBS") !== -1 || f2 === "NON_PBS") {
                    if (c.level2_pbs && c.level2_pbs !== "") continue;
                } else {
                    var l2Target = root.filterLevel2.toLowerCase();
                    var l2Disp = (c.level2_display || "").toLowerCase();
                    var l2Title = (c.level2_title || "").toLowerCase();
                    var l2Pbs = (c.level2_pbs || "").toLowerCase();
                    var l2Name = (c.level2_name || "").toLowerCase();
                    if (l2Disp.indexOf(l2Target) === -1 && l2Title.indexOf(l2Target) === -1 && l2Pbs.indexOf(l2Target) === -1 && l2Name.indexOf(l2Target) === -1) {
                        continue;
                    }
                }
            }

            // Prio 1 Focus filter
            if (root.prio1Only && !c.is_prio1) {
                continue;
            }

            // Grouped (PBS) filter
            if (root.groupedOnly && !c.is_grouped) {
                continue;
            }

            // Milestone filter
            if (root.filterMilestone === "PLANNED" || root.filterMilestone === "WITH_MILESTONE") {
                var cHasM = !!(c.has_milestone || c.milestone_name || c.effective_milestone_name);
                var cTaskHasM = c.tasks && c.tasks.some(function(t) { return !!(t.has_milestone || t.milestone_name || t.effective_milestone_name); });
                if (!cHasM && !cTaskHasM) continue;
            } else if (root.filterMilestone === "UNPLANNED" || root.filterMilestone === "NO_MILESTONE") {
                var cHasM2 = !!(c.has_milestone || c.milestone_name || c.effective_milestone_name);
                var cTaskHasM2 = c.tasks && c.tasks.some(function(t) { return !!(t.has_milestone || t.milestone_name || t.effective_milestone_name); });
                if (cHasM2 || cTaskHasM2) continue;
            } else if (root.filterMilestone !== "ALL" && root.filterMilestone !== "") {
                var targetM = root.filterMilestone.toLowerCase();
                var mName = (c.milestone_name || "").toLowerCase();
                var effMName = (c.effective_milestone_name || "").toLowerCase();
                var mCat = (c.milestone_category || "").toLowerCase();
                var matchesSelf = (mName === targetM || effMName === targetM || mName.indexOf(targetM) !== -1 || effMName.indexOf(targetM) !== -1 || mCat.indexOf(targetM) !== -1);
                var matchesAnyTask = c.tasks && c.tasks.some(function(t) {
                    var tm = (t.milestone_name || t.effective_milestone_name || "").toLowerCase();
                    var tc = (t.milestone_category || "").toLowerCase();
                    return (tm === targetM || tm.indexOf(targetM) !== -1 || tc.indexOf(targetM) !== -1);
                });
                if (!matchesSelf && !matchesAnyTask) continue;
            }

            // Overdue Deadlines filter
            if (root.overdueOnly) {
                var cIsOverdue = (c.urgency_status === "overdue");
                var cHasOverdueTask = c.tasks && c.tasks.some(function(t) { return t.urgency_status === "overdue"; });
                if (!cIsOverdue && !cHasOverdueTask) continue;
            }

            var openTasks = getFilteredTasks(c.tasks || []);
            // Keep container if it has open child tasks, or if the parent container itself is not done/closed
            if (root.hideClosedTasks) {
                if (openTasks.length === 0 && c.is_done) continue;
            }
            res.push(c);
        }

        // Sort items complying with [<NR>] <Name> rule before all other items
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

    function formatCellObject(c) {
        if (!c) return null;
        return {
            assignee: c.assignee || "Team Member",
            sprint_name: c.sprint_name || "",
            total_count: c.total_count || 0,
            stories_count: c.stories_count || 0,
            bugs_count: c.bugs_count || 0,
            tasks_count: c.tasks_count || 0,
            tasks_not_started_count: c.tasks_not_started_count || 0,
            tasks_active_count: c.tasks_active_count || 0,
            tasks_closed_count: c.tasks_closed_count || 0,
            tasks_closed_percent: c.tasks_closed_percent !== undefined ? c.tasks_closed_percent : (c.tasks_count > 0 ? Math.round(((c.tasks_closed_count || 0) / c.tasks_count) * 100) : 0),
            not_started_count: c.not_started_count || 0,
            active_count: c.active_count || 0,
            overdue_count: c.overdue_count || 0,
            completed_count: c.completed_count || 0,
            grouped_containers: c.grouped_containers || [],
            items: c.items || []
        };
    }

    function refreshMatrix() {
        if (!backend) return;
        refreshHierarchyLists();
        var prevAssignee = root.selectedCell ? root.selectedCell.assignee : null;
        var prevSprint = root.selectedCell ? root.selectedCell.sprint_name : null;

        var newData = backend.getWorkloadMatrix(
            root.selectedHorizon,
            root.filterLevel1 || "ALL",
            root.filterLevel2 || "ALL",
            !!root.prio1Only,
            !!root.groupedOnly,
            !!root.hideClosedTasks,
            root.searchQuery || "",
            root.historyOffset,
            root.filterMilestone || "ALL",
            !!root.overdueOnly
        );
        matrixData = newData;

        if (prevAssignee && prevSprint) {
            var foundCell = null;
            if (newData && newData.rows) {
                for (var r = 0; r < newData.rows.length; r++) {
                    var row = newData.rows[r];
                    if (row.assignee === prevAssignee && row.cells) {
                        for (var c = 0; c < row.cells.length; c++) {
                            var cell = row.cells[c];
                            if (cell.sprint_name === prevSprint) {
                                foundCell = cell;
                                break;
                            }
                        }
                    }
                    if (foundCell) break;
                }
            }
            if (foundCell) {
                root.selectedCell = formatCellObject(foundCell);
            } else {
                root.selectedCell = formatCellObject({
                    assignee: prevAssignee,
                    sprint_name: prevSprint,
                    total_count: 0,
                    stories_count: 0,
                    bugs_count: 0,
                    tasks_count: 0,
                    tasks_not_started_count: 0,
                    tasks_active_count: 0,
                    tasks_closed_count: 0,
                    tasks_closed_percent: 0,
                    not_started_count: 0,
                    active_count: 0,
                    overdue_count: 0,
                    completed_count: 0,
                    grouped_containers: [],
                    items: []
                });
            }
            if (typeof window !== "undefined" && window.isRightSidebarOpen && window.rightSidebarMode === "workload_cell") {
                window.rightSidebarData = root.selectedCell;
            }
        }
    }

    property bool hasActiveHierarchyFilters: (root.filterLevel1 || "ALL") !== "ALL" || (root.filterLevel2 || "ALL") !== "ALL" || (root.filterMilestone || "ALL") !== "ALL" || root.prio1Only || root.groupedOnly || root.hideClosedTasks || root.overdueOnly || root.searchQuery !== ""

    function resetHierarchyFilters() {
        root.filterLevel1 = "ALL"
        root.filterLevel2 = "ALL"
        root.filterMilestone = "ALL"
        root.prio1Only = false
        root.groupedOnly = false
        root.hideClosedTasks = false
        root.overdueOnly = false
        root.searchQuery = ""
        if (typeof wlLevel1Combo !== "undefined" && wlLevel1Combo) { wlLevel1Combo.currentIndex = 0; wlLevel1Combo.editText = ""; }
        if (typeof wlLevel2Combo !== "undefined" && wlLevel2Combo) { wlLevel2Combo.currentIndex = 0; wlLevel2Combo.editText = ""; }
        if (typeof wlMilestoneCombo !== "undefined" && wlMilestoneCombo) { wlMilestoneCombo.currentIndex = 0; wlMilestoneCombo.editText = ""; }
        refreshMatrix()
    }

    onSelectedHorizonChanged: refreshMatrix()
    onFilterLevel1Changed:    refreshMatrix()
    onFilterLevel2Changed:    refreshMatrix()
    onFilterMilestoneChanged: refreshMatrix()
    onPrio1OnlyChanged:       refreshMatrix()
    onGroupedOnlyChanged:     refreshMatrix()
    onHideClosedTasksChanged: refreshMatrix()
    onOverdueOnlyChanged:     refreshMatrix()
    onSearchQueryChanged:     refreshMatrix()
    onHistoryOffsetChanged:   refreshMatrix()

    Connections {
        target: backend
        function onWorkItemsChanged() {
            root.refreshMatrix()
        }
        function onWorkloadMatrixChanged() {
            root.refreshMatrix()
        }
        function onMilestonesChanged() {
            root.refreshHierarchyLists()
            root.refreshMatrix()
        }
    }

    Connections {
        target: typeof window !== "undefined" ? window : null
        function onIsRightSidebarOpenChanged() {
            if (typeof window !== "undefined" && !window.isRightSidebarOpen && root.selectedCell) {
                root.selectedCell = null;
            }
        }
    }

    Component.onCompleted: {
        refreshMatrix()
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        anchors.rightMargin: 20
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
                onClicked: {
                    if (backend) {
                        backend.refresh_all_data();
                    }
                    root.refreshMatrix();
                }
            }

            // Prepare Sprints Button
            Button {
                text: "🗓️ Prepare Sprints..."
                font.pixelSize: 11
                font.weight: Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: "Prepare weekly iterations in advance up to a milestone deadline"
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#58a6ff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 30
                    implicitWidth: 135
                    radius: 6
                    color: parent.hovered ? "#0d2344" : "#161b22"
                    border.color: "#1f6feb"
                }
                onClicked: workloadPrepareModal.openForPreparation("", "")
            }
        }

        // ====================== Time Navigation & Timeline Status Bar ======================
        Rectangle {
            Layout.fillWidth: true
            height: 48
            radius: 8
            color: root.historyOffset > 0 ? "#1c180a" : "#161b22"
            border.color: root.historyOffset > 0 ? "#d29922" : "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                // ◀ Past horizon button
                Button {
                    text: "◀ Past (" + root.selectedHorizon + "w)"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    ToolTip.visible: hovered
                    ToolTip.text: "Shift view " + root.selectedHorizon + " sprints back in time"
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 90
                        radius: 6
                        color: parent.hovered ? "#21262d" : "transparent"
                        border.color: "#30363d"
                    }
                    onClicked: root.historyOffset += root.selectedHorizon
                }

                // ◀ -1 Wk button
                Button {
                    text: "◀ -1 Wk"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    ToolTip.visible: hovered
                    ToolTip.text: "Shift view 1 sprint back into the past"
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 65
                        radius: 6
                        color: parent.hovered ? "#21262d" : "transparent"
                        border.color: "#30363d"
                    }
                    onClicked: root.historyOffset += 1
                }

                // ================= Center Timeline & Today Card =================
                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    Item { Layout.fillWidth: true }

                    // Current Date & Week Pill Card
                    Rectangle {
                        implicitHeight: 32
                        implicitWidth: currentInfoRow.implicitWidth + 24
                        radius: 16
                        color: root.historyOffset > 0 ? "#2a220b" : "#0d2036"
                        border.color: root.historyOffset > 0 ? "#d29922" : "#1f6feb"
                        border.width: 1

                        Row {
                            id: currentInfoRow
                            anchors.centerIn: parent
                            spacing: 8

                            // Beacon Pulse Dot
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: root.historyOffset > 0 ? "#f0883e" : "#3fb950"
                                anchors.verticalCenter: parent.verticalCenter

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: true
                                    NumberAnimation { from: 1.0; to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                                    NumberAnimation { from: 0.35; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                                }
                            }

                            // Current Date Text
                            Text {
                                text: root.matrixData && root.matrixData.current_date_label ? ("Today: " + root.matrixData.current_date_label) : "Today"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: "#e6edf3"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "·"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#8b949e"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Current Sprint Tag
                            Text {
                                text: "⚡ " + (root.matrixData && root.matrixData.current_sprint_name ? root.matrixData.current_sprint_name : "")
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: root.historyOffset > 0 ? "#f0883e" : "#58a6ff"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // Jump to Current Week / Today Button
                    Button {
                        text: root.historyOffset > 0 ? "🔴  Back to Current" : "🎯  Focus Current Week"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: root.historyOffset > 0 ? "Return to the current calendar window" : "Scroll & center current week in the timeline view"
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: root.historyOffset > 0 ? "#ff7b72" : "#79c0ff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 30
                            implicitWidth: 150
                            radius: 15
                            color: parent.hovered ? (root.historyOffset > 0 ? "#3d0c0c" : "#13315c") : (root.historyOffset > 0 ? "#21262d" : "#0d2344")
                            border.color: root.historyOffset > 0 ? "#da3633" : "#1f6feb"
                            border.width: 1
                        }
                        onClicked: root.jumpToCurrentWeek()
                    }

                    // Jump to Active Sprints Button (if past active sprints exist)
                    Button {
                        visible: root.matrixData && root.matrixData.latest_active_sprint_name && (root.matrixData.suggested_lookback_offset || 0) > 0 && root.historyOffset !== root.matrixData.suggested_lookback_offset
                        text: "⚡  Active Sprints (" + (root.matrixData ? (root.matrixData.latest_active_sprint_label || root.matrixData.latest_active_sprint_name || "") : "") + ")"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        ToolTip.visible: hovered
                        ToolTip.text: "Jump directly to the latest project sprints that contain work items (" + (root.matrixData ? root.matrixData.latest_active_sprint_name : "") + ")"
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 30
                            implicitWidth: 155
                            radius: 15
                            color: parent.hovered ? "#2ea043" : "#238636"
                            border.color: "#3fb950"
                            border.width: 1
                        }
                        onClicked: {
                            if (root.matrixData && root.matrixData.suggested_lookback_offset !== undefined) {
                                root.historyOffset = root.matrixData.suggested_lookback_offset;
                            }
                        }
                    }

                    // "Viewing past N weeks" indicator badge
                    Rectangle {
                        visible: root.historyOffset > 0
                        implicitHeight: 24
                        implicitWidth: historyBadgeText.implicitWidth + 16
                        radius: 12
                        color: "#3d2e00"
                        border.color: "#d29922"
                        border.width: 1
                        Text {
                            id: historyBadgeText
                            anchors.centerIn: parent
                            text: "📅 " + root.historyOffset + " sprint(s) back"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#f0883e"
                        }
                    }

                    // Sprint range display
                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: sprintRangeText.implicitWidth + 16
                        radius: 6
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        Text {
                            id: sprintRangeText
                            anchors.centerIn: parent
                            text: {
                                if (!root.matrixData || !root.matrixData.sprint_columns || root.matrixData.sprint_columns.length === 0)
                                    return "No data"
                                var cols = root.matrixData.sprint_columns
                                var first = cols[0].label || cols[0].short_label || cols[0].sprint_name
                                var last = cols[cols.length - 1].label || cols[cols.length - 1].short_label || cols[cols.length - 1].sprint_name
                                return first + "  →  " + last
                            }
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: root.historyOffset > 0 ? "#d29922" : "#8b949e"
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // +1 Wk ▶ button
                Button {
                    text: "+1 Wk ▶"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    enabled: root.historyOffset > 0
                    ToolTip.visible: hovered && root.historyOffset > 0
                    ToolTip.text: "Shift view 1 sprint forward towards current week"
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: root.historyOffset > 0 ? "#c9d1d9" : "#484f58"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 65
                        radius: 6
                        color: parent.hovered && root.historyOffset > 0 ? "#21262d" : "transparent"
                        border.color: root.historyOffset > 0 ? "#30363d" : "#21262d"
                    }
                    onClicked: root.historyOffset = Math.max(0, root.historyOffset - 1)
                }

                // Future horizon ▶ button
                Button {
                    text: "Future (" + root.selectedHorizon + "w) ▶"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    enabled: root.historyOffset > 0
                    ToolTip.visible: hovered && root.historyOffset > 0
                    ToolTip.text: "Shift view " + root.selectedHorizon + " sprints forward towards current/future sprints"
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: root.historyOffset > 0 ? "#c9d1d9" : "#484f58"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 90
                        radius: 6
                        color: parent.hovered && root.historyOffset > 0 ? "#21262d" : "transparent"
                        border.color: root.historyOffset > 0 ? "#30363d" : "#21262d"
                    }
                    onClicked: root.historyOffset = Math.max(0, root.historyOffset - root.selectedHorizon)
                }
            }
        }

        // ====================== Informational Banner when Current Calendar Window has 0 items but Project Sprints Exist ======================
        Rectangle {
            Layout.fillWidth: true
            height: 38
            radius: 6
            color: "#0d2036"
            border.color: "#1f6feb"
            border.width: 1
            visible: root.matrixData && (root.matrixData.total_items || 0) === 0 && (root.matrixData.total_all_sprint_items || 0) > 0 && !root.hasActiveHierarchyFilters

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    text: "ℹ️"
                    font.pixelSize: 14
                }
                Text {
                    text: "No work items in visible calendar window (" + sprintRangeText.text + "). " + (root.matrixData ? (root.matrixData.total_all_sprint_items || 0) : 0) + " work items found in project sprints (up to " + (root.matrixData ? root.matrixData.latest_active_sprint_name : "") + ")."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#e6edf3"
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: "◀  Jump to Active Sprints (" + (root.matrixData ? (root.matrixData.latest_active_sprint_label || root.matrixData.latest_active_sprint_name || "") : "") + ")"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 26
                        implicitWidth: 190
                        radius: 4
                        color: parent.hovered ? "#2ea043" : "#238636"
                        border.color: "#3fb950"
                    }
                    onClicked: {
                        if (root.matrixData && root.matrixData.suggested_lookback_offset !== undefined) {
                            root.historyOffset = root.matrixData.suggested_lookback_offset;
                        }
                    }
                }
            }
        }

        // ====================== Backlog Hierarchy (L1 Sub-Systems / L2 Components) & Priority Filter Bar ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Level 1: Sub-Systems (Epics)
            RowLayout {
                spacing: 6
                Text {
                    text: "Sub-System (L1):"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: wlLevel1Combo
                    implicitWidth: 200
                    implicitHeight: 28
                    font.pixelSize: 11
                    editable: true
                    model: root.level1List
                    editText: root.filterLevel1 === "ALL" ? "" : root.filterLevel1

                    onEditTextChanged: {
                        var val = editText ? editText.trim() : "";
                        root.filterLevel1 = (val === "" ? "ALL" : val);
                    }

                    onActivated: function(index) {
                        var val = root.level1List[index] || "ALL";
                        root.filterLevel1 = val;
                        editText = (val === "ALL" ? "" : val);
                    }

                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: wlLevel1Combo.hovered || wlLevel1Combo.activeFocus ? "#58a6ff" : (root.filterLevel1 !== "ALL" ? "#8250df" : "#30363d")
                    }

                    contentItem: TextField {
                        leftPadding: 8
                        rightPadding: (root.filterLevel1 !== "ALL") ? 32 : 24
                        text: wlLevel1Combo.editText
                        placeholderText: "Type or select L1..."
                        placeholderTextColor: "#484f58"
                        font: wlLevel1Combo.font
                        color: root.filterLevel1 !== "ALL" ? "#bc8cff" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        background: Item {}
                        onTextChanged: {
                            if (text !== wlLevel1Combo.editText) {
                                wlLevel1Combo.editText = text;
                            }
                        }
                    }
                }

                // Clear L1 filter button
                Button {
                    visible: root.filterLevel1 !== "ALL" && root.filterLevel1 !== ""
                    text: "✖"
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitWidth: 20; implicitHeight: 20; radius: 10; color: parent.hovered ? "#21262d" : "transparent" }
                    onClicked: {
                        root.filterLevel1 = "ALL";
                        wlLevel1Combo.currentIndex = 0;
                        wlLevel1Combo.editText = "";
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // Level 2: Components (Features)
            RowLayout {
                spacing: 6
                Text {
                    text: "Component (L2):"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: wlLevel2Combo
                    implicitWidth: 200
                    implicitHeight: 28
                    font.pixelSize: 11
                    editable: true
                    model: root.level2List
                    editText: root.filterLevel2 === "ALL" ? "" : root.filterLevel2

                    onEditTextChanged: {
                        var val = editText ? editText.trim() : "";
                        root.filterLevel2 = (val === "" ? "ALL" : val);
                    }

                    onActivated: function(index) {
                        var val = root.level2List[index] || "ALL";
                        root.filterLevel2 = val;
                        editText = (val === "ALL" ? "" : val);
                    }

                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: wlLevel2Combo.hovered || wlLevel2Combo.activeFocus ? "#58a6ff" : (root.filterLevel2 !== "ALL" ? "#388bfd" : "#30363d")
                    }

                    contentItem: TextField {
                        leftPadding: 8
                        rightPadding: (root.filterLevel2 !== "ALL") ? 32 : 24
                        text: wlLevel2Combo.editText
                        placeholderText: "Type or select L2..."
                        placeholderTextColor: "#484f58"
                        font: wlLevel2Combo.font
                        color: root.filterLevel2 !== "ALL" ? "#58a6ff" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        background: Item {}
                        onTextChanged: {
                            if (text !== wlLevel2Combo.editText) {
                                wlLevel2Combo.editText = text;
                            }
                        }
                    }
                }

                // Clear L2 filter button
                Button {
                    visible: root.filterLevel2 !== "ALL" && root.filterLevel2 !== ""
                    text: "✖"
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitWidth: 20; implicitHeight: 20; radius: 10; color: parent.hovered ? "#21262d" : "transparent" }
                    onClicked: {
                        root.filterLevel2 = "ALL";
                        wlLevel2Combo.currentIndex = 0;
                        wlLevel2Combo.editText = "";
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // Milestone Filter
            RowLayout {
                spacing: 6
                Text {
                    text: "Milestone:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: wlMilestoneCombo
                    implicitWidth: 200
                    implicitHeight: 28
                    font.pixelSize: 11
                    editable: true
                    model: root.milestonesList
                    editText: root.filterMilestone === "ALL" ? "" : root.filterMilestone

                    onEditTextChanged: {
                        var val = editText ? editText.trim() : "";
                        root.filterMilestone = (val === "" ? "ALL" : val);
                    }

                    onActivated: function(index) {
                        var val = root.milestonesList[index] || "ALL";
                        root.filterMilestone = val;
                        editText = (val === "ALL" ? "" : val);
                    }

                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: wlMilestoneCombo.hovered || wlMilestoneCombo.activeFocus ? "#58a6ff" : (root.filterMilestone !== "ALL" ? "#d29922" : "#30363d")
                    }

                    contentItem: TextField {
                        leftPadding: 8
                        rightPadding: (root.filterMilestone !== "ALL") ? 32 : 24
                        text: wlMilestoneCombo.editText
                        placeholderText: "Type or select milestone..."
                        placeholderTextColor: "#484f58"
                        font: wlMilestoneCombo.font
                        color: root.filterMilestone !== "ALL" ? "#f0883e" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        background: Item {}
                        onTextChanged: {
                            if (text !== wlMilestoneCombo.editText) {
                                wlMilestoneCombo.editText = text;
                            }
                        }
                    }
                }

                // Clear Milestone filter button
                Button {
                    visible: root.filterMilestone !== "ALL" && root.filterMilestone !== ""
                    text: "✖"
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitWidth: 20; implicitHeight: 20; radius: 10; color: parent.hovered ? "#21262d" : "transparent" }
                    onClicked: {
                        root.filterMilestone = "ALL";
                        wlMilestoneCombo.currentIndex = 0;
                        wlMilestoneCombo.editText = "";
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // 🚨 Overdue Deadlines Only Toggle
            Button {
                text: root.overdueOnly ? "🚨 Overdue Only" : "🚨 Overdue"
                checkable: true
                checked: root.overdueOnly
                font.pixelSize: 11
                font.weight: checked ? Font.Bold : Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: root.overdueOnly ? "Showing overdue deadline items only. Click to show all." : "Click to filter to overdue deadline items only."
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: parent.checked ? "#ffffff" : (parent.hovered ? "#ff7b72" : "#8b949e")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 28
                    implicitWidth: 115
                    radius: 6
                    color: parent.checked ? "#da3633" : (parent.hovered ? "#21262d" : "#161b22")
                    border.color: parent.checked ? "#f85149" : "#30363d"
                }
                onClicked: { root.overdueOnly = !root.overdueOnly }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // ⭐ Prio 1 Focus Only Toggle
            Button {
                text: root.prio1Only ? "⭐ Prio 1 Focus Only" : "⭐ All Priorities"
                checkable: true
                checked: root.prio1Only
                font.pixelSize: 11
                font.weight: Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: root.prio1Only ? "Showing strategic focus Prio 1 items only (OI, MP, SCEN, SPEC, PA, CS, DOC)." : "Click to filter to strategic focus Prio 1 items only."
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: parent.checked ? "#f0883e" : "#8b949e"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 28
                    implicitWidth: 135
                    radius: 6
                    color: parent.checked ? "#3d2800" : (parent.hovered ? "#21262d" : "#161b22")
                    border.color: parent.checked ? "#d29922" : "#30363d"
                }
                onClicked: { root.prio1Only = !root.prio1Only }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // 🏷️ Grouped (PBS) Only Toggle
            Button {
                text: root.groupedOnly ? "🏷️ Grouped (PBS) Only" : "🏷️ All Groupings"
                checkable: true
                checked: root.groupedOnly
                font.pixelSize: 11
                font.weight: Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: root.groupedOnly ? "Showing work items properly grouped with Level 1 & 2 PBS numbers." : "Click to filter to properly grouped PBS items only."
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: parent.checked ? "#58a6ff" : "#8b949e"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 28
                    implicitWidth: 145
                    radius: 6
                    color: parent.checked ? "#0d2344" : (parent.hovered ? "#21262d" : "#161b22")
                    border.color: parent.checked ? "#1f6feb" : "#30363d"
                }
                onClicked: { root.groupedOnly = !root.groupedOnly }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // 🚩 Manage Milestones Button
            Button {
                text: "🚩 Manage"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: "Manage Major Milestones (DDQS, QIAV, Scenarios) and Categories"
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#58a6ff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 28
                    implicitWidth: 95
                    radius: 6
                    color: parent.hovered ? "#21262d" : "#161b22"
                    border.color: "#30363d"
                }
                onClicked: {
                    if (typeof window !== "undefined" && window.openMilestonesManager) {
                        window.openMilestonesManager();
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Reset Hierarchy Filters
            Button {
                visible: root.hasActiveHierarchyFilters
                text: "✖ Reset Filters"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#f85149"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 28
                    implicitWidth: 100
                    radius: 6
                    color: parent.hovered ? "#3c1e1e" : "#211515"
                    border.color: "#da3633"
                }
                onClicked: {
                    wlLevel1Combo.currentIndex = 0;
                    wlLevel1Combo.editText = "";
                    wlLevel2Combo.currentIndex = 0;
                    wlLevel2Combo.editText = "";
                    root.resetHierarchyFilters();
                }
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
                        Text { text: "TASKS (STATUS RATIO)"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                        RowLayout {
                            spacing: 8
                            Text {
                                text: root.matrixData ? (root.matrixData.total_tasks || 0).toString() : "0"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 18
                                font.weight: Font.Bold
                                color: "#d29922"
                            }
                            RowLayout {
                                spacing: 6
                                visible: root.matrixData && root.matrixData.total_tasks > 0
                                Text {
                                    text: "⏳ " + (root.matrixData ? (root.matrixData.total_tasks_not_started || 0) : 0)
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                }
                                Text {
                                    text: "⚡ " + (root.matrixData ? (root.matrixData.total_tasks_active || 0) : 0)
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#58a6ff"
                                }
                                Text {
                                    text: "✅ " + (root.matrixData ? (root.matrixData.total_tasks_closed_percent !== undefined ? root.matrixData.total_tasks_closed_percent : Math.round(((root.matrixData.total_tasks_closed || 0) / Math.max(1, root.matrixData.total_tasks || 1)) * 100)) : 0) + "%"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#3fb950"
                                }
                            }
                        }
                    }
                }
            }

            // Overdue Warnings (Interactive Filter Card)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: root.overdueOnly ? "#3d1214" : (root.matrixData && root.matrixData.total_overdue > 0 ? (overdueCardMa.containsMouse ? "#321719" : "#261315") : (overdueCardMa.containsMouse ? "#21262d" : "#161b22"))
                radius: 8
                border.color: root.overdueOnly ? "#f85149" : (root.matrixData && root.matrixData.total_overdue > 0 ? (overdueCardMa.containsMouse ? "#f85149" : "#da3633") : (overdueCardMa.containsMouse ? "#58a6ff" : "#30363d"))
                border.width: root.overdueOnly ? 2 : 1

                MouseArea {
                    id: overdueCardMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    ToolTip.visible: containsMouse
                    ToolTip.text: root.overdueOnly ? "Filter Active: Showing overdue items only.\nClick to disable filter." : "Click to filter workload matrix and items by Overdue Deadlines."
                    onClicked: {
                        root.overdueOnly = !root.overdueOnly;
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Text { text: "🚨"; font.pixelSize: 24 }
                    ColumnLayout {
                        spacing: 2
                        RowLayout {
                            spacing: 6
                            Text {
                                text: "OVERDUE DEADLINES"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: root.overdueOnly ? "#f85149" : (root.matrixData && root.matrixData.total_overdue > 0 ? "#ff7b72" : "#8b949e")
                            }
                            Rectangle {
                                visible: root.overdueOnly
                                implicitHeight: 14
                                implicitWidth: 46
                                radius: 7
                                color: "#da3633"
                                Text {
                                    anchors.centerIn: parent
                                    text: "FILTER"
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }
                            }
                        }
                        Text {
                            text: root.matrixData ? (root.matrixData.total_overdue || 0).toString() : "0"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: root.overdueOnly ? "#ff7b72" : (root.matrixData && root.matrixData.total_overdue > 0 ? "#f85149" : "#8b949e")
                        }
                    }
                }
            }
        }

        // ====================== Main Workload Heatmap Matrix ======================
        Item {
            id: matrixTableContainer
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
                        height: 68
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Assignee Header Column (Pinned Left)
                            Item {
                                Layout.preferredWidth: root.teamMemberColWidth
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

                            // Scrollable Sprint Column Headers Area
                            Item {
                                id: sprintHeaderArea
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    onWheel: function(wheel) {
                                        if (wheel.angleDelta.x !== 0) {
                                            root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.x));
                                            wheel.accepted = true;
                                        } else if (wheel.modifiers & Qt.ShiftModifier || wheel.angleDelta.y !== 0) {
                                            root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.y));
                                            wheel.accepted = true;
                                        }
                                    }
                                }

                                Row {
                                    id: sprintHeaderRow
                                    x: -root.matrixContentX
                                    height: parent.height

                                    Repeater {
                                        model: root.matrixData ? (root.matrixData.sprint_columns || []) : []
                                        Item {
                                            width: root.sprintColWidth
                                            height: sprintHeaderRow.height

                                            property bool isCurrent: !!modelData.is_current

                                            // Highlight background for current week
                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: 1
                                                color: isCurrent ? "#12253d" : "transparent"
                                                border.color: isCurrent ? "#1f6feb" : "transparent"
                                                border.width: 1
                                                radius: 4
                                            }

                                            // Top indicator accent bar for current week
                                            Rectangle {
                                                visible: isCurrent
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                height: 3
                                                color: "#58a6ff"
                                                radius: 1
                                            }

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 2

                                                // "● THIS WEEK" pill badge if current week
                                                Rectangle {
                                                    visible: isCurrent
                                                    Layout.alignment: Qt.AlignHCenter
                                                    implicitHeight: 15
                                                    implicitWidth: curBadgeRow.implicitWidth + 8
                                                    radius: 7.5
                                                    color: "#0d419d"
                                                    border.color: "#388bfd"
                                                    border.width: 1

                                                    Row {
                                                        id: curBadgeRow
                                                        anchors.centerIn: parent
                                                        spacing: 3
                                                        Text {
                                                            text: "●"
                                                            font.pixelSize: 7
                                                            color: "#79c0ff"
                                                        }
                                                        Text {
                                                            text: "THIS WEEK"
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 8
                                                            font.weight: Font.Bold
                                                            color: "#ffffff"
                                                        }
                                                    }
                                                }

                                                Text {
                                                    text: modelData.short_label || modelData.sprint_name
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: isCurrent ? 13 : 12
                                                    font.weight: Font.Bold
                                                    color: isCurrent ? "#79c0ff" : "#f0f6fc"
                                                    horizontalAlignment: Text.AlignHCenter
                                                    Layout.alignment: Qt.AlignHCenter
                                                }

                                                Text {
                                                    text: modelData.start_date ? (modelData.start_date.substring(5) + " · " + modelData.end_date.substring(5)) : ""
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: isCurrent ? Font.DemiBold : Font.Normal
                                                    color: isCurrent ? "#a5d6ff" : "#8b949e"
                                                    horizontalAlignment: Text.AlignHCenter
                                                    Layout.alignment: Qt.AlignHCenter
                                                }

                                                // Milestones for this sprint week
                                                Row {
                                                    visible: modelData.milestones && modelData.milestones.length > 0
                                                    spacing: 3
                                                    Layout.alignment: Qt.AlignHCenter

                                                    Repeater {
                                                        model: modelData.milestones || []
                                                        Rectangle {
                                                            implicitHeight: 16
                                                            implicitWidth: sMRow.implicitWidth + 8
                                                            radius: 8
                                                            color: modelData.category_bg_color || "#0d2344"
                                                            border.color: modelData.category_color || "#1f6feb"
                                                            border.width: 1

                                                            Row {
                                                                id: sMRow
                                                                anchors.centerIn: parent
                                                                spacing: 2
                                                                Text {
                                                                    text: modelData.category_icon || "🚩"
                                                                    font.pixelSize: 8
                                                                }
                                                                Text {
                                                                    text: modelData.name
                                                                    font.family: "Segoe UI, sans-serif"
                                                                    font.pixelSize: 8
                                                                    font.weight: Font.DemiBold
                                                                    color: modelData.category_color || "#58a6ff"
                                                                }
                                                            }

                                                            ToolTip.visible: sMMa.containsMouse
                                                            ToolTip.text: modelData.name + " (" + (modelData.category_name || "Milestone") + ")\nDate: " + (modelData.date_display || modelData.target_date) + (modelData.description ? ("\n" + modelData.description) : "") + "\n(Click to manage)"

                                                            MouseArea {
                                                                id: sMMa
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

                                            Rectangle {
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: 1
                                                color: "#30363d"
                                            }
                                        }
                                    }
                                }
                            }

                            // Total column header (Pinned Right)
                            Item {
                                Layout.preferredWidth: root.totalColWidth
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

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

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
                            height: root.matrixRowHeight
                            color: rowMa.containsMouse ? "#1c2128" : "#0d1117"
                            border.color: "#21262d"
                            border.width: 1

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: true
                                onWheel: function(wheel) {
                                    if (wheel.angleDelta.x !== 0) {
                                        root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.x));
                                        wheel.accepted = true;
                                    } else if (wheel.modifiers & Qt.ShiftModifier) {
                                        root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.y));
                                        wheel.accepted = true;
                                    } else {
                                        wheel.accepted = false;
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 0

                                // Assignee Info Column (Pinned Left)
                                Rectangle {
                                    Layout.preferredWidth: root.teamMemberColWidth
                                    Layout.fillHeight: true
                                    color: assigneeColMa.containsMouse ? "#21262d" : "transparent"

                                    MouseArea {
                                        id: assigneeColMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (typeof window !== "undefined" && typeof window.openRightSidebar === "function" && backend) {
                                                var details = backend.get_member_workload_details(modelData.assignee);
                                                window.openRightSidebar("workload_member", modelData.assignee, "Member Workload Breakdown", details);
                                            }
                                        }
                                    }

                                    ToolTip.visible: assigneeColMa.containsMouse
                                    ToolTip.text: "Click to open " + modelData.assignee + " workload details in Right Sidebar"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 8
                                        spacing: 10

                                        // Avatar circle
                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: modelData.assignee === "Unassigned" ? "#30363d" : "#1f6feb"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.initials || "U"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: "#ffffff"
                                            }
                                        }

                                        // Name + stats sub-line
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.assignee
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: modelData.assignee === "Unassigned" ? "#8b949e" : (assigneeColMa.containsMouse ? "#58a6ff" : "#f0f6fc")
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: "👤"
                                                    font.pixelSize: 10
                                                    visible: assigneeColMa.containsMouse
                                                }
                                            }

                                            Row {
                                                spacing: 6
                                                visible: modelData.stats && modelData.stats.total > 0

                                                Text {
                                                    text: modelData.stats ? modelData.stats.total + " items" : ""
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    color: "#8b949e"
                                                }

                                                // Overdue pill
                                                Rectangle {
                                                    visible: modelData.stats && (modelData.stats.overdue || 0) > 0
                                                    implicitHeight: 14
                                                    implicitWidth: assigneeOverdueText.implicitWidth + 8
                                                    radius: 7
                                                    color: "#3d0c0c"
                                                    border.color: "#f85149"
                                                    border.width: 1
                                                    Text {
                                                        id: assigneeOverdueText
                                                        anchors.centerIn: parent
                                                        text: "🚨 " + (modelData.stats ? (modelData.stats.overdue || 0) : 0)
                                                        font.pixelSize: 8
                                                        font.weight: Font.Bold
                                                        color: "#ff7b72"
                                                    }
                                                }
                                            }
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

                                // Scrollable Sprint Cells Area
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    Row {
                                        x: -root.matrixContentX
                                        height: parent.height

                                        Repeater {
                                            model: modelData.cells || []
                                            Item {
                                                width: root.sprintColWidth
                                                height: parent.height

                                                property bool hasItems: modelData.total_count > 0
                                                property bool hasOverdue: modelData.overdue_count > 0
                                                property bool isCurrent: !!modelData.is_current
                                                property bool isSelected: root.selectedCell && root.selectedCell.assignee === modelData.assignee && root.selectedCell.sprint_name === modelData.sprint_name

                                                // Column swimlane background guide for current week
                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: isCurrent
                                                    color: "#0a1628"
                                                    opacity: 0.5
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    radius: 6
                                                    color: {
                                                        if (isSelected) return "#1f6feb"
                                                        if (cellMa.containsMouse) return isCurrent ? "#1c3558" : "#262c36"
                                                        if (!hasItems) return isCurrent ? "#0d1b2e" : "transparent"
                                                        if (hasOverdue) return "#381e1e"
                                                        if (modelData.total_count >= 8) return "#0d3525"
                                                        if (modelData.total_count >= 4) return "#0d2344"
                                                        return isCurrent ? "#132338" : "#161b22"
                                                    }
                                                    border.color: {
                                                        if (isSelected) return "#58a6ff"
                                                        if (hasOverdue) return "#f85149"
                                                        if (isCurrent) return "#1f6feb"
                                                        if (hasItems) return "#30363d"
                                                        return "transparent"
                                                    }
                                                    border.width: isCurrent ? 1.5 : 1

                                                    // Cell content
                                                    ColumnLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 2
                                                        visible: hasItems

                                                        RowLayout {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 5

                                                            // Total items pill
                                                            Text {
                                                                text: modelData.total_count.toString()
                                                                font.family: "Segoe UI, sans-serif"
                                                                font.pixelSize: 13
                                                                font.weight: Font.Bold
                                                                color: hasOverdue ? "#ff7b72" : (isSelected ? "#ffffff" : "#f0f6fc")
                                                            }

                                                            // Overdue warning badge
                                                            Rectangle {
                                                                visible: hasOverdue
                                                                implicitHeight: 14
                                                                implicitWidth: overdueLabel.implicitWidth + 6
                                                                radius: 7
                                                                color: "#f85149"
                                                                Text {
                                                                    id: overdueLabel
                                                                    anchors.centerIn: parent
                                                                    text: "!"
                                                                    font.pixelSize: 9
                                                                    font.weight: Font.ExtraBold
                                                                    color: "#ffffff"
                                                                }
                                                            }
                                                        }

                                                        // Stories / Bugs / Tasks micro breakdown
                                                        Row {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 4
                                                            visible: hasItems

                                                            // Stories count
                                                            Text {
                                                                text: "📖" + (modelData.stories_count || 0)
                                                                font.pixelSize: 9
                                                                color: isSelected ? "#e6edf3" : "#8b949e"
                                                                visible: (modelData.stories_count || 0) > 0
                                                            }

                                                            // Bugs count
                                                            Text {
                                                                text: "🐛" + (modelData.bugs_count || 0)
                                                                font.pixelSize: 9
                                                                color: "#f85149"
                                                                visible: (modelData.bugs_count || 0) > 0
                                                            }

                                                            // Tasks count
                                                            Text {
                                                                text: "🛠️" + (modelData.tasks_count || 0)
                                                                font.pixelSize: 9
                                                                color: isSelected ? "#e6edf3" : "#8b949e"
                                                                visible: (modelData.tasks_count || 0) > 0
                                                            }
                                                        }

                                                        // Task Status Relation Breakdown (Not Started ⏳, Active ⚡, Closed ✅)
                                                        Row {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 4
                                                            visible: (modelData.tasks_count || 0) > 0
                                                            Text {
                                                                text: "⏳" + (modelData.tasks_not_started_count || 0)
                                                                font.pixelSize: 9
                                                                font.weight: Font.DemiBold
                                                                color: "#8b949e"
                                                                visible: (modelData.tasks_not_started_count || 0) > 0
                                                            }
                                                            Text {
                                                                text: "⚡" + (modelData.tasks_active_count || 0)
                                                                font.pixelSize: 9
                                                                font.weight: Font.DemiBold
                                                                color: "#58a6ff"
                                                                visible: (modelData.tasks_active_count || 0) > 0
                                                            }
                                                            Text {
                                                                text: "✅" + (modelData.tasks_closed_percent !== undefined ? modelData.tasks_closed_percent : Math.round(((modelData.tasks_closed_count || 0) / Math.max(1, modelData.tasks_count || 1)) * 100)) + "%"
                                                                font.pixelSize: 9
                                                                font.weight: Font.DemiBold
                                                                color: "#3fb950"
                                                                visible: (modelData.tasks_closed_count || 0) > 0
                                                            }
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
                                                                var cellObj = root.formatCellObject(modelData);
                                                                root.selectedCell = cellObj;
                                                                if (typeof window !== "undefined" && typeof window.openRightSidebar === "function") {
                                                                    window.openRightSidebar("workload_cell", (cellObj.assignee || "Team Member") + " • " + (cellObj.sprint_name || "Sprint"), "Sprint Workload Tasks (" + cellObj.total_count + " items)", cellObj);
                                                                }
                                                            }
                                                        }
                                                        onWheel: function(wheel) {
                                                            if (wheel.angleDelta.x !== 0) {
                                                                root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.x));
                                                                wheel.accepted = true;
                                                            } else if (wheel.modifiers & Qt.ShiftModifier) {
                                                                root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.y));
                                                                wheel.accepted = true;
                                                            } else {
                                                                wheel.accepted = false;
                                                            }
                                                        }
                                                    }

                                                    ToolTip.visible: cellMa.containsMouse && hasItems
                                                    ToolTip.text: (modelData.assignee || "") + " @ " + (modelData.sprint_name || "") + "\n" +
                                                                  "Total: " + modelData.total_count + " items\n" +
                                                                  "Stories: " + modelData.stories_count + " | Bugs: " + modelData.bugs_count + " | Tasks: " + modelData.tasks_count + "\n" +
                                                                  "Tasks Breakdown: ⏳ " + (modelData.tasks_not_started_count || 0) + " Not Started | ⚡ " + (modelData.tasks_active_count || 0) + " Active | ✅ " + (modelData.tasks_closed_percent !== undefined ? modelData.tasks_closed_percent : Math.round(((modelData.tasks_closed_count || 0) / Math.max(1, modelData.tasks_count || 1)) * 100)) + "% Closed (" + (modelData.tasks_closed_count || 0) + "/" + (modelData.tasks_count || 0) + ")" +
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
                                    }
                                }

                                // Assignee Horizon Total (Pinned Right)
                                Item {
                                    Layout.preferredWidth: root.totalColWidth
                                    Layout.fillHeight: true

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Rectangle {
                                            Layout.alignment: Qt.AlignHCenter
                                            width: 54
                                            height: 20
                                            radius: 10
                                            color: "#161b22"
                                            border.color: "#30363d"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.stats ? modelData.stats.total.toString() : "0"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: "#58a6ff"
                                            }
                                        }

                                        Row {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: 3
                                            visible: modelData.stats && modelData.stats.tasks > 0
                                            Text { text: "⏳" + (modelData.stats.tasks_not_started || 0); font.pixelSize: 8; font.weight: Font.DemiBold; color: "#8b949e" }
                                            Text { text: "⚡" + (modelData.stats.tasks_active || 0); font.pixelSize: 8; font.weight: Font.DemiBold; color: "#58a6ff" }
                                            Text { text: "✅" + (modelData.stats ? (modelData.stats.tasks_closed_percent !== undefined ? modelData.stats.tasks_closed_percent : Math.round(((modelData.stats.tasks_closed || 0) / Math.max(1, modelData.stats.tasks || 1)) * 100)) : 0) + "%"; font.pixelSize: 8; font.weight: Font.DemiBold; color: "#3fb950" }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Matrix Column Totals Footer ----
                    Rectangle {
                        Layout.fillWidth: true
                        height: 42
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Pinned Left "TOTAL CAPACITY"
                            Item {
                                Layout.preferredWidth: root.teamMemberColWidth
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

                            // Scrollable Sprint Totals Area
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    onWheel: function(wheel) {
                                        if (wheel.angleDelta.x !== 0) {
                                            root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.x));
                                            wheel.accepted = true;
                                        } else if (wheel.modifiers & Qt.ShiftModifier || wheel.angleDelta.y !== 0) {
                                            root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.y));
                                            wheel.accepted = true;
                                        }
                                    }
                                }

                                Row {
                                    x: -root.matrixContentX
                                    height: parent.height

                                    Repeater {
                                        model: root.matrixData ? (root.matrixData.column_totals || []) : []
                                        Item {
                                            width: root.sprintColWidth
                                            height: parent.height

                                            property bool isCurrent: !!modelData.is_current

                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: 1
                                                color: isCurrent ? "#12253d" : "transparent"
                                                border.color: isCurrent ? "#1f6feb" : "transparent"
                                                border.width: 1
                                                radius: 4
                                            }

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 1
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: (modelData.total_count || 0) + " items"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: isCurrent ? 12 : 11
                                                    font.weight: Font.Bold
                                                    color: isCurrent ? "#79c0ff" : "#58a6ff"
                                                }
                                                Row {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    spacing: 4
                                                    visible: (modelData.tasks_count || 0) > 0
                                                    Text { text: "⏳" + (modelData.tasks_not_started_count || 0); font.pixelSize: 9; color: "#8b949e" }
                                                    Text { text: "⚡" + (modelData.tasks_active_count || 0); font.pixelSize: 9; color: "#58a6ff" }
                                                    Text { text: "✅" + (modelData.tasks_closed_percent !== undefined ? modelData.tasks_closed_percent : Math.round(((modelData.tasks_closed_count || 0) / Math.max(1, modelData.tasks_count || 1)) * 100)) + "%"; font.pixelSize: 9; color: "#3fb950" }
                                                }
                                            }
                                            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: isCurrent ? "#1f6feb" : "#30363d" }
                                        }
                                    }
                                }
                            }

                            // Pinned Grand Total (Right)
                            Item {
                                Layout.preferredWidth: root.totalColWidth
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

                    // ---- Horizontal Matrix ScrollBar Control Bar ----
                    Rectangle {
                        id: matrixScrollBarBar
                        Layout.fillWidth: true
                        height: root.maxMatrixScrollX > 0 ? 30 : 0
                        visible: root.maxMatrixScrollX > 0
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        Behavior on height { NumberAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Left spacer matching Team Member column
                            Item {
                                Layout.preferredWidth: root.teamMemberColWidth
                                Layout.fillHeight: true
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        text: "◀ Sprints Timeline Viewport ▶"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                    }
                                    Item { Layout.fillWidth: true }
                                    // Step 1 Sprint Left Button
                                    Button {
                                        text: "◀"
                                        font.pixelSize: 10
                                        ToolTip.visible: hovered
                                        ToolTip.text: "Scroll 1 sprint left"
                                        contentItem: Text { text: parent.text; font: parent.font; color: parent.hovered ? "#58a6ff" : "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { implicitWidth: 20; implicitHeight: 18; radius: 3; color: parent.hovered ? "#21262d" : "transparent"; border.color: parent.hovered ? "#30363d" : "transparent" }
                                        onClicked: {
                                            root.matrixContentX = Math.max(0, root.matrixContentX - root.sprintColWidth);
                                        }
                                    }
                                }
                                Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: "#30363d" }
                            }

                            // Middle horizontal scrollbar
                            Item {
                                id: scrollTrackContainer
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                // Track background
                                Rectangle {
                                    id: scrollTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 10
                                    radius: 5
                                    color: "#0d1117"
                                    border.color: scrollTrackMa.containsMouse ? "#58a6ff" : "#30363d"
                                    border.width: 1

                                    // Draggable Scrollbar Thumb
                                    Rectangle {
                                        id: scrollThumb
                                        height: 8
                                        radius: 4
                                        anchors.verticalCenter: parent.verticalCenter

                                        width: {
                                            if (root.totalSprintContentWidth <= 0 || root.sprintViewportWidth <= 0) return 40;
                                            var ratio = root.sprintViewportWidth / root.totalSprintContentWidth;
                                            return Math.max(36, Math.min(scrollTrack.width - 2, (scrollTrack.width - 2) * ratio));
                                        }

                                        x: {
                                            if (root.maxMatrixScrollX <= 0) return 1;
                                            var maxThumbX = scrollTrack.width - scrollThumb.width - 2;
                                            if (maxThumbX <= 0) return 1;
                                            var scrollRatio = root.matrixContentX / root.maxMatrixScrollX;
                                            return Math.max(1, Math.min(maxThumbX, 1 + scrollRatio * maxThumbX));
                                        }

                                        color: scrollThumbMa.pressed ? "#79c0ff" : (scrollThumbMa.hovered || scrollTrackMa.containsMouse ? "#58a6ff" : "#388bfd")

                                        // Central grip dots on thumb
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 2
                                            visible: scrollThumb.width > 50
                                            Rectangle { width: 2; height: 4; radius: 1; color: "#ffffff"; opacity: 0.8 }
                                            Rectangle { width: 2; height: 4; radius: 1; color: "#ffffff"; opacity: 0.8 }
                                            Rectangle { width: 2; height: 4; radius: 1; color: "#ffffff"; opacity: 0.8 }
                                        }

                                        MouseArea {
                                            id: scrollThumbMa
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            preventStealing: true

                                            property real startMouseX: 0
                                            property real startContentX: 0

                                            onPressed: function(mouse) {
                                                startMouseX = mouse.x;
                                                startContentX = root.matrixContentX;
                                            }

                                            onPositionChanged: function(mouse) {
                                                if (pressed) {
                                                    var deltaMouse = mouse.x - startMouseX;
                                                    var maxThumbX = scrollTrack.width - scrollThumb.width - 2;
                                                    if (maxThumbX > 0) {
                                                        var deltaContent = (deltaMouse / maxThumbX) * root.maxMatrixScrollX;
                                                        root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, startContentX + deltaContent));
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Track Click MouseArea for jump navigation
                                    MouseArea {
                                        id: scrollTrackMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        z: -1

                                        onPressed: function(mouse) {
                                            var clickX = mouse.x;
                                            var maxThumbX = scrollTrack.width - scrollThumb.width - 2;
                                            if (maxThumbX > 0) {
                                                var targetThumbX = clickX - (scrollThumb.width / 2);
                                                var ratio = Math.max(0, Math.min(1.0, targetThumbX / maxThumbX));
                                                root.matrixContentX = ratio * root.maxMatrixScrollX;
                                            }
                                        }

                                        onWheel: function(wheel) {
                                            if (wheel.angleDelta.x !== 0) {
                                                root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.x));
                                                wheel.accepted = true;
                                            } else if (wheel.angleDelta.y !== 0) {
                                                root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX - wheel.angleDelta.y));
                                                wheel.accepted = true;
                                            }
                                        }
                                    }
                                }
                            }

                            // Right spacer matching Total column
                            Item {
                                Layout.preferredWidth: root.totalColWidth
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 8
                                    spacing: 4

                                    // Step 1 Sprint Right Button
                                    Button {
                                        text: "▶"
                                        font.pixelSize: 10
                                        ToolTip.visible: hovered
                                        ToolTip.text: "Scroll 1 sprint right"
                                        contentItem: Text { text: parent.text; font: parent.font; color: parent.hovered ? "#58a6ff" : "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { implicitWidth: 20; implicitHeight: 18; radius: 3; color: parent.hovered ? "#21262d" : "transparent"; border.color: parent.hovered ? "#30363d" : "transparent" }
                                        onClicked: {
                                            root.matrixContentX = Math.max(0, Math.min(root.maxMatrixScrollX, root.matrixContentX + root.sprintColWidth));
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: {
                                            if (root.maxMatrixScrollX <= 0) return "";
                                            var pct = Math.round((root.matrixContentX / root.maxMatrixScrollX) * 100);
                                            return pct + "%";
                                        }
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty State Overlay inside Matrix Table
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    visible: matrixListView.count === 0

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "📭"
                        font.pixelSize: 36
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (root.hasActiveHierarchyFilters) {
                                return "No work items match current filter criteria";
                            }
                            if (root.matrixData && (root.matrixData.total_all_sprint_items || 0) > 0) {
                                return "No work items in visible sprint window (" + sprintRangeText.text + ")";
                            }
                            return "No work items found in sprint iterations";
                        }
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: "#e6edf3"
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !root.hasActiveHierarchyFilters && root.matrixData && (root.matrixData.total_all_sprint_items || 0) > 0
                        text: (root.matrixData ? (root.matrixData.total_all_sprint_items || 0) : 0) + " work items exist in project sprints up to " + (root.matrixData ? root.matrixData.latest_active_sprint_name : "")
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#8b949e"
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10
                        Button {
                            visible: !root.hasActiveHierarchyFilters && root.matrixData && (root.matrixData.total_all_sprint_items || 0) > 0
                            text: "◀  Jump to Active Sprints (" + (root.matrixData ? (root.matrixData.latest_active_sprint_label || root.matrixData.latest_active_sprint_name || "") : "") + ")"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 34
                                implicitWidth: 230
                                radius: 6
                                color: parent.hovered ? "#2ea043" : "#238636"
                                border.color: "#3fb950"
                            }
                            onClicked: {
                                if (root.matrixData && root.matrixData.suggested_lookback_offset !== undefined) {
                                    root.historyOffset = root.matrixData.suggested_lookback_offset;
                                }
                            }
                        }
                        Button {
                            visible: root.hasActiveHierarchyFilters
                            text: "Reset All Filters"
                            font.pixelSize: 12
                            onClicked: root.resetHierarchyFilters()
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

    PrepareIterationsModal {
        id: workloadPrepareModal
        onIterationsPrepared: function(result) {
            root.refreshMatrix();
        }
    }
}


