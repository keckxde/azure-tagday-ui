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
    property string filterLevel1: "ALL"      // "ALL", "UNGROUPED", or specific Level 1 (Epic) display name
    property string filterLevel2: "ALL"      // "ALL", "UNGROUPED", or specific Level 2 (Feature) display name
    property string filterPriority: "ALL"    // "ALL", "PRIO1", "STANDARD"
    property string filterGrouping: "ALL"    // "ALL", "GROUPED", "UNGROUPED"
    property string filterMilestone: "ALL"   // "ALL", "PLANNED", "UNPLANNED", or specific milestone name
    property string filterTagCategory: "ALL" // "ALL" or specific category name
    property string filterTag: "ALL"         // "ALL", "TAGGED", "UNTAGGED", or specific tag name
    property int currentPage: 1
    property int pageSize: 25
    property int totalPages: 1
    property int totalMatchingCount: 0
    property var matchedItemsList: []

    property int overdueItemsCount: {
        if (!backend || !backend.workItems) return 0;
        var count = 0;
        var all = backend.workItems;
        for (var i = 0; i < all.length; i++) {
            if (!all[i].deleted && all[i].urgency_status === "overdue") {
                count++;
            }
        }
        return count;
    }

    property int taggedItemsCount: {
        if (!backend || !backend.workItems) return 0;
        var count = 0;
        var all = backend.workItems;
        for (var i = 0; i < all.length; i++) {
            if (!all[i].deleted && ((all[i].tag_list && all[i].tag_list.length > 0) || (all[i].tags && all[i].tags.trim() !== ""))) {
                count++;
            }
        }
        return count;
    }

    property int uniqueTagsCount: backend && backend.workItemTags ? backend.workItemTags.length : 0

    // -- Filter lists, updated dynamically from database cache --
    property var typesList: []
    property var statesList: []
    property var assigneesList: ["ALL"]
    property var iterationsList: ["ALL"]
    property var level1List: ["ALL"]
    property var level2List: ["ALL"]
    property var milestonesList: ["ALL"]
    property var tagCategoryList: ["ALL"]   // populated from backend.get_tag_category_names()
    property var tagsByCategoryData: ({})   // populated from backend.get_tags_by_category() JSON
    property var tagsList: ["ALL"]

    property var priorityOptions: [
        { label: "All Priorities", value: "ALL" },
        { label: "⭐ Prio 1 Focus Only", value: "PRIO1" },
        { label: "Standard Items", value: "STANDARD" }
    ]

    property var groupingOptions: [
        { label: "All Groupings", value: "ALL" },
        { label: "🏷️ Grouped (PBS)", value: "GROUPED" },
        { label: "⚠️ Ungrouped", value: "UNGROUPED" }
    ]

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

    function refreshHierarchyLists() {
        if (!backend) return
        var l1 = backend.workItemLevel1List || []
        level1List = ["ALL"].concat(l1).concat(["[ WITHOUT [<NR>] SYNTAX ]", "UNGROUPED"])
        var l2 = backend.workItemLevel2List || []
        level2List = ["ALL"].concat(l2).concat(["[ WITHOUT [<NR>] SYNTAX ]", "UNGROUPED"])
    }

    function refreshMilestonesList() {
        if (!backend) return
        var ms = backend.workItemMilestones || []
        milestonesList = ["ALL", "PLANNED", "UNPLANNED"].concat(ms)
    }

    function refreshTagsList() {
        if (!backend) return
        // Refresh the category → tags mapping
        var rawJson = backend.get_tags_by_category ? backend.get_tags_by_category() : "{}"
        try { tagsByCategoryData = JSON.parse(rawJson) } catch(e) { tagsByCategoryData = {} }

        // Rebuild category list
        var catNames = Object.keys(tagsByCategoryData).sort()
        tagCategoryList = ["ALL"].concat(catNames)

        // Rebuild tag list filtered by selected category
        if (root.filterTagCategory === "ALL" || root.filterTagCategory === "") {
            var all = backend.workItemTags || []
            tagsList = ["ALL", "TAGGED", "UNTAGGED"].concat(all)
        } else {
            var catTags = (tagsByCategoryData[root.filterTagCategory] || []).slice()
            tagsList = ["ALL"].concat(catTags)
        }
    }

    function resetAllFilters() {
        root.searchQuery = ""
        root.filterState = "ALL"
        root.filterType = "ALL"
        root.filterAssignee = "ALL"
        root.filterModified = "ALL"
        root.filterIteration = "ALL"
        root.filterUrgency = "ALL"
        root.filterLevel1 = "ALL"
        root.filterLevel2 = "ALL"
        root.filterPriority = "ALL"
        root.filterGrouping = "ALL"
        root.filterMilestone = "ALL"
        root.filterTagCategory = "ALL"
        root.filterTag = "ALL"
        if (typeof level1Combo !== "undefined" && level1Combo) {
            level1Combo.currentIndex = 0
            level1Combo.editText = ""
        }
        if (typeof level2Combo !== "undefined" && level2Combo) {
            level2Combo.currentIndex = 0
            level2Combo.editText = ""
        }
        if (typeof wiMilestoneCombo !== "undefined" && wiMilestoneCombo) {
            wiMilestoneCombo.currentIndex = 0
            wiMilestoneCombo.editText = ""
        }
        if (typeof wiTagCategoryCombo !== "undefined" && wiTagCategoryCombo) {
            wiTagCategoryCombo.currentIndex = 0
        }
        if (typeof wiTagCombo !== "undefined" && wiTagCombo) {
            wiTagCombo.currentIndex = 0
            wiTagCombo.editText = ""
        }
        root.currentPage = 1
        root.updateFilteredModel()
    }

    property bool hasActiveFilters: root.searchQuery !== "" || root.filterState !== "ALL" || root.filterType !== "ALL" || root.filterAssignee !== "ALL" || root.filterModified !== "ALL" || root.filterIteration !== "ALL" || root.filterUrgency !== "ALL" || root.filterLevel1 !== "ALL" || root.filterLevel2 !== "ALL" || root.filterPriority !== "ALL" || root.filterGrouping !== "ALL" || root.filterMilestone !== "ALL" || root.filterTagCategory !== "ALL" || root.filterTag !== "ALL"

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

            // Clickable Overdue Deadlines Badge Pill in Top Header
            Rectangle {
                visible: root.overdueItemsCount > 0
                implicitHeight: 24
                implicitWidth: overdueTopText.implicitWidth + 16
                radius: 12
                color: root.filterUrgency === "OVERDUE" ? "#da3633" : (overdueTopMa.containsMouse ? "#321719" : "#261315")
                border.color: root.filterUrgency === "OVERDUE" ? "#f85149" : "#da3633"
                border.width: 1

                MouseArea {
                    id: overdueTopMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    ToolTip.visible: containsMouse
                    ToolTip.text: root.filterUrgency === "OVERDUE" ? "Showing overdue work items only.\nClick to show all deadlines." : "Click to filter to " + root.overdueItemsCount + " overdue work items."
                    onClicked: {
                        root.filterUrgency = (root.filterUrgency === "OVERDUE" ? "ALL" : "OVERDUE");
                        root.currentPage = 1;
                    }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        id: overdueTopText
                        text: "🚨 " + root.overdueItemsCount + " Overdue"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: root.filterUrgency === "OVERDUE" ? "#ffffff" : "#f85149"
                    }
                }
            }

            // Clickable Tag Summary Pill in Top Header
            Rectangle {
                visible: root.uniqueTagsCount > 0
                implicitHeight: 24
                implicitWidth: tagTopText.implicitWidth + 16
                radius: 12
                color: (root.filterTag !== "ALL") ? "#1f334d" : (tagTopMa.containsMouse ? "#21262d" : "#161b22")
                border.color: (root.filterTag !== "ALL") ? "#58a6ff" : "#30363d"
                border.width: 1

                MouseArea {
                    id: tagTopMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    ToolTip.visible: containsMouse
                    ToolTip.text: root.filterTag !== "ALL" ?
                        ("Active Tag Filter: " + root.filterTag + "\nClick to reset tag filter.") :
                        ("🏷️ " + root.uniqueTagsCount + " unique tags across " + root.taggedItemsCount + " work items.\nClick to filter to tagged items.")
                    onClicked: {
                        if (root.filterTag !== "ALL") {
                            root.filterTag = "ALL";
                            if (typeof wiTagCombo !== "undefined" && wiTagCombo) {
                                wiTagCombo.currentIndex = 0;
                                wiTagCombo.editText = "";
                            }
                        } else {
                            root.filterTag = "TAGGED";
                            if (typeof wiTagCombo !== "undefined" && wiTagCombo) {
                                wiTagCombo.editText = "TAGGED";
                            }
                        }
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        id: tagTopText
                        text: (root.filterTag !== "ALL" && root.filterTag !== "TAGGED") ?
                            ("🏷️ Tag: " + root.filterTag) :
                            ("🏷️ " + root.uniqueTagsCount + " Tags (" + root.taggedItemsCount + ")")
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        font.weight: (root.filterTag !== "ALL") ? Font.Bold : Font.Normal
                        color: (root.filterTag !== "ALL") ? "#58a6ff" : "#8b949e"
                    }
                }
            }

            Item { Layout.fillWidth: true }

            SearchBar {
                placeholder: "Search ID, Title, Assignee, Tag..."
                onSearchUpdated: function(query) {
                    root.searchQuery = query
                    root.currentPage = 1
                }
            }

            // Export to Excel Button
            Button {
                id: exportExcelBtn
                text: "📊 Export to Excel"
                enabled: backend ? !backend.isBusy && root.totalMatchingCount > 0 : false
                font.weight: Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: "Export the current (" + root.totalMatchingCount + ") matching work items to an Excel (.xlsx) spreadsheet"
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: parent.enabled ? "#ffffff" : "#8b949e"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 34
                    implicitWidth: 135
                    radius: 6
                    color: parent.enabled ? (parent.hovered ? "#238636" : "#2ea043") : "#21262d"
                    border.color: parent.enabled ? "#3fb950" : "#30363d"
                }
                onClicked: {
                    if (!backend) return;
                    var res = backend.exportWorkItemsToExcel(root.matchedItemsList || []);
                    if (res && res.success) {
                        exportBanner.filePath = res.file_path || "";
                        exportBanner.itemCount = res.item_count || 0;
                        exportBanner.visible = true;
                    }
                }
            }

            Button {
                text: "↻ Refresh"
                enabled: backend ? !backend.isBusy : false
                font.weight: Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: "Reload work items cache directly from local database"
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#f0f6fc"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 34
                    implicitWidth: 85
                    radius: 6
                    color: parent.hovered ? "#30363d" : "#21262d"
                    border.color: "#30363d"
                }
                onClicked: {
                    if (backend)
                        backend.refresh_all_data();
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

        // Excel Export Success Banner
        Rectangle {
            id: exportBanner
            Layout.fillWidth: true
            implicitHeight: 44
            visible: false
            radius: 8
            color: "#122619"
            border.color: "#238636"
            border.width: 1

            property string filePath: ""
            property int itemCount: 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text { text: "✅"; font.pixelSize: 16 }
                Text {
                    text: "Exported " + exportBanner.itemCount + " work items to Excel: "
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#3fb950"
                }
                Text {
                    Layout.fillWidth: true
                    text: exportBanner.filePath
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                    elide: Text.ElideMiddle
                }

                Button {
                    text: "📂 Open File"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    contentItem: Text { text: parent.text; font: parent.font; color: "#ffffff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitHeight: 28; implicitWidth: 85; radius: 6; color: parent.hovered ? "#2ea043" : "#238636" }
                    onClicked: {
                        if (backend && exportBanner.filePath) backend.open_path_in_explorer(exportBanner.filePath)
                    }
                }

                Button {
                    text: "📁 Open Folder"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    contentItem: Text { text: parent.text; font: parent.font; color: "#c9d1d9"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitHeight: 28; implicitWidth: 95; radius: 6; color: parent.hovered ? "#30363d" : "#21262d"; border.color: "#30363d" }
                    onClicked: {
                        if (backend && exportBanner.filePath) backend.open_path_in_explorer(exportBanner.filePath)
                    }
                }

                Button {
                    text: "✖"
                    font.pixelSize: 11
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitHeight: 22; implicitWidth: 22; radius: 11; color: parent.hovered ? "#30363d" : "transparent" }
                    onClicked: exportBanner.visible = false
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

        // ====================== Backlog Hierarchy (L1 Sub-Systems / L2 Components) & Milestone Filter Row ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Level 1: Sub-Systems (Epics)
            RowLayout {
                spacing: 6
                Text {
                    text: "Sub-System (L1):"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: level1Combo
                    implicitWidth: 190
                    implicitHeight: 28
                    font.pixelSize: 11
                    editable: true
                    model: root.level1List
                    editText: root.filterLevel1 === "ALL" ? "" : root.filterLevel1

                    onEditTextChanged: {
                        var val = editText ? editText.trim() : "";
                        root.filterLevel1 = (val === "" ? "ALL" : val);
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }

                    onActivated: function(index) {
                        var val = root.level1List[index] || "ALL";
                        root.filterLevel1 = val;
                        editText = (val === "ALL" ? "" : val);
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }

                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: level1Combo.hovered || level1Combo.activeFocus ? "#58a6ff" : (root.filterLevel1 !== "ALL" ? "#8250df" : "#30363d")
                    }

                    contentItem: TextField {
                        leftPadding: 8
                        rightPadding: (root.filterLevel1 !== "ALL") ? 32 : 24
                        text: level1Combo.editText
                        placeholderText: "Type or select L1..."
                        placeholderTextColor: "#484f58"
                        font: level1Combo.font
                        color: root.filterLevel1 !== "ALL" ? "#bc8cff" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        background: Item {}
                        onTextChanged: {
                            if (text !== level1Combo.editText) {
                                level1Combo.editText = text;
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
                        level1Combo.currentIndex = 0;
                        level1Combo.editText = "";
                        root.currentPage = 1;
                        root.updateFilteredModel();
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
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: level2Combo
                    implicitWidth: 190
                    implicitHeight: 28
                    font.pixelSize: 11
                    editable: true
                    model: root.level2List
                    editText: root.filterLevel2 === "ALL" ? "" : root.filterLevel2

                    onEditTextChanged: {
                        var val = editText ? editText.trim() : "";
                        root.filterLevel2 = (val === "" ? "ALL" : val);
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }

                    onActivated: function(index) {
                        var val = root.level2List[index] || "ALL";
                        root.filterLevel2 = val;
                        editText = (val === "ALL" ? "" : val);
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }

                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: level2Combo.hovered || level2Combo.activeFocus ? "#58a6ff" : (root.filterLevel2 !== "ALL" ? "#388bfd" : "#30363d")
                    }

                    contentItem: TextField {
                        leftPadding: 8
                        rightPadding: (root.filterLevel2 !== "ALL") ? 32 : 24
                        text: level2Combo.editText
                        placeholderText: "Type or select L2..."
                        placeholderTextColor: "#484f58"
                        font: level2Combo.font
                        color: root.filterLevel2 !== "ALL" ? "#58a6ff" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        background: Item {}
                        onTextChanged: {
                            if (text !== level2Combo.editText) {
                                level2Combo.editText = text;
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
                        level2Combo.currentIndex = 0;
                        level2Combo.editText = "";
                        root.currentPage = 1;
                        root.updateFilteredModel();
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
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: wiMilestoneCombo
                    implicitWidth: 190
                    implicitHeight: 28
                    font.pixelSize: 11
                    editable: true
                    model: root.milestonesList
                    editText: root.filterMilestone === "ALL" ? "" : root.filterMilestone

                    onEditTextChanged: {
                        var val = editText ? editText.trim() : "";
                        root.filterMilestone = (val === "" ? "ALL" : val);
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }

                    onActivated: function(index) {
                        var val = root.milestonesList[index] || "ALL";
                        root.filterMilestone = val;
                        editText = (val === "ALL" ? "" : val);
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }

                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: wiMilestoneCombo.hovered || wiMilestoneCombo.activeFocus ? "#58a6ff" : (root.filterMilestone !== "ALL" ? "#d29922" : "#30363d")
                    }

                    contentItem: TextField {
                        leftPadding: 8
                        rightPadding: (root.filterMilestone !== "ALL") ? 32 : 24
                        text: wiMilestoneCombo.editText
                        placeholderText: "Type or select milestone..."
                        placeholderTextColor: "#484f58"
                        font: wiMilestoneCombo.font
                        color: root.filterMilestone !== "ALL" ? "#f0883e" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        background: Item {}
                        onTextChanged: {
                            if (text !== wiMilestoneCombo.editText) {
                                wiMilestoneCombo.editText = text;
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
                        wiMilestoneCombo.currentIndex = 0;
                        wiMilestoneCombo.editText = "";
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // Tag Category + Tag Two-Step Filter
            RowLayout {
                spacing: 6

                Text {
                    text: "Cat:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                    ToolTip.visible: catLabelMa.containsMouse
                    ToolTip.text: "Select a tag category first, then pick a specific tag"
                    MouseArea { id: catLabelMa; anchors.fill: parent; hoverEnabled: true }
                }

                // Category combo
                ComboBox {
                    id: wiTagCategoryCombo
                    implicitWidth: 150
                    implicitHeight: 28
                    font.pixelSize: 11
                    model: root.tagCategoryList
                    currentIndex: {
                        var idx = root.tagCategoryList.indexOf(root.filterTagCategory)
                        return idx >= 0 ? idx : 0
                    }
                    displayText: currentIndex === 0 ? "All Categories" : currentText

                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: wiTagCategoryCombo.hovered || wiTagCategoryCombo.activeFocus ? "#58a6ff" : (root.filterTagCategory !== "ALL" ? "#a371f7" : "#30363d")
                    }
                    contentItem: Text {
                        leftPadding: 8; rightPadding: 24
                        text: wiTagCategoryCombo.displayText
                        font: wiTagCategoryCombo.font
                        color: root.filterTagCategory !== "ALL" ? "#a371f7" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    delegate: ItemDelegate {
                        width: wiTagCategoryCombo.width
                        contentItem: Text {
                            text: modelData === "ALL" ? "All Categories" : modelData
                            font: wiTagCategoryCombo.font
                            color: "#f0f6fc"
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            color: highlighted ? "#21262d" : "#161b22"
                        }
                        highlighted: wiTagCategoryCombo.highlightedIndex === index
                    }
                    popup: Popup {
                        y: wiTagCategoryCombo.height + 2
                        width: wiTagCategoryCombo.width
                        implicitHeight: contentItem.implicitHeight
                        padding: 1
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: wiTagCategoryCombo.delegateModel
                            ScrollIndicator.vertical: ScrollIndicator {}
                        }
                        background: Rectangle { color: "#161b22"; border.color: "#30363d"; radius: 6 }
                    }
                    onActivated: function(index) {
                        root.filterTagCategory = root.tagCategoryList[index] || "ALL"
                        // Reset tag selection when category changes
                        root.filterTag = "ALL"
                        if (wiTagCombo) { wiTagCombo.currentIndex = 0; wiTagCombo.editText = "" }
                        root.refreshTagsList()
                        root.currentPage = 1
                        root.updateFilteredModel()
                    }
                }

                Text {
                    text: "Tag:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: wiTagCombo
                    implicitWidth: 190
                    implicitHeight: 28
                    font.pixelSize: 11
                    editable: true
                    model: root.tagsList
                    editText: root.filterTag === "ALL" ? "" : root.filterTag

                    onEditTextChanged: {
                        var val = editText ? editText.trim() : "";
                        root.filterTag = (val === "" ? "ALL" : val);
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }

                    onActivated: function(index) {
                        var val = root.tagsList[index] || "ALL";
                        root.filterTag = val;
                        editText = (val === "ALL" ? "" : val);
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }

                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: wiTagCombo.hovered || wiTagCombo.activeFocus ? "#58a6ff" : (root.filterTag !== "ALL" ? "#58a6ff" : "#30363d")
                    }

                    contentItem: TextField {
                        leftPadding: 8
                        rightPadding: (root.filterTag !== "ALL") ? 32 : 24
                        text: wiTagCombo.editText
                        placeholderText: root.filterTagCategory !== "ALL" ? ("Tag in '" + root.filterTagCategory + "'...") : "Type or select tag..."
                        placeholderTextColor: "#484f58"
                        font: wiTagCombo.font
                        color: root.filterTag !== "ALL" ? "#58a6ff" : "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        background: Item {}
                        onTextChanged: {
                            if (text !== wiTagCombo.editText) {
                                wiTagCombo.editText = text;
                            }
                        }
                    }
                }

                // Clear Tag filter button (resets both category and tag)
                Button {
                    visible: root.filterTag !== "ALL" || root.filterTagCategory !== "ALL"
                    text: "✖"
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { implicitWidth: 20; implicitHeight: 20; radius: 10; color: parent.hovered ? "#21262d" : "transparent" }
                    onClicked: {
                        root.filterTagCategory = "ALL";
                        root.filterTag = "ALL";
                        wiTagCategoryCombo.currentIndex = 0;
                        wiTagCombo.currentIndex = 0;
                        wiTagCombo.editText = "";
                        root.refreshTagsList();
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // 🚨 Overdue Deadlines Only Toggle (positioned right next to Tag)
            Button {
                text: root.filterUrgency === "OVERDUE" ? "🚨 Overdue Only" : "🚨 Overdue"
                checkable: true
                checked: root.filterUrgency === "OVERDUE"
                font.pixelSize: 11
                font.weight: checked ? Font.Bold : Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: root.filterUrgency === "OVERDUE" ? "Showing overdue deadline items only. Click to show all." : "Click to filter to overdue deadline items only."
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
                onClicked: {
                    root.filterUrgency = (root.filterUrgency === "OVERDUE" ? "ALL" : "OVERDUE");
                    root.currentPage = 1;
                    root.updateFilteredModel();
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ====================== Priority & PBS Grouping Filter Row ======================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Priority Focus Filter (OI, MP, SCEN, SPEC, PA, CS, DOC)
            RowLayout {
                spacing: 6
                Text {
                    text: "Priority:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }
                Repeater {
                    model: root.priorityOptions
                    Button {
                        text: modelData.label
                        checkable: true
                        checked: root.filterPriority === modelData.value
                        font.pixelSize: 11
                        font.weight: checked ? Font.DemiBold : Font.Normal
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.checked ? (modelData.value === "PRIO1" ? "#f0883e" : "#ffffff") : "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 26
                            implicitWidth: pLabel.implicitWidth + 18
                            radius: 13
                            color: parent.checked ? (modelData.value === "PRIO1" ? "#3d2800" : "#1f6feb") : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? (modelData.value === "PRIO1" ? "#d29922" : "#388bfd") : "#30363d"
                            Text { id: pLabel; text: parent.parent.text; visible: false }
                        }
                        onClicked: {
                            root.filterPriority = modelData.value
                            root.currentPage = 1
                        }
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#30363d" }

            // PBS Grouping Filter
            RowLayout {
                spacing: 6
                Text {
                    text: "PBS:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }
                Repeater {
                    model: root.groupingOptions
                    Button {
                        text: modelData.label
                        checkable: true
                        checked: root.filterGrouping === modelData.value
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
                            implicitWidth: gLabel.implicitWidth + 18
                            radius: 13
                            color: parent.checked ? (modelData.value === "UNGROUPED" ? "#3c1e1e" : "#1f6feb") : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? (modelData.value === "UNGROUPED" ? "#da3633" : "#388bfd") : "#30363d"
                            Text { id: gLabel; text: parent.parent.text; visible: false }
                        }
                        onClicked: {
                            root.filterGrouping = modelData.value
                            root.currentPage = 1
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
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
                    return Math.max(120, 115 + prs.length * 22 + repos.length * 18 + 36)
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
                        if (model.has_milestone) return (model.milestone_color ? Qt.rgba(Qt.color(model.milestone_color).r, Qt.color(model.milestone_color).g, Qt.color(model.milestone_color).b, 0.5) : "#d29922")
                        return "#21262d"
                    }
                    border.width: model.has_milestone ? 1.5 : 1
                    clip: true

                    // Milestone Left Accent Indicator
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        radius: 1.5
                        visible: !!model.has_milestone
                        color: model.milestone_color || "#d29922"
                        z: 2
                    }

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

                        // Title, Hierarchy Path & Badges
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            // Milestone Strategic Badge (Direct or Inherited)
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: milestoneBadgeLayout.implicitWidth + 10
                                radius: 4
                                visible: !!model.has_milestone
                                color: model.milestone_bg || (model.milestone_color ? Qt.rgba(Qt.color(model.milestone_color).r, Qt.color(model.milestone_color).g, Qt.color(model.milestone_color).b, 0.2) : "#3d2800")
                                border.color: model.milestone_color || "#d29922"
                                border.width: 1

                                RowLayout {
                                    id: milestoneBadgeLayout
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Text {
                                        text: (model.is_milestone_inherited ? "↳ " : "") + (model.milestone_icon ? model.milestone_icon : "🚩")
                                        font.pixelSize: 9
                                    }
                                    Text {
                                        text: model.effective_milestone_name || model.milestone_name || "Milestone"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: model.milestone_color || "#f0883e"
                                        elide: Text.ElideRight
                                    }
                                }

                                ToolTip.visible: milestoneMouse.containsMouse
                                ToolTip.text: model.is_milestone_inherited ?
                                    ("Inherited Milestone: " + (model.effective_milestone_name || model.milestone_name) + " (from parent story/epic)") :
                                    ("Target Milestone: " + (model.effective_milestone_name || model.milestone_name) + (model.milestone_category ? " [" + model.milestone_category + "]" : ""))

                                MouseArea {
                                    id: milestoneMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }
                            }

                            // Prio 1 Strategic Focus Badge
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: prioBadgeText.implicitWidth + 8
                                radius: 4
                                visible: !!model.is_prio1
                                color: "#3d2800"
                                border.color: "#d29922"
                                border.width: 1

                                Text {
                                    id: prioBadgeText
                                    anchors.centerIn: parent
                                    text: model.prio_badge || "⭐ Prio 1"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#f0883e"
                                }
                            }

                            // Hierarchy (L1 / L2 PBS) Breadcrumb Chip
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: hBadgeText.implicitWidth + 8
                                radius: 4
                                visible: (model.level1_display || "") !== "" && model.level1_display !== "Ungrouped Sub-System"
                                color: "#161b22"
                                border.color: model.is_grouped ? "#30363d" : "#da3633"
                                border.width: 1

                                Text {
                                    id: hBadgeText
                                    anchors.centerIn: parent
                                    text: (model.level1_display || "") + ((model.level2_display && model.level2_display !== "Ungrouped Component") ? (" › " + model.level2_display) : "")
                                    font.pixelSize: 9
                                    color: model.is_grouped ? "#8b949e" : "#f85149"
                                    elide: Text.ElideRight
                                }
                            }

                            // Tag Badges in Main Row (First 2-3 tags)
                            Repeater {
                                model: {
                                    var list = [];
                                    if (model.tag_list && model.tag_list.length > 0) {
                                        list = model.tag_list;
                                    } else if (model.tags && model.tags.trim() !== "") {
                                        list = model.tags.split(";").map(function(t){ return t.trim(); }).filter(function(t){ return t.length > 0; });
                                    }
                                    return list.slice(0, 3);
                                }

                                Rectangle {
                                    implicitHeight: 18
                                    implicitWidth: rowTagLayout.implicitWidth + 8
                                    radius: 4
                                    property bool isTarget: modelData.toLowerCase().indexOf("target:") === 0
                                    color: rowTagMa.containsMouse ? (isTarget ? "#3d2800" : "#1f334d") : (isTarget ? "#241700" : "#16202c")
                                    border.color: isTarget ? "#d29922" : "#388bfd"
                                    border.width: 1

                                    RowLayout {
                                        id: rowTagLayout
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text { text: isTarget ? "🎯" : "🏷️"; font.pixelSize: 8 }
                                        Text {
                                            id: rowTagText
                                            text: modelData
                                            font.pixelSize: 9
                                            font.weight: isTarget ? Font.Bold : Font.Normal
                                            color: isTarget ? "#f0883e" : "#58a6ff"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    ToolTip.visible: rowTagMa.containsMouse
                                    ToolTip.text: isTarget ? ("Target Milestone: " + modelData) : ("Tag: " + modelData)

                                    MouseArea {
                                        id: rowTagMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.filterTag = modelData;
                                            root.currentPage = 1;
                                            root.updateFilteredModel();
                                        }
                                    }
                                }
                            }

                            // Extra Tags "+N" Counter Chip if > 3 tags
                            Rectangle {
                                property int totalTags: {
                                    if (model.tag_list && model.tag_list.length > 0) return model.tag_list.length;
                                    if (model.tags && model.tags.trim() !== "") return model.tags.split(";").filter(function(t){ return t.trim().length > 0; }).length;
                                    return 0;
                                }
                                visible: totalTags > 3
                                implicitHeight: 18
                                implicitWidth: extraTagText.implicitWidth + 8
                                radius: 4
                                color: "#21262d"
                                border.color: "#30363d"
                                border.width: 1

                                Text {
                                    id: extraTagText
                                    anchors.centerIn: parent
                                    text: "+" + (parent.totalTags - 3)
                                    font.pixelSize: 9
                                    color: "#8b949e"
                                }

                                ToolTip.visible: extraTagMa.containsMouse
                                ToolTip.text: "Tags: " + (model.tags || "") + "\nClick to expand details"

                                MouseArea {
                                    id: extraTagMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: expanded = !expanded
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: model.title
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.Normal
                                color: model.deleted ? "#8b949e" : "#f0f6fc"
                                font.strikeout: model.deleted
                                elide: Text.ElideRight
                            }
                        }

                        // State badge
                        Rectangle {
                            Layout.preferredWidth: 88
                            height: 22
                            radius: 11
                            property color stateC: root.stateColor(model.state)
                            color: Qt.rgba(stateC.r, stateC.g, stateC.b, 0.15)
                            border.color: Qt.rgba(stateC.r, stateC.g, stateC.b, 0.5)
                            Text {
                                anchors.centerIn: parent
                                text: model.state || "New"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: root.stateColor(model.state)
                                elide: Text.ElideRight
                            }
                        }

                        // Iteration Pill
                        Rectangle {
                            Layout.preferredWidth: 125
                            height: 24
                            radius: 12
                            color: iterMa.containsMouse ? (model.is_iteration_planned ? "#163c75" : (model.has_milestone ? "#3d2800" : "#21262d")) : (model.is_iteration_planned ? "#0d2344" : (model.has_milestone ? "#241700" : "#161b22"))
                            border.color: iterMa.containsMouse ? "#58a6ff" : (model.is_iteration_planned ? "#1f6feb" : (model.has_milestone ? "#d29922" : "#30363d"))
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 4
                                Text { text: model.is_iteration_planned ? "🎯" : "📋"; font.pixelSize: 10 }
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (model.is_iteration_planned) {
                                            return model.iteration_name || "Planned"
                                        } else if (model.has_milestone) {
                                            return "Backlog"
                                        } else {
                                            return (model.iteration_name && model.iteration_name !== "CH_SAPH_KAWEST") ? model.iteration_name : "Unplanned"
                                        }
                                    }
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: (model.is_iteration_planned || model.has_milestone) ? Font.DemiBold : Font.Normal
                                    color: model.is_iteration_planned ? "#58a6ff" : (model.has_milestone ? "#d29922" : "#8b949e")
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: iterMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                ToolTip.visible: containsMouse
                                ToolTip.text: "Iteration: " + (model.iteration_path || model.iteration_name || "Unplanned") +
                                              (model.team_name ? ("\nTeam: " + model.team_name) : "") +
                                              "\nClick to change iteration assignment"
                                onClicked: iterationModal.openForWorkItem(model.id, model.title, model.iteration_name);
                            }
                        }

                        // Deadline Pill
                        Rectangle {
                            Layout.preferredWidth: 115
                            height: 22
                            radius: 11
                            property bool hasDeadline: (model.deadline_str || "") !== ""
                            property color uColor: model.urgency_color || "#8b949e"
                            color: deadMa.containsMouse ? (hasDeadline ? Qt.rgba(uColor.r, uColor.g, uColor.b, 0.25) : "#21262d") : (hasDeadline ? Qt.rgba(uColor.r, uColor.g, uColor.b, 0.15) : "#161b22")
                            border.color: deadMa.containsMouse ? "#58a6ff" : (hasDeadline ? Qt.rgba(uColor.r, uColor.g, uColor.b, 0.5) : "#30363d")
                            border.width: 1
                            RowLayout { anchors.centerIn: parent; spacing: 4
                                Text { text: parent.parent.hasDeadline ? (model.urgency_badge || model.deadline_str || "—") : "➕ Set Date"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: parent.parent.hasDeadline ? parent.parent.uColor : "#8b949e"; elide: Text.ElideRight }
                            }
                            MouseArea { id: deadMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: deadlineDialog.openForWorkItem(model.id, model.title, model.deadline_str, ""); }
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
                                Rectangle {
                                    width: prRefText.implicitWidth + 12
                                    height: 20
                                    radius: 10
                                    color: (model.linked_pr_count || 0) > 0 ? "#1f6feb" : "#21262d"
                                    visible: (model.linked_pr_count || 0) > 0
                                    Text { id: prRefText; anchors.centerIn: parent; text: "PR: " + (model.linked_pr_count || 0); font.pixelSize: 10; font.weight: Font.DemiBold; color: "#ffffff" }
                                    MouseArea { id: prRefMa; anchors.fill: parent; hoverEnabled: true; onClicked: expanded = !expanded }
                                }
                                Rectangle {
                                    width: repoRefText.implicitWidth + 12
                                    height: 20
                                    radius: 10
                                    color: (model.linked_repo_count || 0) > 0 ? "#238636" : "#21262d"
                                    visible: (model.linked_repo_count || 0) > 0
                                    Text { id: repoRefText; anchors.centerIn: parent; text: "Repo: " + (model.linked_repo_count || 0); font.pixelSize: 10; font.weight: Font.DemiBold; color: "#ffffff" }
                                    MouseArea { id: repoRefMa; anchors.fill: parent; hoverEnabled: true; onClicked: expanded = !expanded }
                                }
                                Text {
                                    text: "—"
                                    font.pixelSize: 12
                                    color: "#484f58"
                                    visible: (model.linked_pr_count || 0) === 0 && (model.linked_repo_count || 0) === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    // ---- Expanded References & Details Panel ----
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

                                    Row {
                                        spacing: 5
                                        visible: !!model.has_milestone
                                        Text { text: "🚩 Milestone:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                                        Text {
                                            text: (model.effective_milestone_name || model.milestone_name) + (model.is_milestone_inherited ? " (Inherited from parent)" : " (Target direct)")
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: model.milestone_color || "#f0883e"
                                        }
                                    }

                                    Row {
                                        spacing: 5
                                        visible: (model.team_name || "") !== ""
                                        Text { text: "👥 Team:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                                        Text {
                                            text: model.team_name
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: "#58a6ff"
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
                                }
                            }

                            // Quick Actions Bar (Jump to Sprint Matrix, Team Taskboard, TFS item)
                            Rectangle {
                                Layout.fillWidth: true
                                height: 30
                                color: "#161b22"
                                radius: 4
                                border.color: "#30363d"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: "⚡ Quick Actions:"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                    }

                                    // Jump to Team Workload Sprint Matrix
                                    Rectangle {
                                        height: 22
                                        implicitWidth: workloadBtnRow.implicitWidth + 14
                                        radius: 11
                                        color: workloadMa.containsMouse ? "#1f6feb" : "#21262d"
                                        border.color: workloadMa.containsMouse ? "#58a6ff" : "#30363d"
                                        border.width: 1

                                        Row {
                                            id: workloadBtnRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "🏃"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                            Text {
                                                text: "Team Sprint Matrix"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: workloadMa.containsMouse ? "#ffffff" : "#c9d1d9"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        MouseArea {
                                            id: workloadMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.text: "Navigate to Team Workload Matrix for " + (model.assigned_to || "this sprint")
                                            onClicked: {
                                                if (window && typeof window.navigateToWorkloadSprint === "function") {
                                                    window.navigateToWorkloadSprint(model.assigned_to, model.sprint_week_name || model.iteration_name);
                                                }
                                            }
                                        }
                                    }

                                    // Open Team Sprint Taskboard in live TFS/Azure DevOps
                                    Rectangle {
                                        height: 22
                                        implicitWidth: tfsSprintBtnRow.implicitWidth + 14
                                        radius: 11
                                        visible: (model.tfs_sprint_url || "") !== ""
                                        color: tfsSprintMa.containsMouse ? "#238636" : "#21262d"
                                        border.color: tfsSprintMa.containsMouse ? "#3fb950" : "#30363d"
                                        border.width: 1

                                        Row {
                                            id: tfsSprintBtnRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "🌐"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                                            Text {
                                                text: model.team_name ? (model.team_name + " Sprint Board") : "TFS Sprint Board"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: tfsSprintMa.containsMouse ? "#ffffff" : "#c9d1d9"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        MouseArea {
                                            id: tfsSprintMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.text: "Open Team Sprint Taskboard in Browser:\n" + model.tfs_sprint_url
                                            onClicked: {
                                                if (model.tfs_sprint_url) Qt.openUrlExternally(model.tfs_sprint_url);
                                            }
                                        }
                                    }

                                    // Open Work Item in TFS/Azure DevOps
                                    Rectangle {
                                        height: 22
                                        implicitWidth: tfsWiBtnRow.implicitWidth + 14
                                        radius: 11
                                        visible: (model.tfs_url || "") !== ""
                                        color: tfsWiMa.containsMouse ? "#1f6feb" : "#21262d"
                                        border.color: tfsWiMa.containsMouse ? "#58a6ff" : "#30363d"
                                        border.width: 1

                                        Row {
                                            id: tfsWiBtnRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "↗"; font.pixelSize: 10; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter; color: tfsWiMa.containsMouse ? "#ffffff" : "#58a6ff" }
                                            Text {
                                                text: "Open in TFS #" + model.id
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: tfsWiMa.containsMouse ? "#ffffff" : "#c9d1d9"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        MouseArea {
                                            id: tfsWiMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.text: "Open Work Item #" + model.id + " in Browser"
                                            onClicked: {
                                                if (model.tfs_url) Qt.openUrlExternally(model.tfs_url);
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // Interactive Tags Metadata Bar
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: Math.max(28, tagChipsFlow.implicitHeight + 8)
                                color: "#161b22"
                                radius: 4
                                border.color: "#30363d"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    anchors.topMargin: 3
                                    anchors.bottomMargin: 3
                                    spacing: 8

                                    Text {
                                        text: "🏷️ Tags:"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Flow {
                                        id: tagChipsFlow
                                        Layout.fillWidth: true
                                        spacing: 5

                                        Repeater {
                                            model: {
                                                if (model.tag_list && model.tag_list.length > 0) {
                                                    return model.tag_list;
                                                } else if (model.tags && model.tags.trim() !== "") {
                                                    return model.tags.split(";").map(function(t){ return t.trim(); }).filter(function(t){ return t.length > 0; });
                                                }
                                                return [];
                                            }

                                            Rectangle {
                                                implicitHeight: 20
                                                implicitWidth: chipRow.implicitWidth + 10
                                                radius: 4
                                                property bool isTarget: modelData.toLowerCase().indexOf("target:") === 0
                                                color: chipMa.containsMouse ? (isTarget ? "#3d2800" : "#1f334d") : (isTarget ? "#201804" : "#16202c")
                                                border.color: isTarget ? "#d29922" : "#388bfd"
                                                border.width: 1

                                                RowLayout {
                                                    id: chipRow
                                                    anchors.centerIn: parent
                                                    spacing: 3
                                                    Text { text: isTarget ? "🎯" : "🏷️"; font.pixelSize: 9 }
                                                    Text {
                                                        text: modelData
                                                        font.pixelSize: 10
                                                        font.weight: isTarget ? Font.Bold : Font.Normal
                                                        color: isTarget ? "#f0883e" : "#58a6ff"
                                                    }
                                                }

                                                ToolTip.visible: chipMa.containsMouse
                                                ToolTip.text: isTarget ?
                                                    ("Target Milestone Tag: " + modelData + "\nClick to filter work items by this tag") :
                                                    ("Tag: " + modelData + "\nClick to filter work items by this tag")

                                                MouseArea {
                                                    id: chipMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.filterTag = modelData;
                                                        // Auto-select category for this tag
                                                        if (backend && backend.get_tags_by_category) {
                                                            try {
                                                                var catData2 = JSON.parse(backend.get_tags_by_category());
                                                                for (var catKey2 in catData2) {
                                                                    if (catData2[catKey2].indexOf(modelData) !== -1) {
                                                                        root.filterTagCategory = catKey2;
                                                                        root.refreshTagsList();
                                                                        var catIdx2 = root.tagCategoryList.indexOf(catKey2);
                                                                        if (catIdx2 >= 0 && typeof wiTagCategoryCombo !== "undefined" && wiTagCategoryCombo)
                                                                            wiTagCategoryCombo.currentIndex = catIdx2;
                                                                        break;
                                                                    }
                                                                }
                                                            } catch(e) {}
                                                        }
                                                        if (typeof wiTagCombo !== "undefined" && wiTagCombo) {
                                                            wiTagCombo.editText = modelData;
                                                        }
                                                        root.currentPage = 1;
                                                        root.updateFilteredModel();
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            visible: (!model.tag_list || model.tag_list.length === 0) && (!model.tags || model.tags.trim() === "")
                                            text: "No tags assigned"
                                            font.pixelSize: 11
                                            font.italic: true
                                            color: "#484f58"
                                            anchors.verticalCenter: parent.verticalCenter
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
                                    model: model.linked_prs || []
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 20
                                        color: prItemMa.containsMouse ? "#21262d" : "transparent"
                                        radius: 3
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            spacing: 6
                                            Text {
                                                text: "PR #" + (modelData.pr_id || modelData.id || "")
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#58a6ff"
                                            }
                                            Text {
                                                text: "· " + (modelData.repo_name || "")
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#8b949e"
                                            }
                                            Text {
                                                text: modelData.title || ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#c9d1d9"
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: modelData.status || ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                color: (modelData.status || "").toLowerCase() === "completed" ? "#3fb950" : "#d29922"
                                            }
                                        }
                                        MouseArea {
                                            id: prItemMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.text: "Open PR in Browser:\n" + (modelData.web_url || modelData.url || "")
                                            onClicked: {
                                                var link = modelData.web_url || modelData.url || "";
                                                if (link) Qt.openUrlExternally(link);
                                            }
                                        }
                                    }
                                }
                            }

                            // Repo tags / links
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: (model.linked_repo_count || 0) > 0

                                Text {
                                    text: "📦 Repositories:"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: model.linked_repos || []
                                        Rectangle {
                                            implicitHeight: 18
                                            implicitWidth: repoTagText.implicitWidth + 8
                                            radius: 3
                                            color: "#21262d"
                                            border.color: "#30363d"
                                            border.width: 1
                                            Text {
                                                id: repoTagText
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                font.weight: Font.DemiBold
                                                color: "#7ee787"
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

        // ====================== Pagination Bar ======================
        Rectangle {
            Layout.fillWidth: true
            height: 40
            color: "#161b22"
            radius: 6
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8

                Text {
                    text: {
                        var start = root.totalMatchingCount === 0 ? 0 : (root.currentPage - 1) * root.pageSize + 1
                        var end = Math.min(root.currentPage * root.pageSize, root.totalMatchingCount)
                        return "Showing " + start + "–" + end + " of " + root.totalMatchingCount + " items"
                    }
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Page " + root.currentPage + " of " + root.totalPages
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

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
                (item.iteration_path || "").toLowerCase().indexOf(q) !== -1 ||
                (item.level1_display || "").toLowerCase().indexOf(q) !== -1 ||
                (item.level2_display || "").toLowerCase().indexOf(q) !== -1 ||
                (item.prio_tag || "").toLowerCase().indexOf(q) !== -1 ||
                (item.tags || "").toLowerCase().indexOf(q) !== -1 ||
                (item.milestone_name || "").toLowerCase().indexOf(q) !== -1 ||
                (item.effective_milestone_name || "").toLowerCase().indexOf(q) !== -1 ||
                (item.milestone_category || "").toLowerCase().indexOf(q) !== -1

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

            var matchesLevel1 = true
            if (root.filterLevel1 !== "ALL") {
                var f1 = (root.filterLevel1 || "").toUpperCase()
                if (f1 === "UNGROUPED" || f1 === "[ UNGROUPED ]" || f1.indexOf("WITHOUT") !== -1 || f1.indexOf("NO_PBS") !== -1 || f1.indexOf("NO PBS") !== -1 || f1.indexOf("!PBS") !== -1 || f1 === "NON_PBS") {
                    matchesLevel1 = !item.level1_pbs || item.level1_pbs === "" || !item.level1_id
                } else {
                    var l1Target = root.filterLevel1.toLowerCase()
                    var l1Disp = (item.level1_display || "").toLowerCase()
                    var l1Title = (item.level1_title || "").toLowerCase()
                    var l1Pbs = (item.level1_pbs || "").toLowerCase()
                    var l1Name = (item.level1_name || "").toLowerCase()
                    matchesLevel1 = (l1Disp.indexOf(l1Target) !== -1 || l1Title.indexOf(l1Target) !== -1 || l1Pbs.indexOf(l1Target) !== -1 || l1Name.indexOf(l1Target) !== -1)
                }
            }

            var matchesLevel2 = true
            if (root.filterLevel2 !== "ALL") {
                var f2 = (root.filterLevel2 || "").toUpperCase()
                if (f2 === "UNGROUPED" || f2 === "[ UNGROUPED ]" || f2.indexOf("WITHOUT") !== -1 || f2.indexOf("NO_PBS") !== -1 || f2.indexOf("NO PBS") !== -1 || f2.indexOf("!PBS") !== -1 || f2 === "NON_PBS") {
                    matchesLevel2 = !item.level2_pbs || item.level2_pbs === "" || !item.level2_id
                } else {
                    var l2Target = root.filterLevel2.toLowerCase()
                    var l2Disp = (item.level2_display || "").toLowerCase()
                    var l2Title = (item.level2_title || "").toLowerCase()
                    var l2Pbs = (item.level2_pbs || "").toLowerCase()
                    var l2Name = (item.level2_name || "").toLowerCase()
                    matchesLevel2 = (l2Disp.indexOf(l2Target) !== -1 || l2Title.indexOf(l2Target) !== -1 || l2Pbs.indexOf(l2Target) !== -1 || l2Name.indexOf(l2Target) !== -1)
                }
            }

            var matchesPriority = true
            if (root.filterPriority === "PRIO1") {
                matchesPriority = !!item.is_prio1
            } else if (root.filterPriority === "STANDARD") {
                matchesPriority = !item.is_prio1
            }

            var matchesGrouping = true
            if (root.filterGrouping === "GROUPED") {
                matchesGrouping = !!item.is_grouped
            } else if (root.filterGrouping === "UNGROUPED") {
                matchesGrouping = !item.is_grouped
            }

            var matchesMilestone = true
            if (root.filterMilestone === "ALL") {
                matchesMilestone = true
            } else if (root.filterMilestone === "PLANNED" || root.filterMilestone === "WITH_MILESTONE") {
                matchesMilestone = !!item.has_milestone
            } else if (root.filterMilestone === "UNPLANNED" || root.filterMilestone === "NO_MILESTONE") {
                matchesMilestone = !item.has_milestone
            } else {
                var targetM = root.filterMilestone.toLowerCase().trim()
                var mName = (item.milestone_name || "").toLowerCase()
                var effMName = (item.effective_milestone_name || "").toLowerCase()
                var mCat = (item.milestone_category || "").toLowerCase()
                var targetTags = (item.target_tags || []).map(function(t) { return (t || "").toLowerCase(); })
                var rawTags = (item.tags || "").toLowerCase()
                matchesMilestone = (
                    mName === targetM ||
                    effMName === targetM ||
                    mName.indexOf(targetM) !== -1 ||
                    effMName.indexOf(targetM) !== -1 ||
                    mCat.indexOf(targetM) !== -1 ||
                    targetTags.indexOf(targetM) !== -1 ||
                    targetTags.some(function(t) { return t.indexOf(targetM) !== -1; }) ||
                    rawTags.indexOf("target:" + targetM) !== -1
                )
            }

            var matchesTag = true
            if (root.filterTag === "ALL") {
                matchesTag = true
            } else if (root.filterTag === "TAGGED") {
                matchesTag = (item.tag_list && item.tag_list.length > 0) || (item.tags && item.tags.trim() !== "")
            } else if (root.filterTag === "UNTAGGED") {
                matchesTag = (!item.tag_list || item.tag_list.length === 0) && (!item.tags || item.tags.trim() === "")
            } else {
                var targetTag = root.filterTag.toLowerCase().trim()
                var rawT = (item.tags || "").toLowerCase()
                var tList = (item.tag_list || []).map(function(x) { return (x || "").toLowerCase(); })
                matchesTag = tList.indexOf(targetTag) !== -1 || tList.some(function(t) { return t.indexOf(targetTag) !== -1; }) || rawT.indexOf(targetTag) !== -1
            }

            if (matchesQuery && matchesState && matchesType && matchesModified && matchesAssignee && matchesIteration && matchesUrgency && matchesLevel1 && matchesLevel2 && matchesPriority && matchesGrouping && matchesMilestone && matchesTag) {
                matched.push(item)
            }
        }

        // Sort items complying with [<NR>] <Name> rule before all other items
        matched.sort(function(a, b) {
            var aGrouped = a.is_grouped ? 1 : 0
            var bGrouped = b.is_grouped ? 1 : 0
            if (aGrouped !== bGrouped) return bGrouped - aGrouped

            var aPrio = a.is_prio1 ? 1 : 0
            var bPrio = b.is_prio1 ? 1 : 0
            if (aPrio !== bPrio) return bPrio - aPrio

            return (b.id || 0) - (a.id || 0)
        })

        root.matchedItemsList = matched
        root.totalMatchingCount = matched.length
        root.totalPages = Math.ceil(matched.length / root.pageSize) || 1
        if (root.currentPage > root.totalPages) root.currentPage = root.totalPages
        if (root.currentPage < 1) root.currentPage = 1

        var startIdx = (root.currentPage - 1) * root.pageSize
        var endIdx = Math.min(startIdx + root.pageSize, matched.length)
        for (var j = startIdx; j < endIdx; j++) {
            var wi = matched[j]
            var entry = {
                id: wi.id || 0,
                title: wi.title || "",
                type: wi.type || "",
                state: wi.state || "",
                assigned_to: wi.assigned_to || "",
                changed_date: wi.changed_date || "",
                iteration_path: wi.iteration_path || "",
                iteration_name: wi.iteration_name || "",
                is_iteration_planned: !!wi.is_iteration_planned,
                sprint_week_name: wi.sprint_week_name || "",
                target_date: wi.target_date || "",
                deadline_str: wi.deadline_str || "",
                urgency_status: wi.urgency_status || "none",
                urgency_badge: wi.urgency_badge || "—",
                urgency_color: wi.urgency_color || "#8b949e",
                days_diff: wi.days_diff !== undefined && wi.days_diff !== null ? wi.days_diff : 0,
                deleted: !!wi.deleted,
                tfs_url: wi.tfs_url || "",
                tags: wi.tags || "",
                tag_list: wi.tag_list || [],
                target_tags: wi.target_tags || [],
                level: wi.level || 4,
                level1_id: wi.level1_id || 0,
                level1_display: wi.level1_display || "",
                level2_id: wi.level2_id || 0,
                level2_display: wi.level2_display || "",
                is_grouped: !!wi.is_grouped,
                grouping_status: wi.grouping_status || "ungrouped",
                is_prio1: !!wi.is_prio1,
                prio_category: wi.prio_category || "standard",
                prio_type: wi.prio_type || "",
                prio_tag: wi.prio_tag || "",
                prio_badge: wi.prio_badge || "",
                milestone_name: wi.milestone_name || "",
                milestone_icon: wi.milestone_icon || "",
                milestone_color: wi.milestone_color || "",
                milestone_bg: wi.milestone_bg || "",
                milestone_category: wi.milestone_category || "",
                has_direct_milestone: !!wi.has_direct_milestone,
                has_milestone: !!wi.has_milestone,
                effective_milestone_name: wi.effective_milestone_name || "",
                is_milestone_inherited: !!wi.is_milestone_inherited,
                team_name: wi.team_name || "",
                area_path: wi.area_path || "",
                tfs_sprint_url: wi.tfs_sprint_url || "",
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
            root.refreshHierarchyLists()
            root.refreshMilestonesList()
            root.refreshTagsList()
            root.updateFilteredModel()
        }
        function onMilestonesChanged() {
            root.refreshMilestonesList()
            root.updateFilteredModel()
        }
        function onTagCategoriesChanged() {
            root.refreshTagsList()
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
    onFilterLevel1Changed:    updateFilteredModel()
    onFilterLevel2Changed:    updateFilteredModel()
    onFilterPriorityChanged:  updateFilteredModel()
    onFilterGroupingChanged:  updateFilteredModel()
    onFilterMilestoneChanged:    updateFilteredModel()
    onFilterTagCategoryChanged:  updateFilteredModel()
    onFilterTagChanged:          updateFilteredModel()

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
        refreshHierarchyLists()
        refreshMilestonesList()
        refreshTagsList()
        updateFilteredModel()
    }
}
