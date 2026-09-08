import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root
    property string searchQuery: ""
    property string selectedRepo: "ALL"
    property string selectedStatus: "ALL" // "ALL", "COMPLETED", "ACTIVE", "ABANDONED"
    property string selectedTagFilter: "ALL" // "ALL", "TAGGED", "UNTAGGED"
    property int sortMode: 0 // 0: Time Desc, 1: Time Asc, 2: PR ID Desc, 3: PR ID Asc, 4: Repo A-Z
    property int currentPage: 1
    property int pageSize: 20
    property int totalPages: 1
    property int totalMatchingCount: 0

    // Set repository filter programmatically (e.g. from other views)
    function filterByRepo(repoName) {
        if (!repoName || repoName === "ALL") {
            root.selectedRepo = "ALL";
            if (repoFilterInput) repoFilterInput.text = "";
        } else {
            root.selectedRepo = repoName;
            if (repoFilterInput) repoFilterInput.text = repoName;
        }
        root.currentPage = 1;
    }

    // Set status filter programmatically (e.g. from Dashboard cards)
    function filterByStatus(statusName) {
        if (!statusName) {
            root.selectedStatus = "ALL";
        } else {
            root.selectedStatus = statusName.toUpperCase();
        }
        root.currentPage = 1;
    }

    // Set tag filter programmatically
    function filterByTag(tagFilterName) {
        if (!tagFilterName) {
            root.selectedTagFilter = "ALL";
        } else {
            root.selectedTagFilter = tagFilterName.toUpperCase();
        }
        root.currentPage = 1;
    }

    // Filtered and Sorted Pull Requests List
    readonly property var filteredPRs: {
        if (!backend || !backend.pullRequests) return [];
        var list = backend.pullRequests;
        var query = root.searchQuery.trim().toLowerCase();
        var repoFilter = root.selectedRepo;
        var statusFilter = root.selectedStatus;
        var tagFilter = root.selectedTagFilter;
        var result = [];

        for (var i = 0; i < list.length; i++) {
            var pr = list[i];

            // 1. Repository Filter
            if (repoFilter !== "ALL" && pr.repo_name !== repoFilter) {
                continue;
            }

            // 2. Status Filter
            if (statusFilter !== "ALL") {
                if (statusFilter === "COMPLETED" && pr.status !== "completed") continue;
                if (statusFilter === "ACTIVE" && pr.status !== "active") continue;
                if (statusFilter === "ABANDONED" && pr.status !== "abandoned") continue;
            }

            // 2b. Tag Filter
            if (tagFilter !== "ALL") {
                if (tagFilter === "TAGGED" && !pr.is_tagged) continue;
                if (tagFilter === "UNTAGGED" && pr.is_tagged) continue;
            }

            // 3. Search Query Filter
            if (query !== "") {
                var prIdStr = pr.id ? ("!" + pr.id + " " + pr.id) : "";
                var repoStr = pr.repo_name ? pr.repo_name.toLowerCase() : "";
                var titleStr = pr.title ? pr.title.toLowerCase() : "";
                var authorStr = pr.created_by ? pr.created_by.toLowerCase() : "";
                var tagStr = pr.tag_name ? pr.tag_name.toLowerCase() : "";
                var branchStr = (pr.target_branch ? pr.target_branch.toLowerCase() : "") + " " + (pr.source_branch ? pr.source_branch.toLowerCase() : "");

                if (prIdStr.indexOf(query) === -1 &&
                    repoStr.indexOf(query) === -1 &&
                    titleStr.indexOf(query) === -1 &&
                    authorStr.indexOf(query) === -1 &&
                    tagStr.indexOf(query) === -1 &&
                    branchStr.indexOf(query) === -1) {
                    continue;
                }
            }

            result.push(pr);
        }

        // Apply Sorting
        if (root.sortMode === 0) {
            // Time Descending (Newest first)
            result.sort(function(a, b) {
                var tA = a.timestamp || "";
                var tB = b.timestamp || "";
                if (tA !== tB) return tA > tB ? -1 : 1;
                return (b.id || 0) - (a.id || 0);
            });
        } else if (root.sortMode === 1) {
            // Time Ascending (Oldest first)
            result.sort(function(a, b) {
                var tA = a.timestamp || "";
                var tB = b.timestamp || "";
                if (tA !== tB) return tA < tB ? -1 : 1;
                return (a.id || 0) - (b.id || 0);
            });
        } else if (root.sortMode === 2) {
            // PR ID Descending
            result.sort(function(a, b) {
                return (b.id || 0) - (a.id || 0);
            });
        } else if (root.sortMode === 3) {
            // PR ID Ascending
            result.sort(function(a, b) {
                return (a.id || 0) - (b.id || 0);
            });
        } else if (root.sortMode === 4) {
            // Repository A-Z
            result.sort(function(a, b) {
                var rA = (a.repo_name || "").toLowerCase();
                var rB = (b.repo_name || "").toLowerCase();
                if (rA !== rB) return rA < rB ? -1 : 1;
                return (b.id || 0) - (a.id || 0);
            });
        }

        return result;
    }

    // Paged slice
    readonly property var pagedPRs: {
        var start = (root.currentPage - 1) * root.pageSize;
        return root.filteredPRs.slice(start, start + root.pageSize);
    }

    onFilteredPRsChanged: {
        root.totalMatchingCount = root.filteredPRs.length;
        root.totalPages = Math.max(1, Math.ceil(root.totalMatchingCount / root.pageSize));
        if (root.currentPage > root.totalPages) {
            root.currentPage = 1;
        }
    }

    onPageSizeChanged: {
        root.totalPages = Math.max(1, Math.ceil(root.totalMatchingCount / root.pageSize));
        root.currentPage = 1;
    }

    // Filtered repositories for typing in the repo selector
    readonly property var repoFilteredList: {
        var allRepos = (backend && backend.prRepositories) ? backend.prRepositories : [];
        var typed = (repoFilterInput && repoFilterInput.text) ? repoFilterInput.text.trim().toLowerCase() : "";
        var res = ["ALL"];
        for (var i = 0; i < allRepos.length; i++) {
            var r = allRepos[i];
            if (!typed || r.toLowerCase().indexOf(typed) !== -1) {
                res.push(r);
            }
        }
        return res;
    }

    // Static Column Widths across all rows for consistent tabular alignment and optimal content fit
    readonly property int colPrIdWidth: 75
    readonly property int colRepoWidth: 175
    readonly property int colTitleMinWidth: 240
    readonly property int colStatusWidth: 95
    readonly property int colTagWidth: 140
    readonly property int colBranchWidth: 130
    readonly property int colTimeWidth: 150
    readonly property int colActionWidth: 90
    readonly property int tableMinWidth: colPrIdWidth + colRepoWidth + colTitleMinWidth + colStatusWidth + colTagWidth + colBranchWidth + colTimeWidth + colActionWidth + (7 * 12) + 28

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        // ==========================================
        // Top Toolbar
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "🔀 Pull Requests"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 18
                font.weight: Font.Bold
                color: "#f0f6fc"
            }

            Text {
                text: "(" + root.totalMatchingCount + " of " + ((backend && backend.pullRequests) ? backend.pullRequests.length : 0) + ")"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 13
                color: "#8b949e"
            }

            Item { Layout.fillWidth: true }

            // Status Filter Chips
            Row {
                spacing: 6
                Repeater {
                    model: ["ALL", "COMPLETED", "ACTIVE", "ABANDONED"]
                    Button {
                        text: modelData
                        checkable: true
                        checked: root.selectedStatus === modelData
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
                            color: parent.checked ? (modelData === "ACTIVE" ? "#1f6feb" : (modelData === "COMPLETED" ? "#238636" : (modelData === "ABANDONED" ? "#da3633" : "#30363d"))) : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? "#58a6ff" : "#30363d"
                        }
                        onClicked: {
                            root.selectedStatus = modelData;
                            root.currentPage = 1;
                        }
                    }
                }
            }

            // Tag Filter Chips (All, Tagged, Untagged)
            Row {
                spacing: 6
                Repeater {
                    model: [
                        { key: "ALL", label: "All Tags" },
                        { key: "TAGGED", label: "🏷️ Tagged" },
                        { key: "UNTAGGED", label: "⚠️ Untagged" }
                    ]
                    Button {
                        text: modelData.label
                        checkable: true
                        checked: root.selectedTagFilter === modelData.key
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
                            implicitWidth: 85
                            radius: 6
                            color: parent.checked ? (modelData.key === "TAGGED" ? "#238636" : (modelData.key === "UNTAGGED" ? "#9e6a03" : "#1f6feb")) : (parent.hovered ? "#21262d" : "#161b22")
                            border.color: parent.checked ? "#58a6ff" : "#30363d"
                        }
                        onClicked: {
                            root.selectedTagFilter = modelData.key;
                            root.currentPage = 1;
                        }
                    }
                }
            }

            // Patch Titles On-Demand Button
            Button {
                id: patchTitlesBtn
                text: (backend && backend.isPrTitlesPatched) ? "✨ Titles Patched" : "✨ Patch Titles"
                enabled: backend ? !backend.isBusy : false
                font.pixelSize: 11
                font.weight: Font.DemiBold
                ToolTip.visible: hovered
                ToolTip.text: (backend && backend.isPrTitlesPatched) ? "PR titles have been patched with [<TYPE>_<NR>] tags from referenced work items.\nClick to re-run patcher." : "Run PR Title Patcher on demand: Enforce [<TYPE>_<NR>] tags discovered in referenced work items."
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: (backend && backend.isPrTitlesPatched) ? "#58a6ff" : "#f0f6fc"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    implicitHeight: 30
                    implicitWidth: 115
                    radius: 6
                    color: (backend && backend.isPrTitlesPatched) ? "#0d2344" : (parent.hovered ? "#30363d" : "#21262d")
                    border.color: (backend && backend.isPrTitlesPatched) ? "#1f6feb" : "#30363d"
                }
                onClicked: {
                    if (backend) {
                        backend.patch_pr_titles();
                    }
                }
            }

            // Quick Refresh Button
            Button {
                text: "↻ Refresh"
                font.pixelSize: 12
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#f0f6fc"
                }
                background: Rectangle {
                    implicitHeight: 30
                    implicitWidth: 85
                    radius: 6
                    color: parent.hovered ? "#30363d" : "#21262d"
                    border.color: "#30363d"
                }
                onClicked: {
                    if (backend) backend.refresh_all_data();
                }
            }
        }

        // ==========================================
        // Secondary Filters: Typeable Repo Filter, Sort, Search
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Searchable Repository Selector Dropdown
            RowLayout {
                spacing: 6
                Text {
                    text: "Repo:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                // Typeable Repo Input Box with Autocomplete Popup
                Rectangle {
                    id: repoSelectorBox
                    implicitWidth: 260
                    implicitHeight: 32
                    color: "#161b22"
                    radius: 6
                    border.color: (repoFilterInput.activeFocus || repoPopup.opened) ? "#58a6ff" : "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: "📁"
                            font.pixelSize: 11
                        }

                        TextInput {
                            id: repoFilterInput
                            Layout.fillWidth: true
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#f0f6fc"
                            clip: true
                            selectByMouse: true
                            text: root.selectedRepo === "ALL" ? "" : root.selectedRepo

                            Text {
                                text: root.selectedRepo === "ALL" ? "All Repositories (type to filter)..." : root.selectedRepo
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: root.selectedRepo === "ALL" ? "#8b949e" : "#f0f6fc"
                                visible: !repoFilterInput.text && !repoFilterInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    repoPopup.open();
                                }
                            }

                            onTextChanged: {
                                if (activeFocus && !repoPopup.opened) {
                                    repoPopup.open();
                                }
                            }

                            onAccepted: {
                                if (root.repoFilteredList.length > 1) {
                                    var match = root.repoFilteredList[1];
                                    root.selectedRepo = match;
                                    repoFilterInput.text = match;
                                } else if (root.repoFilteredList.length === 1 && root.repoFilteredList[0] === "ALL") {
                                    root.selectedRepo = "ALL";
                                    repoFilterInput.text = "";
                                }
                                root.currentPage = 1;
                                repoPopup.close();
                            }
                        }

                        // Clear Button
                        Text {
                            text: "✕"
                            font.pixelSize: 11
                            color: "#8b949e"
                            visible: root.selectedRepo !== "ALL" || repoFilterInput.text.length > 0
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    repoFilterInput.text = "";
                                    root.selectedRepo = "ALL";
                                    root.currentPage = 1;
                                    repoPopup.close();
                                }
                            }
                        }

                        // Dropdown Toggle Button
                        Text {
                            text: repoPopup.opened ? "▲" : "▼"
                            font.pixelSize: 10
                            color: "#8b949e"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (repoPopup.opened) {
                                        repoPopup.close();
                                    } else {
                                        repoPopup.open();
                                        repoFilterInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    // Autocomplete Popup for Repositories
                    Popup {
                        id: repoPopup
                        y: repoSelectorBox.height + 4
                        width: Math.max(repoSelectorBox.width, 320)
                        height: Math.min(260, Math.max(60, root.repoFilteredList.length * 30 + 10))
                        padding: 4
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                        background: Rectangle {
                            color: "#161b22"
                            radius: 6
                            border.color: "#30363d"
                            border.width: 1
                        }

                        contentItem: ListView {
                            id: repoPopupListView
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.repoFilteredList

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                active: true
                            }

                            delegate: Rectangle {
                                width: repoPopupListView.width
                                height: 28
                                radius: 4
                                color: rItemMa.containsMouse ? "#21262d" : (root.selectedRepo === modelData ? "#1f6feb" : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        text: modelData === "ALL" ? "🌐" : "📁"
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        text: modelData === "ALL" ? "ALL REPOSITORIES" : modelData
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: (root.selectedRepo === modelData || (root.selectedRepo === "ALL" && modelData === "ALL")) ? Font.Bold : Font.Normal
                                        color: (root.selectedRepo === modelData) ? "#ffffff" : "#c9d1d9"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: rItemMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedRepo = modelData;
                                        repoFilterInput.text = modelData === "ALL" ? "" : modelData;
                                        root.currentPage = 1;
                                        repoPopup.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Sort Order Dropdown
            RowLayout {
                spacing: 6
                Text {
                    text: "Sort:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }

                ComboBox {
                    id: sortCombo
                    implicitWidth: 175
                    implicitHeight: 32
                    font.pixelSize: 12
                    model: [
                        "🕒 Time (Newest)",
                        "🕒 Time (Oldest)",
                        "🔢 PR ID (Highest)",
                        "🔢 PR ID (Lowest)",
                        "📁 Repository (A-Z)"
                    ]
                    currentIndex: root.sortMode
                    onActivated: function(index) {
                        root.sortMode = index;
                        root.currentPage = 1;
                    }
                    background: Rectangle {
                        color: "#161b22"
                        radius: 6
                        border.color: sortCombo.hovered ? "#58a6ff" : "#30363d"
                    }
                    contentItem: Text {
                        leftPadding: 10
                        rightPadding: sortCombo.indicator.width + 10
                        text: sortCombo.displayText
                        font: sortCombo.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Search Box
            Rectangle {
                Layout.preferredWidth: 300
                height: 32
                color: "#161b22"
                radius: 6
                border.color: searchInput.activeFocus ? "#58a6ff" : "#30363d"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 6

                    Text {
                        text: "🔍"
                        font.pixelSize: 12
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#f0f6fc"
                        clip: true
                        selectByMouse: true
                        text: root.searchQuery
                        onTextChanged: {
                            root.searchQuery = text;
                            root.currentPage = 1;
                        }

                        Text {
                            text: "Search PR #, title, repo, author..."
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#6e7681"
                            visible: !searchInput.text && !searchInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: "✕"
                        font.pixelSize: 12
                        color: "#8b949e"
                        visible: searchInput.text.length > 0
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchInput.text = "";
                                root.searchQuery = "";
                                root.currentPage = 1;
                            }
                        }
                    }
                }
            }
        }

        // ==========================================
        // Pull Requests Table Container
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#161b22"
            radius: 8
            border.color: "#30363d"
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Table Header (Strictly matched to column properties)
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    color: "#0d1117"
                    border.color: "#21262d"
                    border.width: 1
                    clip: true

                    RowLayout {
                        x: -prListView.contentX
                        width: Math.max(parent.width, root.tableMinWidth)
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14 + (prVBar.visible ? prVBar.width + 4 : 0)
                        spacing: 12

                        Text {
                            text: "PR ID"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                            Layout.preferredWidth: root.colPrIdWidth
                            Layout.minimumWidth: root.colPrIdWidth
                            Layout.maximumWidth: root.colPrIdWidth
                        }

                        Text {
                            text: "REPOSITORY"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                            Layout.preferredWidth: root.colRepoWidth
                            Layout.minimumWidth: root.colRepoWidth
                            Layout.maximumWidth: root.colRepoWidth
                        }

                        Text {
                            text: "TITLE & TASKS"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                            Layout.fillWidth: true
                            Layout.minimumWidth: root.colTitleMinWidth
                        }

                        Text {
                            text: "STATUS"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                            Layout.preferredWidth: root.colStatusWidth
                            Layout.minimumWidth: root.colStatusWidth
                            Layout.maximumWidth: root.colStatusWidth
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            text: "TAG INFO"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                            Layout.preferredWidth: root.colTagWidth
                            Layout.minimumWidth: root.colTagWidth
                            Layout.maximumWidth: root.colTagWidth
                        }

                        Text {
                            text: "BRANCHES"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                            Layout.preferredWidth: root.colBranchWidth
                            Layout.minimumWidth: root.colBranchWidth
                            Layout.maximumWidth: root.colBranchWidth
                        }

                        Text {
                            text: "TIME & AUTHOR"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                            Layout.preferredWidth: root.colTimeWidth
                            Layout.minimumWidth: root.colTimeWidth
                            Layout.maximumWidth: root.colTimeWidth
                        }

                        Text {
                            text: "ACTIONS"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                            Layout.preferredWidth: root.colActionWidth
                            Layout.minimumWidth: root.colActionWidth
                            Layout.maximumWidth: root.colActionWidth
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }

                // Table Rows ListView
                ListView {
                    id: prListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: Math.max(width, root.tableMinWidth)
                    flickableDirection: Flickable.AutoFlickDirection
                    model: root.pagedPRs

                    ScrollBar.vertical: ScrollBar {
                        id: prVBar
                        policy: ScrollBar.AsNeeded
                        active: true
                    }

                    ScrollBar.horizontal: ScrollBar {
                        id: prHBar
                        policy: ScrollBar.AsNeeded
                        active: true
                    }

                    // Empty State
                    Item {
                        anchors.fill: parent
                        visible: prListView.count === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "🔀"
                                font.pixelSize: 36
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: root.searchQuery ? "No pull requests match your search or filter" : "No pull requests found in database cache"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: "#8b949e"
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Button {
                                text: "Clear Filters"
                                visible: root.searchQuery !== "" || root.selectedRepo !== "ALL" || root.selectedStatus !== "ALL"
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: 11
                                onClicked: {
                                    root.searchQuery = "";
                                    root.filterByRepo("ALL");
                                    root.selectedStatus = "ALL";
                                    root.currentPage = 1;
                                }
                            }
                        }
                    }

                    // PR Table Row Delegate
                    delegate: Rectangle {
                        id: prDelegate
                        width: Math.max(prListView.width, root.tableMinWidth)
                        property bool isExpanded: false
                        // Explicit height prevents delegate overlapping and layout collapses!
                        height: prCol.implicitHeight + 16
                        color: prRowHover.containsMouse ? "#21262d" : (index % 2 === 0 ? "#161b22" : "#1a1f29")
                        radius: 6
                        border.color: isExpanded ? "#388bfd" : "#262c36"
                        border.width: 1

                        MouseArea {
                            id: prRowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.ArrowCursor
                        }

                        ColumnLayout {
                            id: prCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14 + (prVBar.visible ? prVBar.width + 4 : 0)
                            anchors.topMargin: 8
                            spacing: 8

                            // Main Tabular Row (Strictly aligns with header columns)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                // 1. PR ID badge
                                Rectangle {
                                    Layout.preferredWidth: root.colPrIdWidth
                                    Layout.minimumWidth: root.colPrIdWidth
                                    Layout.maximumWidth: root.colPrIdWidth
                                    height: 24
                                    radius: 4
                                    color: "#0d1117"
                                    border.color: "#30363d"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "!" + modelData.id
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                }

                                // 2. Repository pill (Click to filter)
                                Rectangle {
                                    Layout.preferredWidth: root.colRepoWidth
                                    Layout.minimumWidth: root.colRepoWidth
                                    Layout.maximumWidth: root.colRepoWidth
                                    height: 24
                                    radius: 4
                                    color: "#0d1117"
                                    border.color: root.selectedRepo === modelData.repo_name ? "#58a6ff" : "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 4

                                        Text { text: "📁"; font.pixelSize: 10 }
                                        Text {
                                            text: modelData.repo_name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: "#c9d1d9"
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Click to filter by " + modelData.repo_name
                                        onClicked: {
                                            root.filterByRepo(modelData.repo_name);
                                        }
                                    }
                                }

                                // 3. Title & Linked Tasks (Fills remaining horizontal space)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: root.colTitleMinWidth
                                    spacing: 4

                                    Text {
                                        text: modelData.title
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: "#f0f6fc"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    // Referenced Tasks Flow Chips neatly inside column 3
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        visible: modelData.tasks && modelData.tasks.length > 0

                                        Repeater {
                                            model: modelData.tasks || []
                                            delegate: Rectangle {
                                                id: taskChip
                                                height: 20
                                                width: Math.min(220, taskRow.implicitWidth + 12)
                                                radius: 3
                                                color: taskMa.containsMouse ? "#21262d" : "#0d1117"
                                                border.color: modelData.deleted ? "#da3633" : (modelData.type === "Bug" ? "#f85149" : (modelData.type === "User Story" ? "#a371f7" : "#1f6feb"))
                                                border.width: 1

                                                RowLayout {
                                                    id: taskRow
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    Text {
                                                        text: modelData.type === "Bug" ? "🐛" : (modelData.type === "User Story" ? "📖" : "📋")
                                                        font.pixelSize: 9
                                                    }

                                                    Text {
                                                        text: "#" + modelData.id
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: "#58a6ff"
                                                    }

                                                    Text {
                                                        text: modelData.title
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 10
                                                        color: "#c9d1d9"
                                                        elide: Text.ElideRight
                                                        Layout.maximumWidth: 120
                                                    }
                                                }

                                                MouseArea {
                                                    id: taskMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.url) Qt.openUrlExternally(modelData.url);
                                                    }
                                                }

                                                ToolTip.visible: taskMa.containsMouse
                                                ToolTip.delay: 250
                                                ToolTip.text: (modelData.type || "Work Item") + " #" + modelData.id + "\n" + modelData.title + "\nState: " + modelData.state + "\nAssigned: " + (modelData.assigned_to || "Unassigned")
                                            }
                                        }
                                    }
                                }

                                // 4. Status Badge
                                StatusBadge {
                                    Layout.preferredWidth: root.colStatusWidth
                                    Layout.minimumWidth: root.colStatusWidth
                                    Layout.maximumWidth: root.colStatusWidth
                                    text: modelData.status.toUpperCase()
                                    badgeColor: modelData.status === "completed" ? "#238636" : (modelData.status === "active" ? "#1f6feb" : (modelData.status === "abandoned" ? "#da3633" : "#6e7681"))
                                }

                                // 4b. Tag Info Badge
                                Rectangle {
                                    Layout.preferredWidth: root.colTagWidth
                                    Layout.minimumWidth: root.colTagWidth
                                    Layout.maximumWidth: root.colTagWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitHeight: 24
                                    radius: 4
                                    color: modelData.is_tagged ? "#162b20" :
                                           (modelData.status === "completed" ? "#332200" : "#161b22")
                                    border.color: modelData.is_tagged ? "#238636" :
                                                  (modelData.status === "completed" ? "#9e6a03" : "#30363d")
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            text: modelData.is_tagged ? ("🏷️ " + modelData.tag_name) :
                                                  (modelData.status === "completed" ? "⚠️ Untagged" :
                                                   (modelData.status === "active" ? "⏳ In Review" : "—"))
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: modelData.is_tagged ? Font.DemiBold : Font.Normal
                                            color: modelData.is_tagged ? "#3fb950" :
                                                   (modelData.status === "completed" ? "#d29922" : "#8b949e")
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: root.colTagWidth - 12
                                        }
                                    }

                                    ToolTip.visible: tagCellHover.hovered && (modelData.is_tagged || modelData.status === "completed")
                                    ToolTip.text: modelData.is_tagged ? (modelData.tag_type === "direct" ? "Direct merge commit tag: " + modelData.tag_name : ("Included in release tag " + modelData.tag_name)) :
                                                  (modelData.status === "completed" ? "Merged after latest tag (candidate for next release)" : "")
                                    HoverHandler { id: tagCellHover }
                                }

                                // 5. Branches
                                ColumnLayout {
                                    Layout.preferredWidth: root.colBranchWidth
                                    Layout.minimumWidth: root.colBranchWidth
                                    Layout.maximumWidth: root.colBranchWidth
                                    spacing: 1

                                    Text {
                                        text: "➔ " + (modelData.target_branch || "dev")
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        color: "#58a6ff"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.source_branch ? ("⎇ " + modelData.source_branch) : ""
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        visible: modelData.source_branch !== ""
                                    }
                                }

                                // 6. Time & Author
                                ColumnLayout {
                                    Layout.preferredWidth: root.colTimeWidth
                                    Layout.minimumWidth: root.colTimeWidth
                                    Layout.maximumWidth: root.colTimeWidth
                                    spacing: 1

                                    Text {
                                        text: modelData.display_date
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#e6edf3"
                                    }
                                    Text {
                                        text: modelData.created_by ? ("by " + modelData.created_by) : ""
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // 7. Action Buttons: Open TFS & Expand Toggle
                                RowLayout {
                                    Layout.preferredWidth: root.colActionWidth
                                    Layout.minimumWidth: root.colActionWidth
                                    Layout.maximumWidth: root.colActionWidth
                                    spacing: 4
                                    Layout.alignment: Qt.AlignRight

                                    Button {
                                        text: "TFS ↗"
                                        font.pixelSize: 11
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: "#58a6ff"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 26
                                            implicitWidth: 48
                                            radius: 4
                                            color: parent.hovered ? "#30363d" : "#0d1117"
                                            border.color: "#30363d"
                                        }
                                        onClicked: {
                                            if (modelData.web_url) {
                                                Qt.openUrlExternally(modelData.web_url);
                                            }
                                        }
                                    }

                                    Button {
                                        text: prDelegate.isExpanded ? "▲" : "▼"
                                        font.pixelSize: 11
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: "#8b949e"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 26
                                            implicitWidth: 26
                                            radius: 4
                                            color: parent.hovered ? "#30363d" : "#0d1117"
                                            border.color: "#30363d"
                                        }
                                        onClicked: prDelegate.isExpanded = !prDelegate.isExpanded
                                    }
                                }
                            }

                            // Expanded Details Section: Description & Detailed Info
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: prDelegate.isExpanded
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: "#30363d"
                                }

                                // Metadata Sub-row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16

                                    Text {
                                        text: "Source: " + (modelData.source_branch || "N/A") + " ➔ Target: " + (modelData.target_branch || "N/A")
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                    }

                                    // Tag pill in expanded view
                                    Rectangle {
                                        visible: modelData.is_tagged || modelData.status === "completed"
                                        implicitHeight: 20
                                        implicitWidth: expTagText.implicitWidth + 14
                                        radius: 4
                                        color: modelData.is_tagged ? "#162b20" : "#332200"
                                        border.color: modelData.is_tagged ? "#238636" : "#9e6a03"
                                        border.width: 1

                                        Text {
                                            id: expTagText
                                            anchors.centerIn: parent
                                            text: modelData.is_tagged ? ("🏷️ Tagged: " + modelData.tag_name + (modelData.tag_type === "direct" ? " (direct)" : " (in release)")) : "⚠️ Untagged (pending tag)"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: modelData.is_tagged ? "#3fb950" : "#d29922"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: modelData.closed_by ? ("Merged/Closed by " + modelData.closed_by + " on " + modelData.closed_date) : ("Created on " + modelData.created_date)
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                    }
                                }

                                // Description Markdown Box
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: prDescText.implicitHeight + 16
                                    color: "#0d1117"
                                    radius: 6
                                    border.color: "#30363d"
                                    border.width: 1
                                    visible: modelData.description && modelData.description.trim() !== ""

                                    Text {
                                        id: prDescText
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        text: modelData.description || ""
                                        textFormat: Text.MarkdownText
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        color: "#c9d1d9"
                                        wrapMode: Text.Wrap
                                        onLinkActivated: function(link) {
                                            Qt.openUrlExternally(link);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ==========================================
                // Pagination Footer Controls
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        // Summary Text
                        Text {
                            text: {
                                if (root.totalMatchingCount === 0) return "No items";
                                var startIdx = (root.currentPage - 1) * root.pageSize + 1;
                                var endIdx = Math.min(root.currentPage * root.pageSize, root.totalMatchingCount);
                                return "Showing " + startIdx + "–" + endIdx + " of " + root.totalMatchingCount + " pull requests";
                            }
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                        }

                        Item { Layout.fillWidth: true }

                        // Page Size Selector
                        RowLayout {
                            spacing: 6
                            Text {
                                text: "Per page:"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                            }

                            ComboBox {
                                implicitWidth: 75
                                implicitHeight: 28
                                font.pixelSize: 11
                                model: [15, 20, 50, 100]
                                currentIndex: 1 // default 20
                                onActivated: function(index) {
                                    root.pageSize = model[index];
                                }
                                background: Rectangle {
                                    color: "#161b22"
                                    radius: 4
                                    border.color: "#30363d"
                                }
                                contentItem: Text {
                                    leftPadding: 8
                                    text: parent.displayText
                                    font: parent.font
                                    color: "#f0f6fc"
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        // Navigation Buttons
                        RowLayout {
                            spacing: 4

                            Button {
                                text: "«"
                                enabled: root.currentPage > 1
                                font.pixelSize: 12
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#f0f6fc" : "#484f58"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    implicitWidth: 32
                                    radius: 4
                                    color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                    border.color: "#30363d"
                                }
                                onClicked: root.currentPage = 1
                            }

                            Button {
                                text: "‹ Prev"
                                enabled: root.currentPage > 1
                                font.pixelSize: 12
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#f0f6fc" : "#484f58"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    implicitWidth: 60
                                    radius: 4
                                    color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                    border.color: "#30363d"
                                }
                                onClicked: root.currentPage = Math.max(1, root.currentPage - 1)
                            }

                            Text {
                                text: "Page " + root.currentPage + " of " + root.totalPages
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: "#f0f6fc"
                                Layout.leftMargin: 6
                                Layout.rightMargin: 6
                            }

                            Button {
                                text: "Next ›"
                                enabled: root.currentPage < root.totalPages
                                font.pixelSize: 12
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#f0f6fc" : "#484f58"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    implicitWidth: 60
                                    radius: 4
                                    color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                    border.color: "#30363d"
                                }
                                onClicked: root.currentPage = Math.min(root.totalPages, root.currentPage + 1)
                            }

                            Button {
                                text: "»"
                                enabled: root.currentPage < root.totalPages
                                font.pixelSize: 12
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#f0f6fc" : "#484f58"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    implicitWidth: 32
                                    radius: 4
                                    color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                    border.color: "#30363d"
                                }
                                onClicked: root.currentPage = root.totalPages
                            }
                        }
                    }
                }
            }
        }
    }
}
