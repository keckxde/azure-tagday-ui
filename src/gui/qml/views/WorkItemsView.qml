import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root
    property string searchQuery: ""
    property string filterState: "ALL"       // "ALL", "ACTIVE", "DELETED", or specific state
    property string filterType: "ALL"        // "ALL" or specific WI type
    property string filterAssignee: "ALL"    // "ALL", "UNASSIGNED", or specific user
    property string filterModified: "ALL"    // "ALL", "7", "14", "30" (days)
    property string filterIteration: "ALL"   // "ALL", "PLANNED", "UNPLANNED", or specific iteration name
    property string filterUrgency: "ALL"     // "ALL", "OVERDUE", "DUE_THIS_WEEK", "DUE_NEXT_WEEK", "FUTURE", "COMPLETED"
    property int currentPage: 1
    property int pageSize: 25
    property int totalPages: 1
    property int totalMatchingCount: 0

    // -- Filter lists, updated dynamically from database cache --
    property var typesList: []
    property var statesList: []
    property var assigneesList: ["ALL"]
    property var iterationsList: ["ALL"]

    property var urgencyOptions: [
        { label: "All Deadlines", value: "ALL" },
        { label: "🚨 Overdue", value: "OVERDUE" },
        { label: "⏳ Due This Week", value: "DUE_THIS_WEEK" },
        { label: "📅 Due Next Week", value: "DUE_NEXT_WEEK" },
        { label: "🔮 Upcoming", value: "FUTURE" }
    ]

    property var modifiedOptions: [
        { label: "All Time", value: "ALL" },
        { label: "Last 7 Days", value: "7" },
        { label: "Last 14 Days", value: "14" },
        { label: "Last 30 Days", value: "30" }
    ]

    function refreshTypesList() {
        if (!backend) return
        var types = backend.workItemTypes || []
        typesList = ["ALL"].concat(types)
    }

    function refreshStatesList() {
        if (!backend) return
        var states = backend.workItemStates || []
        statesList = ["ALL"].concat(states).concat(["DELETED"])
    }

    function refreshAssigneesList() {
        if (!backend) return
        var assignees = backend.workItemAssignees || []
        assigneesList = ["ALL", "UNASSIGNED"].concat(assignees)
    }

    function refreshIterationsList() {
        if (!backend) return
        var iters = backend.workItemIterations || []
        iterationsList = ["ALL", "PLANNED", "UNPLANNED"].concat(iters)
    }

    function resetAllFilters() {
        root.searchQuery = ""
        root.filterState = "ALL"
        root.filterType = "ALL"
        root.filterAssignee = "ALL"
        root.filterModified = "ALL"
        root.filterIteration = "ALL"
        root.filterUrgency = "ALL"
        root.currentPage = 1
        root.updateFilteredModel()
    }

    property bool hasActiveFilters: root.searchQuery !== "" || root.filterState !== "ALL" || root.filterType !== "ALL" || root.filterAssignee !== "ALL" || root.filterModified !== "ALL" || root.filterIteration !== "ALL" || root.filterUrgency !== "ALL"

    function isWithinDays(dateStr, maxDays) {
        if (!dateStr) return false;
        var clean = dateStr.replace("Z", "").replace(" ", "T");
        var d = new Date(clean);
        if (isNaN(d.getTime())) {
            d = new Date(dateStr);
        }
        if (isNaN(d.getTime())) return false;
        var now = new Date();
        var diffMs = now.getTime() - d.getTime();
        var diffDays = diffMs / (1000 * 60 * 60 * 24);
        return diffDays <= maxDays && diffDays >= -0.5;
    }

    // ========================
    // Color helpers
    // ========================
    function typeColor(t) {
        switch((t || "").toLowerCase()) {
            case "bug":         return "#da3633"
            case "feature":     return "#388bfd"
            case "epic":        return "#8250df"
            case "requirement": return "#1a7f37"
            case "task":        return "#d29922"
            case "test case":   return "#0969da"
            case "test plan":   return "#0969da"
            case "test suite":  return "#0969da"
            default:            return "#6e7681"
        }
    }

    function stateColor(s, deleted) {
        if (deleted) return "#f85149"
        switch ((s || "").toLowerCase()) {
            case "closed": case "done":       return "#3fb950"
            case "resolved":                  return "#2ea043"
            case "active": case "in progress": return "#d29922"
            case "in planning":               return "#a371f7"
            case "proposed":                  return "#bf8700"
            case "new": case "open": case "to do": return "#388bfd"
            case "removed": case "cut":       return "#f85149"
            default:                          return "#8b949e"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        // ====================== Top Toolbar ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "Work Items"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 18
                font.weight: Font.Bold
                color: "#f0f6fc"
            }

            Text {
                text: "(" + root.totalMatchingCount + " items)"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 14
                color: "#8b949e"
            }

            Item { Layout.fillWidth: true }

            SearchBar {
                placeholder: "Search ID, Title, Assignee, Tag..."
                onSearchUpdated: function(query) {
                    root.searchQuery = query
                    root.currentPage = 1
                }
            }

            Button {
                text: "⚡ Sync WIQL"
                enabled: backend ? !backend.isBusy : false
                font.weight: Font.DemiBold
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 34
                    implicitWidth: 110
                    radius: 6
                    color: parent.enabled ? (parent.hovered ? "#388bfd" : "#1f6feb") : "#30363d"
                }
                onClicked: {
                    if (backend)
                        backend.sync_work_items_async();
                }
            }
        }

        // ====================== State Filter Row ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "State:"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "#8b949e"
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 42
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.statesList
                    Button {
                        text: modelData === "ALL" ? "All States" : (modelData === "DELETED" ? "Deleted" : modelData)
                        checkable: true
                        checked: root.filterState === modelData
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
                            implicitHeight: 26
                            implicitWidth: stateLabel.implicitWidth + 20
                            radius: 13
                            property color stateC: {
                                if (modelData === "ALL") return "#1f6feb"
                                if (modelData === "DELETED") return "#da3633"
                                return root.stateColor(modelData, false)
                            }
                            color: parent.checked ? stateC : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? Qt.lighter(stateC, 1.3) : "#30363d"
                            Text {
                                id: stateLabel
                                text: parent.parent.text
                                visible: false
                            }
                        }
                        onClicked: {
                            root.filterState = modelData
                            root.currentPage = 1
                        }
                    }
                }
            }
        }

        // ====================== Type Filter Row ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Type:"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "#8b949e"
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 54
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.typesList
                    Button {
                        text: modelData === "ALL" ? "All Types" : modelData
                        checkable: true
                        checked: root.filterType === modelData
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
                            implicitHeight: 26
                            implicitWidth: typeLabel.implicitWidth + 20
                            radius: 13
                            property color typeC: modelData === "ALL" ? "#1f6feb" : root.typeColor(modelData)
                            color: parent.checked ? typeC : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? Qt.lighter(typeC, 1.3) : "#30363d"
                            Text {
                                id: typeLabel
                                text: parent.parent.text
                                visible: false
                            }
                        }
                        onClicked: {
                            root.filterType = modelData
                            root.currentPage = 1
                        }
                    }
                }
            }
        }

        // ====================== Deadline Urgency Filter Row ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Deadline:"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "#8b949e"
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 54
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.urgencyOptions
                    Button {
                        text: modelData.label
                        checkable: true
                        checked: root.filterUrgency === modelData.value
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
                            implicitHeight: 26
                            implicitWidth: urgLabel.implicitWidth + 20
                            radius: 13
                            property color urgC: {
                                if (modelData.value === "OVERDUE") return "#f85149"
                                if (modelData.value === "DUE_THIS_WEEK") return "#d29922"
                                if (modelData.value === "DUE_NEXT_WEEK") return "#388bfd"
                                if (modelData.value === "FUTURE") return "#58a6ff"
                                return "#1f6feb"
                            }
                            color: parent.checked ? urgC : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? Qt.lighter(urgC, 1.3) : "#30363d"
                            Text {
                                id: urgLabel
                                text: parent.parent.text
                                visible: false
                            }
                        }
                        onClicked: {
                            root.filterUrgency = modelData.value
                            root.currentPage = 1
                        }
                    }
                }
            }
        }

        // ====================== Additional Filters Row (Modified, User, Iteration) ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Modified Date Filter
            RowLayout {
                spacing: 6
                Text {
                    text: "Modified:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                Repeater {
                    model: root.modifiedOptions
                    Button {
                        text: modelData.label
                        checkable: true
                        checked: root.filterModified === modelData.value
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
                            implicitHeight: 26
                            implicitWidth: modLabel.implicitWidth + 18
                            radius: 13
                            color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? "#388bfd" : "#30363d"
                            Text { id: modLabel; text: parent.parent.text; visible: false }
                        }
                        onClicked: {
                            root.filterModified = modelData.value
                            root.currentPage = 1
                        }
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // Assignee / User Filter
            RowLayout {
                spacing: 6
                Text {
                    text: "User:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: assigneeCombo
                    implicitWidth: 170
                    implicitHeight: 28
                    font.pixelSize: 11
                    model: root.assigneesList
                    currentIndex: {
                        var idx = root.assigneesList.indexOf(root.filterAssignee)
                        return idx >= 0 ? idx : 0
                    }
                    displayText: {
                        if (currentIndex === 0 || currentText === "ALL") return "All Users"
                        if (currentIndex === 1 || currentText === "UNASSIGNED") return "Unassigned"
                        return currentText
                    }
                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: assigneeCombo.hovered || assigneeCombo.activeFocus ? "#58a6ff" : (root.filterAssignee !== "ALL" ? "#1f6feb" : "#30363d")
                    }
                    contentItem: Text {
                        leftPadding: 8
                        rightPadding: 24
                        text: assigneeCombo.displayText
                        font: assigneeCombo.font
                        color: root.filterAssignee !== "ALL" ? "#58a6ff" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    onActivated: function(index) {
                        var val = root.assigneesList[index] || "ALL"
                        root.filterAssignee = val
                        root.currentPage = 1
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // Iteration Filter
            RowLayout {
                spacing: 6
                Text {
                    text: "Iteration:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                Row {
                    spacing: 4
                    Button {
                        text: "All"
                        checkable: true
                        checked: root.filterIteration === "ALL"
                        font.pixelSize: 11
                        font.weight: checked ? Font.DemiBold : Font.Normal
                        contentItem: Text {
                            text: parent.text; font: parent.font
                            color: parent.checked ? "#ffffff" : "#8b949e"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 26; implicitWidth: 38; radius: 13
                            color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? "#388bfd" : "#30363d"
                        }
                        onClicked: {
                            root.filterIteration = "ALL"
                            root.currentPage = 1
                        }
                    }

                    Button {
                        text: "🎯 Planned"
                        checkable: true
                        checked: root.filterIteration === "PLANNED"
                        font.pixelSize: 11
                        font.weight: checked ? Font.DemiBold : Font.Normal
                        contentItem: Text {
                            text: parent.text; font: parent.font
                            color: parent.checked ? "#ffffff" : "#58a6ff"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 26; implicitWidth: 80; radius: 13
                            color: parent.checked ? "#0d2344" : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? "#1f6feb" : "#30363d"
                        }
                        onClicked: {
                            root.filterIteration = "PLANNED"
                            root.currentPage = 1
                        }
                    }

                    Button {
                        text: "📋 Backlog"
                        checkable: true
                        checked: root.filterIteration === "UNPLANNED"
                        font.pixelSize: 11
                        font.weight: checked ? Font.DemiBold : Font.Normal
                        contentItem: Text {
                            text: parent.text; font: parent.font
                            color: parent.checked ? "#ffffff" : "#8b949e"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 26; implicitWidth: 78; radius: 13
                            color: parent.checked ? "#30363d" : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? "#8b949e" : "#30363d"
                        }
                        onClicked: {
                            root.filterIteration = "UNPLANNED"
                            root.currentPage = 1
                        }
                    }
                }

                ComboBox {
                    id: iterationCombo
                    implicitWidth: 175
                    implicitHeight: 28
                    font.pixelSize: 11
                    model: root.iterationsList
                    currentIndex: {
                        var idx = root.iterationsList.indexOf(root.filterIteration)
                        return idx >= 0 ? idx : 0
                    }
                    displayText: {
                        if (currentIndex === 0 || currentText === "ALL") return "Specific Sprint..."
                        if (currentIndex === 1 || currentText === "PLANNED") return "🎯 Planned (Any)"
                        if (currentIndex === 2 || currentText === "UNPLANNED") return "📋 Unplanned (Backlog)"
                        return "🎯 " + currentText
                    }
                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: iterationCombo.hovered || iterationCombo.activeFocus ? "#58a6ff" : ((root.filterIteration !== "ALL" && root.filterIteration !== "PLANNED" && root.filterIteration !== "UNPLANNED") ? "#1f6feb" : "#30363d")
                    }
                    contentItem: Text {
                        leftPadding: 8
                        rightPadding: 24
                        text: iterationCombo.displayText
                        font: iterationCombo.font
                        color: (root.filterIteration !== "ALL" && root.filterIteration !== "PLANNED" && root.filterIteration !== "UNPLANNED") ? "#58a6ff" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    onActivated: function(index) {
                        var val = root.iterationsList[index] || "ALL"
                        root.filterIteration = val
                        root.currentPage = 1
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Clear / Reset filters button
            Button {
                visible: root.hasActiveFilters
                text: "✖ Reset Filters"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                contentItem: Text {
                    text: parent.text; font: parent.font
                    color: "#f85149"
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 26; implicitWidth: 96; radius: 6
                    color: parent.hovered ? "#3c1e1e" : "#211515"
                    border.color: "#da3633"
                }
                onClicked: root.resetAllFilters()
            }
        }

        // ====================== Table Header ======================
        Rectangle {
            Layout.fillWidth: true
            height: 36
            color: "#161b22"
            radius: 6
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 24
                spacing: 12

                Text { text: "ID";          Layout.preferredWidth: 64;  font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "TYPE";        Layout.preferredWidth: 92;  font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "TITLE";       Layout.fillWidth: true;     font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "STATE";       Layout.preferredWidth: 88;  font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "ITERATION";   Layout.preferredWidth: 125; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "DEADLINE";    Layout.preferredWidth: 115; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "ASSIGNED TO"; Layout.preferredWidth: 115; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "REFS";        Layout.preferredWidth: 75;  font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "LINK";        Layout.preferredWidth: 45;  font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
            }
        }

        // ====================== Work Items List ======================
        ListView {
            id: wiListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3

            model: ListModel { id: filteredWorkItems }

            ScrollBar.vertical: ScrollBar {
                id: vbar
                active: true
                policy: ScrollBar.AlwaysOn
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: vbar.pressed ? "#58a6ff" : (vbar.hovered ? "#8b949e" : "#30363d")
                }
                background: Rectangle { implicitWidth: 6; color: "transparent" }
            }

            delegate: Item {
                width: wiListView.width - 14
                height: expanded ? expandedHeight + 52 : 52

                property bool expanded: false
                property int expandedHeight: {
                    var prs = model.linked_prs || []
                    var repos = model.linked_repos || []
                    return Math.max(48, 40 + prs.length * 20 + repos.length * 18 + 32)
                }

                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    color: itemMouse.containsMouse ? "#1c2128" : "#0d1117"
                    radius: 6
                    border.color: {
                        if (model.deleted) return "#f85149"
                        if (model.urgency_status === "overdue") return "#da3633"
                        if (itemMouse.containsMouse) return "#388bfd"
                        return "#21262d"
                    }
                    border.width: 1
                    clip: true

                    // Row click area - follows TFS link when clicking anywhere on the work item row
                    MouseArea {
                        id: itemMouse
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 52
                        hoverEnabled: true
                        cursorShape: (model.tfs_url || "") !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        ToolTip.visible: containsMouse && (model.tfs_url || "") !== ""
                        ToolTip.text: "Open in TFS: #" + model.id + " - " + model.title
                        onClicked: {
                            if (backend && (model.tfs_url || "") !== "") {
                                backend.open_url(model.tfs_url)
                            }
                        }
                    }

                    // ---- Main Row ----
                    RowLayout {
                        id: mainRow
                        z: 1
                        width: parent.width
                        height: 52
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        // ID
                        Text {
                            text: "#" + model.id
                            Layout.preferredWidth: 64
                            font.family: "Consolas, monospace"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: model.deleted ? "#f85149" : "#58a6ff"
                        }

                        // Type badge
                        Rectangle {
                            Layout.preferredWidth: 92
                            height: 22
                            radius: 11
                            property color typeC: root.typeColor(model.type)
                            color: Qt.rgba(typeC.r, typeC.g, typeC.b, 0.15)
                            border.color: Qt.rgba(typeC.r, typeC.g, typeC.b, 0.5)
                            Text {
                                anchors.centerIn: parent
                                text: model.type || "Task"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: root.typeColor(model.type)
                                elide: Text.ElideRight
                            }
                        }

                        // Title & Shift Badge
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: model.title
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                color: model.deleted ? "#8b949e" : "#f0f6fc"
                                font.strikeout: model.deleted
                                elide: Text.ElideRight
                            }

                            // Shift / Delay indicator badge
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: sBadgeText.implicitWidth + 10
                                radius: 9
                                visible: (model.shift_badge || "") !== ""
                                color: "#3c1e1e"
                                border.color: "#da3633"
                                border.width: 1

                                Text {
                                    id: sBadgeText
                                    anchors.centerIn: parent
                                    text: model.shift_badge || ""
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#f85149"
                                }

                                ToolTip.visible: sBadgeMa.containsMouse
                                ToolTip.text: "Iteration Shift History:\nThis item has been postponed or moved " + (model.shift_count || 1) + " time(s).\nTotal Delay: +" + (model.total_delayed_weeks || 0) + " week(s)."

                                MouseArea {
                                    id: sBadgeMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        iterationModal.openForWorkItem(model.id, model.title, model.iteration_name);
                                    }
                                }
                            }
                        }

                        // State
                        Text {
                            text: model.state
                            Layout.preferredWidth: 88
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: root.stateColor(model.state, model.deleted)
                            elide: Text.ElideRight
                        }

                        // Iteration Pill (Clickable / Reschedule)
                        Rectangle {
                            Layout.preferredWidth: 125
                            height: 24
                            radius: 12
                            color: iterMa.containsMouse ? (model.is_iteration_planned ? "#163c75" : "#21262d") : (model.is_iteration_planned ? "#0d2344" : "#161b22")
                            border.color: iterMa.containsMouse ? "#58a6ff" : (model.is_iteration_planned ? "#1f6feb" : "#30363d")
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 4

                                Text {
                                    text: model.is_iteration_planned ? "🎯" : "📋"
                                    font.pixelSize: 10
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.is_iteration_planned ? (model.iteration_name || "Planned") : (model.iteration_name && model.iteration_name !== "CH_SAPH_KAWEST" ? model.iteration_name : "Unplanned")
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: model.is_iteration_planned ? Font.DemiBold : Font.Normal
                                    color: model.is_iteration_planned ? "#58a6ff" : "#8b949e"
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: iterMa.containsMouse
                                    text: "✏️"
                                    font.pixelSize: 9
                                }
                            }

                            ToolTip.visible: iterMa.containsMouse
                            ToolTip.text: {
                                var txt = "";
                                if (model.is_iteration_planned) {
                                    txt = "Planned Iteration: " + (model.iteration_name || "Sprint") + "\nPath: " + (model.iteration_path || model.iteration_name);
                                } else {
                                    txt = "Not planned in an iteration\nPath: " + (model.iteration_path || "Project Root / Backlog");
                                }
                                return txt + "\n(Click to reschedule / move sprint)";
                            }

                            MouseArea {
                                id: iterMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    iterationModal.openForWorkItem(model.id, model.title, model.iteration_name);
                                }
                            }
                        }

                        // Deadline & Urgency Pill (Clickable / Editable)
                        Rectangle {
                            Layout.preferredWidth: 115
                            height: 22
                            radius: 11
                            property bool hasDeadline: (model.deadline_str || "") !== ""
                            property color uColor: model.urgency_color || "#8b949e"
                            color: deadMa.containsMouse ? (hasDeadline ? Qt.rgba(uColor.r, uColor.g, uColor.b, 0.25) : "#21262d") : (hasDeadline ? Qt.rgba(uColor.r, uColor.g, uColor.b, 0.15) : "#161b22")
                            border.color: deadMa.containsMouse ? "#58a6ff" : (hasDeadline ? Qt.rgba(uColor.r, uColor.g, uColor.b, 0.5) : "#30363d")
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: parent.parent.hasDeadline ? (model.urgency_badge || model.deadline_str || "—") : "➕ Set Date"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    font.weight: parent.parent.hasDeadline ? Font.DemiBold : Font.Normal
                                    color: parent.parent.hasDeadline ? parent.parent.uColor : (deadMa.containsMouse ? "#58a6ff" : "#8b949e")
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: deadMa.containsMouse && parent.parent.hasDeadline
                                    text: "✏️"
                                    font.pixelSize: 9
                                }
                            }

                            ToolTip.visible: deadMa.containsMouse
                            ToolTip.text: parent.hasDeadline ? ("Milestone Deadline: " + model.deadline_str + "\nTarget Date: " + (model.target_date || "N/A") + "\n(Click to change or clear)") : "No deadline set (Click to set deadline)"

                            MouseArea {
                                id: deadMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    deadlineDialog.openForWorkItem(model.id, model.title, model.deadline_str, "");
                                }
                            }
                        }

                        // Assigned To
                        Text {
                            text: model.assigned_to || "Unassigned"
                            Layout.preferredWidth: 115
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                            elide: Text.ElideRight
                        }

                        // References pill
                        Item {
                            Layout.preferredWidth: 75
                            height: 22

                            Row {
                                spacing: 5
                                anchors.verticalCenter: parent.verticalCenter

                                // PR count pill
                                Rectangle {
                                    width: prRefText.implicitWidth + 12
                                    height: 20
                                    radius: 10
                                    visible: (model.linked_pr_count || 0) > 0
                                    color: "#0d2344"
                                    border.color: "#1f6feb"
                                    border.width: 1
                                    Text {
                                        id: prRefText
                                        anchors.centerIn: parent
                                        text: "🔀 " + (model.linked_pr_count || 0)
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: "#58a6ff"
                                    }
                                    ToolTip.visible: prRefMa.containsMouse && (model.linked_pr_count || 0) > 0
                                    ToolTip.text: (model.linked_pr_count || 0) + " PR(s) reference this work item"
                                    MouseArea {
                                        id: prRefMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: { expanded = !expanded }
                                    }
                                }

                                // Repo count pill
                                Rectangle {
                                    width: repoRefText.implicitWidth + 12
                                    height: 20
                                    radius: 10
                                    visible: (model.linked_repo_count || 0) > 0
                                    color: "#0a1f2e"
                                    border.color: "#30363d"
                                    border.width: 1
                                    Text {
                                        id: repoRefText
                                        anchors.centerIn: parent
                                        text: "📦 " + (model.linked_repo_count || 0)
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                    }
                                    ToolTip.visible: repoRefMa.containsMouse && (model.linked_repo_count || 0) > 0
                                    ToolTip.text: (model.linked_repo_count || 0) + " repository(s) have PRs referencing this item"
                                    MouseArea {
                                        id: repoRefMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: { expanded = !expanded }
                                    }
                                }

                                // No refs label
                                Text {
                                    visible: (model.linked_pr_count || 0) === 0
                                    text: "—"
                                    font.pixelSize: 12
                                    color: "#484f58"
                                }
                            }
                        }

                        // TFS Link
                        Rectangle {
                            Layout.preferredWidth: 45
                            height: 24
                            radius: 4
                            color: tfsLinkMa.containsMouse && (model.tfs_url || "") !== "" ? "#0d2344" : "transparent"
                            border.color: tfsLinkMa.containsMouse && (model.tfs_url || "") !== "" ? "#1f6feb" : "transparent"
                            border.width: 1
                            visible: (model.tfs_url || "") !== ""

                            Text {
                                anchors.centerIn: parent
                                text: "↗ TFS"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: tfsLinkMa.containsMouse ? "#58a6ff" : "#388bfd"
                            }

                            ToolTip.visible: tfsLinkMa.containsMouse
                            ToolTip.text: "Open in TFS: " + (model.tfs_url || "")

                            MouseArea {
                                id: tfsLinkMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (backend && (model.tfs_url || "") !== "") {
                                        backend.open_url(model.tfs_url)
                                    }
                                }
                            }
                        }
                    }

                    // ---- Expanded References Panel ----
                    Rectangle {
                        id: expandPanel
                        anchors.top: mainRow.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 10
                        anchors.topMargin: 0
                        height: parent.height - 52 - 6
                        visible: expanded
                        color: "#131920"
                        radius: 4
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            // Iteration & Modification metadata bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 28
                                color: "#161b22"
                                radius: 4
                                border.color: "#30363d"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 12

                                    Row {
                                        spacing: 5
                                        Text { text: "🎯 Iteration:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                                        Text {
                                            text: model.is_iteration_planned ? ("Planned (" + (model.iteration_path || model.iteration_name) + ")") : ("Not planned (" + (model.iteration_path || "Backlog") + ")")
                                            font.pixelSize: 11
                                            color: model.is_iteration_planned ? "#58a6ff" : "#8b949e"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Row {
                                        spacing: 5
                                        visible: (model.deadline_str || "") !== ""
                                        Text { text: "⏳ Deadline:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                                        Text {
                                            text: model.deadline_str + " (" + (model.urgency_badge || "") + ")"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: model.urgency_color || "#f0f6fc"
                                        }
                                    }

                                    Row {
                                        spacing: 5
                                        visible: (model.changed_date || "") !== ""
                                        Text { text: "🕒 Last Changed:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                                        Text {
                                            text: (model.changed_date || "").replace("T", " ").split(".")[0].replace("Z", "")
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            color: "#c9d1d9"
                                        }
                                    }
                                }
                            }

                            // PR list
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                visible: (model.linked_pr_count || 0) > 0

                                Text {
                                    text: "🔀 Referenced Pull Requests"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                }

                                Repeater {
                                    model: {
                                        var prs = wiListView.model.get(index) ? wiListView.model.get(index).linked_prs : []
                                        return prs || []
                                    }
                                    Row {
                                        spacing: 8
                                        Text {
                                            text: "!"+modelData.pr_id
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
                                        }
                                        Text {
                                            text: modelData.repo_name || ""
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                        Text {
                                            text: (modelData.title || "").substring(0, 60)
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#c9d1d9"
                                        }
                                    }
                                }
                            }

                            // Repo list
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                visible: (model.linked_repo_count || 0) > 0

                                Text {
                                    text: "📦 Referenced Repositories"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: {
                                            var item = wiListView.model.get(index)
                                            return item ? (item.linked_repos || []) : []
                                        }
                                        Rectangle {
                                            height: 20
                                            width: repoChipText.implicitWidth + 14
                                            radius: 10
                                            color: "#0a1f2e"
                                            border.color: "#30363d"
                                            Text {
                                                id: repoChipText
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#8b949e"
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

        // ====================== Pagination ======================
        Rectangle {
            Layout.fillWidth: true
            height: 46
            color: "#161b22"
            radius: 6
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: "Page " + root.currentPage + " of " + Math.max(1, root.totalPages) + "  ·  " + root.totalMatchingCount + " items"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                }

                Item { Layout.fillWidth: true }

                // Page size selector
                Row {
                    spacing: 4
                    Text { text: "Rows:"; font.pixelSize: 12; color: "#8b949e"; anchors.verticalCenter: parent.verticalCenter }
                    Repeater {
                        model: [15, 25, 50, 100]
                        Button {
                            text: modelData.toString()
                            checkable: true
                            checked: root.pageSize === modelData
                            font.pixelSize: 11
                            font.weight: checked ? Font.DemiBold : Font.Normal
                            contentItem: Text {
                                text: parent.text; font: parent.font
                                color: parent.checked ? "#ffffff" : "#8b949e"
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 26; implicitWidth: 36; radius: 4
                                color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                                border.color: parent.checked ? "#388bfd" : "#30363d"
                            }
                            onClicked: { root.pageSize = modelData; root.currentPage = 1; root.updateFilteredModel() }
                        }
                    }
                }

                Item { width: 8 }

                Button {
                    text: "«"; enabled: root.currentPage > 1; font.pixelSize: 14
                    contentItem: Text { text: parent.text; font: parent.font; color: parent.enabled ? "#f0f6fc" : "#484f58"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitHeight: 28; implicitWidth: 32; radius: 4; color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"; border.color: "#30363d" }
                    onClicked: { root.currentPage = 1; root.updateFilteredModel() }
                }
                Button {
                    text: "‹ Prev"; enabled: root.currentPage > 1; font.pixelSize: 11
                    contentItem: Text { text: parent.text; font: parent.font; color: parent.enabled ? "#f0f6fc" : "#484f58"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitHeight: 28; implicitWidth: 64; radius: 4; color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"; border.color: "#30363d" }
                    onClicked: { if (root.currentPage > 1) { root.currentPage--; root.updateFilteredModel() } }
                }
                Button {
                    text: "Next ›"; enabled: root.currentPage < root.totalPages; font.pixelSize: 11
                    contentItem: Text { text: parent.text; font: parent.font; color: parent.enabled ? "#f0f6fc" : "#484f58"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitHeight: 28; implicitWidth: 64; radius: 4; color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"; border.color: "#30363d" }
                    onClicked: { if (root.currentPage < root.totalPages) { root.currentPage++; root.updateFilteredModel() } }
                }
                Button {
                    text: "»"; enabled: root.currentPage < root.totalPages; font.pixelSize: 14
                    contentItem: Text { text: parent.text; font: parent.font; color: parent.enabled ? "#f0f6fc" : "#484f58"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitHeight: 28; implicitWidth: 32; radius: 4; color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"; border.color: "#30363d" }
                    onClicked: { root.currentPage = root.totalPages; root.updateFilteredModel() }
                }
            }
        }
    }

    // ========================
    // Filtering & paging
    // ========================
    function updateFilteredModel() {
        filteredWorkItems.clear()
        if (!backend || !backend.workItems) return
        var list = backend.workItems || []
        var q = (root.searchQuery || "").toLowerCase()
        var st = root.filterState
        var ft = root.filterType

        var matched = []
        for (var i = 0; i < list.length; i++) {
            var item = list[i]
            var matchesQuery = !q ||
                (item.id || 0).toString().indexOf(q) !== -1 ||
                (item.title || "").toLowerCase().indexOf(q) !== -1 ||
                (item.assigned_to || "").toLowerCase().indexOf(q) !== -1 ||
                (item.type || "").toLowerCase().indexOf(q) !== -1 ||
                (item.state || "").toLowerCase().indexOf(q) !== -1 ||
                (item.iteration_name || "").toLowerCase().indexOf(q) !== -1 ||
                (item.iteration_path || "").toLowerCase().indexOf(q) !== -1

            var matchesState = true
            if (st === "ALL") {
                matchesState = !item.deleted
            } else if (st === "DELETED") {
                matchesState = item.deleted
            } else {
                matchesState = !item.deleted && ((item.state || "").toLowerCase() === st.toLowerCase())
            }

            var matchesType = (ft === "ALL") || (item.type === ft)

            var matchesModified = true
            if (root.filterModified !== "ALL") {
                var days = parseInt(root.filterModified)
                if (!isNaN(days)) {
                    matchesModified = root.isWithinDays(item.changed_date, days)
                }
            }

            var matchesAssignee = true
            if (root.filterAssignee === "ALL") {
                matchesAssignee = true
            } else if (root.filterAssignee === "UNASSIGNED") {
                matchesAssignee = !item.assigned_to || item.assigned_to === "Unassigned"
            } else {
                matchesAssignee = (item.assigned_to || "").toLowerCase() === root.filterAssignee.toLowerCase()
            }

            var matchesIteration = true
            if (root.filterIteration === "ALL") {
                matchesIteration = true
            } else if (root.filterIteration === "PLANNED") {
                matchesIteration = !!item.is_iteration_planned
            } else if (root.filterIteration === "UNPLANNED") {
                matchesIteration = !item.is_iteration_planned
            } else {
                matchesIteration = (item.iteration_name || "").toLowerCase() === root.filterIteration.toLowerCase()
            }

            var matchesUrgency = true
            if (root.filterUrgency !== "ALL") {
                var u_stat = (item.urgency_status || "").toUpperCase()
                if (root.filterUrgency === "OVERDUE") {
                    matchesUrgency = u_stat === "OVERDUE"
                } else if (root.filterUrgency === "DUE_THIS_WEEK") {
                    matchesUrgency = u_stat === "DUE_THIS_WEEK"
                } else if (root.filterUrgency === "DUE_NEXT_WEEK") {
                    matchesUrgency = u_stat === "DUE_NEXT_WEEK"
                } else if (root.filterUrgency === "FUTURE") {
                    matchesUrgency = u_stat === "FUTURE"
                }
            }

            if (matchesQuery && matchesState && matchesType && matchesModified && matchesAssignee && matchesIteration && matchesUrgency) {
                matched.push(item)
            }
        }

        root.totalMatchingCount = matched.length
        root.totalPages = Math.ceil(matched.length / root.pageSize) || 1
        if (root.currentPage > root.totalPages) root.currentPage = root.totalPages
        if (root.currentPage < 1) root.currentPage = 1

        var startIdx = (root.currentPage - 1) * root.pageSize
        var endIdx = Math.min(startIdx + root.pageSize, matched.length)
        for (var j = startIdx; j < endIdx; j++) {
            var wi = matched[j]
            var entry = {
                id: wi.id,
                title: wi.title,
                type: wi.type,
                state: wi.state,
                assigned_to: wi.assigned_to,
                changed_date: wi.changed_date,
                iteration_path: wi.iteration_path || "",
                iteration_name: wi.iteration_name || "",
                is_iteration_planned: !!wi.is_iteration_planned,
                sprint_week_name: wi.sprint_week_name || "",
                target_date: wi.target_date || "",
                deadline_str: wi.deadline_str || "",
                urgency_status: wi.urgency_status || "none",
                urgency_badge: wi.urgency_badge || "—",
                urgency_color: wi.urgency_color || "#8b949e",
                days_diff: wi.days_diff,
                deleted: wi.deleted,
                tfs_url: wi.tfs_url || "",
                linked_pr_count: wi.linked_pr_count || 0,
                linked_repo_count: wi.linked_repo_count || 0,
                linked_prs: wi.linked_prs || [],
                linked_repos: wi.linked_repos || [],
            }
            filteredWorkItems.append(entry)
        }
    }

    Connections {
        target: backend
        function onWorkItemsChanged() {
            root.refreshTypesList()
            root.refreshStatesList()
            root.refreshAssigneesList()
            root.refreshIterationsList()
            root.updateFilteredModel()
        }
    }

    onSearchQueryChanged:     updateFilteredModel()
    onFilterStateChanged:     updateFilteredModel()
    onFilterTypeChanged:      updateFilteredModel()
    onFilterAssigneeChanged:  updateFilteredModel()
    onFilterModifiedChanged:  updateFilteredModel()
    onFilterIterationChanged: updateFilteredModel()
    onFilterUrgencyChanged:   updateFilteredModel()

    DeadlineEditorDialog {
        id: deadlineDialog
        onDeadlineUpdated: function(id, newDate, result) {
            root.updateFilteredModel()
        }
    }

    IterationPickerModal {
        id: iterationModal
        onIterationUpdated: function(id, newIteration, result) {
            root.updateFilteredModel()
        }
    }

    Component.onCompleted: {
        refreshTypesList()
        refreshStatesList()
        refreshAssigneesList()
        refreshIterationsList()
        updateFilteredModel()
    }
}

