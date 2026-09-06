import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root
    property string searchQuery: ""
    property string filterState: "ALL"   // "ALL", "ACTIVE", "DELETED"
    property string filterType: "ALL"    // "ALL" or specific WI type
    property int currentPage: 1
    property int pageSize: 25
    property int totalPages: 1
    property int totalMatchingCount: 0

    // -- State and Type filter lists, updated dynamically from database cache --
    property var typesList: []
    property var statesList: []

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
                Layout.preferredWidth: 42
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

                Text { text: "ID";          Layout.preferredWidth: 72;  font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "TYPE";        Layout.preferredWidth: 110; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "TITLE";       Layout.fillWidth: true;     font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "STATE";       Layout.preferredWidth: 110; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "ASSIGNED TO"; Layout.preferredWidth: 140; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "REFS";        Layout.preferredWidth: 100; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text { text: "LINK";        Layout.preferredWidth: 50;  font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
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
                    return Math.max(36, prs.length * 20 + repos.length * 18 + 32)
                }

                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    color: itemMouse.containsMouse ? "#1c2128" : "#0d1117"
                    radius: 6
                    border.color: {
                        if (model.deleted) return "#f85149"
                        if (itemMouse.containsMouse) return "#388bfd"
                        return "#21262d"
                    }
                    border.width: 1
                    clip: true

                    // ---- Main Row ----
                    RowLayout {
                        id: mainRow
                        width: parent.width
                        height: 52
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        // ID
                        Text {
                            text: "#" + model.id
                            Layout.preferredWidth: 72
                            font.family: "Consolas, monospace"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: model.deleted ? "#f85149" : "#58a6ff"
                        }

                        // Type badge
                        Rectangle {
                            Layout.preferredWidth: 110
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

                        // Title
                        Text {
                            Layout.fillWidth: true
                            text: model.title
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 13
                            color: model.deleted ? "#8b949e" : "#f0f6fc"
                            font.strikeout: model.deleted
                            elide: Text.ElideRight
                        }

                        // State
                        Text {
                            text: model.state
                            Layout.preferredWidth: 110
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: root.stateColor(model.state, model.deleted)
                            elide: Text.ElideRight
                        }

                        // Assigned To
                        Text {
                            text: model.assigned_to || "Unassigned"
                            Layout.preferredWidth: 140
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                            elide: Text.ElideRight
                        }

                        // References pill
                        Item {
                            Layout.preferredWidth: 100
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
                            Layout.preferredWidth: 50
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
                                        // Access linked_prs from outer delegate model
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

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: true
                        onClicked: {
                            if ((model.linked_pr_count || 0) > 0 || (model.linked_repo_count || 0) > 0) {
                                expanded = !expanded
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
                (item.state || "").toLowerCase().indexOf(q) !== -1

            var matchesState = true
            if (st === "ALL") {
                matchesState = !item.deleted
            } else if (st === "DELETED") {
                matchesState = item.deleted
            } else {
                matchesState = !item.deleted && ((item.state || "").toLowerCase() === st.toLowerCase())
            }

            var matchesType = (ft === "ALL") || (item.type === ft)

            if (matchesQuery && matchesState && matchesType) {
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
            // QML ListModel needs plain scalars; serialise linked_prs/repos as JSON strings
            var wi = matched[j]
            var entry = {
                id: wi.id,
                title: wi.title,
                type: wi.type,
                state: wi.state,
                assigned_to: wi.assigned_to,
                changed_date: wi.changed_date,
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
            root.updateFilteredModel()
        }
    }

    onSearchQueryChanged: updateFilteredModel()
    onFilterStateChanged: updateFilteredModel()
    onFilterTypeChanged:  updateFilteredModel()

    Component.onCompleted: {
        refreshTypesList()
        refreshStatesList()
        updateFilteredModel()
    }
}
