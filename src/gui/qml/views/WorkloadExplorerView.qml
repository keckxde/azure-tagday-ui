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
    property bool prio1Only: false
    property bool groupedOnly: false
    property real drawerWidth: 540
    property var level1List: ["ALL"]
    property var level2List: ["ALL"]

    // Horizontal Matrix Scrolling Properties
    property real matrixContentX: 0
    property int matrixSprintCount: root.matrixData && root.matrixData.sprint_columns ? root.matrixData.sprint_columns.length : 0
    property real minSprintColWidth: 155
    property real teamMemberColWidth: 220
    property real totalColWidth: 100
    property real sprintViewportWidth: Math.max(100, (matrixTableContainer.width - root.teamMemberColWidth - root.totalColWidth))
    property real sprintColWidth: Math.max(root.minSprintColWidth, root.matrixSprintCount > 0 ? (root.sprintViewportWidth / root.matrixSprintCount) : root.minSprintColWidth)
    property real totalSprintContentWidth: root.matrixSprintCount * root.sprintColWidth
    property real maxMatrixScrollX: Math.max(0, root.totalSprintContentWidth - root.sprintViewportWidth)

    onMaxMatrixScrollXChanged: {
        if (matrixContentX > maxMatrixScrollX) {
            matrixContentX = maxMatrixScrollX;
        }
    }

    function refreshHierarchyLists() {
        if (!backend) return;
        var l1 = backend.workItemLevel1List || [];
        level1List = ["ALL"].concat(l1).concat(["[ WITHOUT [<NR>] SYNTAX ]", "UNGROUPED"]);
        var l2 = backend.workItemLevel2List || [];
        level2List = ["ALL"].concat(l2).concat(["[ WITHOUT [<NR>] SYNTAX ]", "UNGROUPED"]);
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

    function refreshMatrix() {
        if (!backend) return
        refreshHierarchyLists()
        matrixData = backend.getWorkloadMatrix(
            root.selectedHorizon,
            root.filterLevel1 || "ALL",
            root.filterLevel2 || "ALL",
            !!root.prio1Only,
            !!root.groupedOnly,
            !!root.hideClosedTasks,
            root.searchQuery || ""
        )
    }

    property bool hasActiveHierarchyFilters: (root.filterLevel1 || "ALL") !== "ALL" || (root.filterLevel2 || "ALL") !== "ALL" || root.prio1Only || root.groupedOnly || root.hideClosedTasks || root.searchQuery !== ""

    function resetHierarchyFilters() {
        root.filterLevel1 = "ALL"
        root.filterLevel2 = "ALL"
        root.prio1Only = false
        root.groupedOnly = false
        root.hideClosedTasks = false
        root.searchQuery = ""
        refreshMatrix()
    }

    onSelectedHorizonChanged: refreshMatrix()
    onFilterLevel1Changed:    refreshMatrix()
    onFilterLevel2Changed:    refreshMatrix()
    onPrio1OnlyChanged:       refreshMatrix()
    onGroupedOnlyChanged:     refreshMatrix()
    onHideClosedTasksChanged: refreshMatrix()
    onSearchQueryChanged:     refreshMatrix()

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
                text: "🚩 Milestones"
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
                    implicitWidth: 105
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
                        height: 58
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
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: modelData.start_date ? (modelData.start_date.substring(5) + " · " + modelData.end_date.substring(5)) : ""
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
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
                                                    ToolTip.text: modelData.name + " (" + (modelData.category_name || "Milestone") + ")\nDate: " + modelData.target_date + (modelData.description ? ("\n" + modelData.description) : "") + "\n(Click to manage)"

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

                                                    // Type tags breakdown
                                                    Row {
                                                        spacing: 3
                                                        Text { text: "🎯" + modelData.stories_count; font.pixelSize: 10; visible: modelData.stories_count > 0 }
                                                        Text { text: "🐛" + modelData.bugs_count; font.pixelSize: 10; visible: modelData.bugs_count > 0 }
                                                        Text { text: "🛠️" + modelData.tasks_count; font.pixelSize: 10; visible: modelData.tasks_count > 0 }
                                                        Text { text: "🚨" + modelData.overdue_count; font.pixelSize: 10; visible: modelData.overdue_count > 0 }
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
                                                        root.selectedCell = {
                                                            assignee: modelData.assignee || "Team Member",
                                                            sprint_name: modelData.sprint_name,
                                                            total_count: modelData.total_count || 0,
                                                            stories_count: modelData.stories_count || 0,
                                                            bugs_count: modelData.bugs_count || 0,
                                                            tasks_count: modelData.tasks_count || 0,
                                                            tasks_not_started_count: modelData.tasks_not_started_count || 0,
                                                            tasks_active_count: modelData.tasks_active_count || 0,
                                                            tasks_closed_count: modelData.tasks_closed_count || 0,
                                                            tasks_closed_percent: modelData.tasks_closed_percent !== undefined ? modelData.tasks_closed_percent : Math.round(((modelData.tasks_closed_count || 0) / Math.max(1, modelData.tasks_count || 1)) * 100),
                                                            not_started_count: modelData.not_started_count || 0,
                                                            active_count: modelData.active_count || 0,
                                                            overdue_count: modelData.overdue_count || 0,
                                                            completed_count: modelData.completed_count || 0,
                                                            grouped_containers: modelData.grouped_containers || [],
                                                            items: modelData.items || []
                                                        }
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

                                // Assignee Horizon Total
                                Item {
                                    Layout.preferredWidth: 100
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
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: (modelData.total_count || 0) + " items"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
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
        width: Math.max(380, Math.min(root.width - 80, root.drawerWidth))
        visible: root.selectedCell !== null
        color: "#161b22"
        border.color: "#30363d"
        border.width: 1

        // Left Edge Resizer Handle / Splitter
        Rectangle {
            id: drawerResizer
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 6
            z: 100
            color: drawerResizerMa.containsMouse || drawerResizerMa.pressed ? "#58a6ff" : "transparent"

            // Central Grip Indicator
            Column {
                anchors.centerIn: parent
                spacing: 3
                visible: drawerResizerMa.containsMouse || drawerResizerMa.pressed
                Rectangle { width: 2; height: 8; radius: 1; color: "#ffffff" }
                Rectangle { width: 2; height: 8; radius: 1; color: "#ffffff" }
                Rectangle { width: 2; height: 8; radius: 1; color: "#ffffff" }
            }

            MouseArea {
                id: drawerResizerMa
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                preventStealing: true

                property real startMouseX: 0
                property real startWidth: 0

                onPressed: function(mouse) {
                    startMouseX = mouse.x;
                    startWidth = detailDrawer.width;
                }

                onPositionChanged: function(mouse) {
                    if (pressed) {
                        var diff = mouse.x - startMouseX;
                        var newWidth = detailDrawer.width - diff;
                        var minW = 380;
                        var maxW = Math.max(minW, root.width - 80);
                        root.drawerWidth = Math.max(minW, Math.min(maxW, newWidth));
                    }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 16
            anchors.topMargin: 16
            anchors.bottomMargin: 16
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

                    // Task status relation pill
                    RowLayout {
                        spacing: 6
                        visible: root.selectedCell && (root.selectedCell.tasks_count || 0) > 0

                        Text {
                            text: "🛠️ " + (root.selectedCell ? root.selectedCell.tasks_count : 0) + " tasks:"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }
                        Text {
                            text: "⏳ " + (root.selectedCell ? (root.selectedCell.tasks_not_started_count || 0) : 0) + " Not Started"
                            font.pixelSize: 10
                            color: "#8b949e"
                        }
                        Text {
                            text: "⚡ " + (root.selectedCell ? (root.selectedCell.tasks_active_count || 0) : 0) + " Active"
                            font.pixelSize: 10
                            color: "#58a6ff"
                        }
                        Text {
                            text: "✅ " + (root.selectedCell ? (root.selectedCell.tasks_closed_percent !== undefined ? root.selectedCell.tasks_closed_percent : Math.round(((root.selectedCell.tasks_closed_count || 0) / Math.max(1, root.selectedCell.tasks_count || 1)) * 100)) : 0) + "% Closed (" + (root.selectedCell ? (root.selectedCell.tasks_closed_count || 0) : 0) + "/" + (root.selectedCell ? (root.selectedCell.tasks_count || 0) : 0) + ")"
                            font.pixelSize: 10
                            color: "#3fb950"
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
                        visible: root.hideClosedTasks && root.selectedCell && (root.selectedCell.completed_count || 0) > 0
                        text: "✓ " + (root.selectedCell ? (root.selectedCell.completed_count || 0) : 0) + " closed hidden"
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

                        // ==================== Parent Header Line (Line 1: Type, ID, Badges, Owner, State) ====================
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
                                        if (t.indexOf("feature") !== -1) return "🎯";
                                        if (t.indexOf("epic") !== -1) return "👑";
                                        if (t.indexOf("req") !== -1) return "📋";
                                        if (t.indexOf("standalone") !== -1 || modelData.id === 0) return "🛠️";
                                        return "📘";
                                    }
                                    font.pixelSize: 14
                                }

                                Text {
                                    text: modelData.id > 0 ? ("#" + modelData.id) : "Direct"
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 12
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

                            // External Parent Indicator Badge
                            Rectangle {
                                visible: !!modelData.is_external_parent
                                implicitHeight: 20
                                implicitWidth: cExtLabel.implicitWidth + 10
                                radius: 10
                                color: "#16243b"
                                border.color: "#1f6feb"
                                Text {
                                    id: cExtLabel
                                    anchors.centerIn: parent
                                    text: "🌐 External Parent"
                                    font.pixelSize: 9
                                    color: "#58a6ff"
                                }
                            }

                            // Prio 1 Strategic Focus Badge
                            Rectangle {
                                visible: !!modelData.is_prio1
                                implicitHeight: 20
                                implicitWidth: cPrioText.implicitWidth + 10
                                radius: 4
                                color: "#3d2800"
                                border.color: "#d29922"
                                border.width: 1
                                Text {
                                    id: cPrioText
                                    anchors.centerIn: parent
                                    text: modelData.prio_badge || "⭐ Prio 1"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#f0883e"
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Owner / Assignee pill
                            Rectangle {
                                implicitHeight: 20
                                implicitWidth: cOwnerText.implicitWidth + 12
                                radius: 10
                                color: "#161b22"
                                border.color: "#30363d"
                                Text {
                                    id: cOwnerText
                                    anchors.centerIn: parent
                                    text: "👤 " + (modelData.assigned_to || "Unassigned")
                                    font.pixelSize: 10
                                    color: "#c9d1d9"
                                }
                            }

                            // State badge
                            Rectangle {
                                visible: modelData.id > 0
                                implicitHeight: 20
                                implicitWidth: cStateLabel.implicitWidth + 12
                                radius: 10
                                color: modelData.is_done ? "#0d3525" : (modelData.state === "Proposed" ? "#2d2006" : "#161b22")
                                border.color: modelData.is_done ? "#3fb950" : (modelData.state === "Proposed" ? "#d29922" : "#30363d")
                                Text {
                                    id: cStateLabel
                                    anchors.centerIn: parent
                                    text: modelData.state || "Active"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: modelData.is_done ? "#3fb950" : (modelData.state === "Proposed" ? "#d29922" : "#58a6ff")
                                }
                            }
                        }

                        // ==================== Parent Title (Line 2: Prominent & Full-Width) ====================
                        Text {
                            Layout.fillWidth: true
                            text: modelData.title || (modelData.id > 0 ? ("Work Item #" + modelData.id) : "Direct Tasks / Standalone Items")
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: cardTitleMa.containsMouse && (modelData.tfs_url || "") !== "" ? "#58a6ff" : "#f0f6fc"
                            wrapMode: Text.Wrap

                            ToolTip.visible: cardTitleMa.containsMouse
                            ToolTip.text: (modelData.title || "") + ((modelData.tfs_url || "") !== "" ? "\n(Click to open in TFS)" : "")

                            MouseArea {
                                id: cardTitleMa
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

                        // ==================== Metadata & Schedule (Line 2: Iteration, Deadline, PBS Breadcrumbs) ====================
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Move / Planned Iteration Pill
                            Rectangle {
                                visible: modelData.id > 0
                                implicitHeight: 22
                                implicitWidth: cSprintRow.implicitWidth + 12
                                radius: 11
                                color: "#161b22"
                                border.color: cEditSprintMa.containsMouse ? "#58a6ff" : "#30363d"
                                border.width: 1

                                RowLayout {
                                    id: cSprintRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text { text: "🔄"; font.pixelSize: 10 }
                                    Text {
                                        text: modelData.iteration_path ? modelData.iteration_path.split("\\").pop() : (root.selectedCell ? root.selectedCell.sprint_name : "Sprint")
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: "#58a6ff"
                                    }
                                }
                                ToolTip.visible: cEditSprintMa.containsMouse
                                ToolTip.text: "Planned Iteration: " + (modelData.iteration_path || "Sprint") + "\n(Click to reschedule)"

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

                            // Deadline Pill
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
                                        text: parent.parent.hasDate ? (modelData.urgency_badge || modelData.deadline_str) : "➕ Set Date"
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

                            // Milestone Pill (if workitem is matched to a major milestone)
                            Rectangle {
                                visible: (modelData.milestone_name || "") !== ""
                                implicitHeight: 22
                                implicitWidth: cMStoneRow.implicitWidth + 12
                                radius: 11
                                color: modelData.milestone_bg || "#16243b"
                                border.color: modelData.milestone_color || "#1f6feb"
                                border.width: 1

                                RowLayout {
                                    id: cMStoneRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: modelData.milestone_icon || "🚩"
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        text: modelData.milestone_name
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: modelData.milestone_color || "#79c0ff"
                                    }
                                }
                                ToolTip.visible: cMStoneMa.containsMouse
                                ToolTip.text: "Major Milestone: " + (modelData.milestone_name || "") + " (" + (modelData.milestone_category || "") + ")"
                                MouseArea {
                                    id: cMStoneMa
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

                            // Hierarchy / PBS Breadcrumb Chip
                            Rectangle {
                                visible: (modelData.level1_display || "") !== "" && modelData.level1_display !== "Ungrouped Sub-System"
                                implicitHeight: 20
                                implicitWidth: cHierarchyText.implicitWidth + 10
                                radius: 4
                                color: "#161b22"
                                border.color: modelData.is_grouped ? "#30363d" : "#da3633"
                                border.width: 1
                                Text {
                                    id: cHierarchyText
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
                                implicitWidth: cUngroupedText.implicitWidth + 8
                                radius: 4
                                color: "#2d1515"
                                border.color: "#da3633"
                                border.width: 1
                                Text {
                                    id: cUngroupedText
                                    anchors.centerIn: parent
                                    text: "⚠️ Ungrouped (No PBS)"
                                    font.pixelSize: 9
                                    color: "#f85149"
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Tasks summary count & relation pill
                            RowLayout {
                                visible: (modelData.total_tasks_count || 0) > 0
                                spacing: 8

                                Row {
                                    spacing: 4
                                    Text {
                                        text: "⏳" + (modelData.tasks_not_started_count || 0)
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                        visible: (modelData.tasks_not_started_count || 0) > 0
                                    }
                                    Text {
                                        text: "⚡" + (modelData.tasks_active_count || 0)
                                        font.pixelSize: 10
                                        color: "#58a6ff"
                                        visible: (modelData.tasks_active_count || 0) > 0
                                    }
                                    Text {
                                        text: "✅" + (modelData.progress_percent !== undefined ? modelData.progress_percent : Math.round(((modelData.tasks_closed_count || 0) / Math.max(1, modelData.total_tasks_count || 1)) * 100)) + "%"
                                        font.pixelSize: 10
                                        color: "#3fb950"
                                        visible: (modelData.tasks_closed_count || 0) > 0
                                    }
                                }

                                Text {
                                    text: "(" + (modelData.completed_tasks_count || 0) + "/" + (modelData.total_tasks_count || 0) + " done · " + (modelData.progress_percent || 0) + "%)"
                                    font.pixelSize: 10
                                    color: modelData.progress_percent === 100 ? "#3fb950" : "#8b949e"
                                }
                            }
                        }

                        // Tasks Progress Bar (3-segment: Closed ✅ Green, Active ⚡ Blue, Not Started ⏳ Slate)
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
                                                text: modelData.title || (modelData.id > 0 ? ("Task #" + modelData.id) : "")
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                color: modelData.is_done ? "#8b949e" : "#e6edf3"
                                                elide: Text.ElideRight
                                                ToolTip.visible: taskMa.containsMouse && (modelData.title || "").length > 30
                                                ToolTip.text: modelData.title || ""
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

                                            // Milestone Pill in Task Row
                                            Rectangle {
                                                visible: (modelData.milestone_name || "") !== ""
                                                implicitHeight: 18
                                                implicitWidth: tkMStoneRow.implicitWidth + 8
                                                radius: 9
                                                color: modelData.milestone_bg || "#16243b"
                                                border.color: modelData.milestone_color || "#1f6feb"
                                                Row {
                                                    id: tkMStoneRow
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
                                                ToolTip.visible: tkMStoneMa.containsMouse
                                                ToolTip.text: "Milestone: " + (modelData.milestone_name || "") + " (" + (modelData.milestone_category || "") + ")"
                                                MouseArea {
                                                    id: tkMStoneMa
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

