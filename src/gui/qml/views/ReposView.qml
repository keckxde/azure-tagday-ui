import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root

    // ==========================================
    // Repositories State & Properties
    // ==========================================
    property string searchQuery: ""
    property string selectedCategory: (pendingPrsCount > 0) ? "🏷️ PENDING PRs" : (unmergedBranchesCount > 0 ? "🌿 UNMERGED BRANCHES" : "ALL")
    property bool showDeleted: false
    property int currentPage: 1
    property int pageSize: 15
    property int totalPages: 1
    property int totalMatchingCount: 0
    property int contentMargins: 18

    // ==========================================
    // Sidebar State & Properties (PRs & Unmerged Branches)
    // ==========================================
    property bool isPrSidebarOpen: true
    property int sidebarTab: 0 // 0: Pull Requests, 1: Unmerged Branches
    property real prSidebarWidth: (backend && backend.rightSidebarWidth) ? Math.max(320, Math.min(800, backend.rightSidebarWidth)) : 440
    property real minPrSidebarWidth: 320
    property real maxPrSidebarWidth: 800

    // Pull Requests Sidebar State
    property string prSearchQuery: ""
    property string prSelectedRepo: "ALL"
    property string prSelectedStatus: "ALL" // "ALL", "ACTIVE", "COMPLETED", "ABANDONED"
    property string prSelectedTagFilter: "ALL" // "ALL", "TAGGED", "UNTAGGED"
    property int prSortMode: 0 // 0: Time Desc, 1: Time Asc, 2: PR ID Desc, 3: PR ID Asc, 4: Repo A-Z
    property int prCurrentPage: 1
    property int prPageSize: 20
    property int prTotalPages: 1
    property int prTotalMatchingCount: 0

    // Unmerged Branches Sidebar State
    property string branchSearchQuery: ""
    property string branchSelectedRepo: "ALL"
    property int branchSortMode: 0 // 0: Ahead Desc, 1: Date Desc, 2: Branch A-Z, 3: Repo A-Z
    property int branchCurrentPage: 1
    property int branchPageSize: 20
    property int branchTotalPages: 1
    property int branchTotalMatchingCount: 0
    property var filteredBranchesList: []
    property var pagedBranchesList: []

    // Public methods to control PR & Branches sidebar from outside or within
    function openPrSidebar(repoFilter, statusFilter) {
        root.isPrSidebarOpen = true;
        root.sidebarTab = 0;
        if (statusFilter && typeof statusFilter === "boolean") {
            // Called with (statusName, isStatus=true)
            root.prSelectedStatus = repoFilter ? repoFilter.toUpperCase() : "ALL";
            root.prSelectedRepo = "ALL";
        } else if (typeof statusFilter === "string" && statusFilter) {
            root.prSelectedRepo = repoFilter || "ALL";
            root.prSelectedStatus = statusFilter.toUpperCase();
        } else if (repoFilter && repoFilter !== "ALL") {
            root.prSelectedRepo = repoFilter;
            root.prSelectedStatus = "ALL";
        } else {
            root.prSelectedRepo = "ALL";
            root.prSelectedStatus = "ALL";
        }
        root.prSearchQuery = "";
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }

    function openBranchesSidebar(repoFilter) {
        root.isPrSidebarOpen = true;
        root.sidebarTab = 1;
        root.branchSelectedRepo = repoFilter || "ALL";
        root.branchSearchQuery = "";
        root.branchCurrentPage = 1;
        root.updateFilteredBranches();
    }

    function closePrSidebar() {
        root.isPrSidebarOpen = false;
    }

    function togglePrSidebar() {
        if (!root.isPrSidebarOpen) {
            root.isPrSidebarOpen = true;
            root.sidebarTab = 0;
            root.updateFilteredPrs();
        } else if (root.sidebarTab !== 0) {
            root.sidebarTab = 0;
            root.updateFilteredPrs();
        } else {
            root.isPrSidebarOpen = false;
        }
    }

    function toggleBranchesSidebar() {
        if (!root.isPrSidebarOpen) {
            root.isPrSidebarOpen = true;
            root.sidebarTab = 1;
            root.updateFilteredBranches();
        } else if (root.sidebarTab !== 1) {
            root.sidebarTab = 1;
            root.updateFilteredBranches();
        } else {
            root.isPrSidebarOpen = false;
        }
    }

    function filterPrsByRepo(repoName) {
        root.prSelectedRepo = repoName || "ALL";
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }

    function filterPrsByStatus(statusName) {
        root.prSelectedStatus = statusName ? statusName.toUpperCase() : "ALL";
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }

    function filterPrsByTag(tagFilterName) {
        root.prSelectedTagFilter = tagFilterName ? tagFilterName.toUpperCase() : "ALL";
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }

    readonly property int totalPrsCount: {
        return (backend && backend.pullRequests) ? backend.pullRequests.length : 0;
    }

    readonly property int totalBranchesCount: {
        return (backend && backend.unmergedBranches) ? backend.unmergedBranches.length : 0;
    }

    readonly property int activePrsCount: {
        if (!backend || !backend.pullRequests) return 0;
        var count = 0;
        var list = backend.pullRequests;
        for (var i = 0; i < list.length; i++) {
            if (list[i].status === "active") count++;
        }
        return count;
    }

    readonly property int untaggedPrsCount: {
        if (!backend || !backend.pullRequests) return 0;
        var count = 0;
        var list = backend.pullRequests;
        for (var i = 0; i < list.length; i++) {
            if (!list[i].is_tagged && list[i].status === "completed") count++;
        }
        return count;
    }

    readonly property int deletedReposCount: {
        if (!backend || !backend.repositories)
            return 0;
        var count = 0;
        var list = backend.repositories;
        for (var i = 0; i < list.length; i++) {
            var item = list[i];
            if (item.is_deleted === true || (item.category && item.category.toUpperCase() === "DELETED"))
                count++;
        }
        return count;
    }

    readonly property int pendingPrsCount: {
        if (!backend || !backend.repositories)
            return 0;
        var count = 0;
        var list = backend.repositories;
        for (var i = 0; i < list.length; i++) {
            if (list[i].is_deleted === true || (list[i].category && list[i].category.toUpperCase() === "DELETED"))
                continue;
            if (list[i].has_untagged_prs || (list[i].prs_after_tag_count && list[i].prs_after_tag_count > 0))
                count++;
        }
        return count;
    }

    readonly property int unmergedBranchesCount: {
        if (!backend || !backend.repositories)
            return 0;
        var count = 0;
        var list = backend.repositories;
        for (var i = 0; i < list.length; i++) {
            if (list[i].is_deleted === true || (list[i].category && list[i].category.toUpperCase() === "DELETED"))
                continue;
            if (list[i].has_unmerged_branches || (list[i].unmerged_branches_count && list[i].unmerged_branches_count > 0))
                count++;
        }
        return count;
    }

    readonly property int pendingCount: {
        if (!backend || !backend.repositories)
            return 0;
        var count = 0;
        var list = backend.repositories;
        for (var i = 0; i < list.length; i++) {
            if (list[i].is_deleted === true || (list[i].category && list[i].category.toUpperCase() === "DELETED"))
                continue;
            if (list[i].has_pending_changes)
                count++;
        }
        return count;
    }

    function validateSelectedCategory() {
        if (selectedCategory === "🏷️ PENDING PRs" && root.pendingPrsCount === 0) {
            selectedCategory = (root.unmergedBranchesCount > 0) ? "🌿 UNMERGED BRANCHES" : "ALL";
        } else if (selectedCategory === "🌿 UNMERGED BRANCHES" && root.unmergedBranchesCount === 0) {
            selectedCategory = (root.pendingPrsCount > 0) ? "🏷️ PENDING PRs" : "ALL";
        } else if (selectedCategory === "⚠️ PENDING" && root.pendingCount === 0) {
            selectedCategory = "ALL";
        }
    }

    onPendingPrsCountChanged: validateSelectedCategory()
    onUnmergedBranchesCountChanged: validateSelectedCategory()
    onPendingCountChanged: validateSelectedCategory()

    // Shared Column Widths for pixel-perfect alignment across Header and Rows
    readonly property int colRepoWidth: 180
    readonly property int colStableWidth: 110
    readonly property int colUnstableWidth: 110
    readonly property int colBranchWidth: 95

    // ==========================================
    // Filtered & Paged Pull Requests Computation
    // ==========================================
    property var filteredPRsList: []
    property var pagedPRsList: []

    function updateFilteredPrs() {
        if (!backend || !backend.pullRequests) {
            root.filteredPRsList = [];
            root.pagedPRsList = [];
            root.prTotalMatchingCount = 0;
            root.prTotalPages = 1;
            return;
        }

        var list = backend.pullRequests || [];
        var query = root.prSearchQuery.trim().toLowerCase();
        var repoFilter = root.prSelectedRepo;
        var statusFilter = root.prSelectedStatus;
        var tagFilter = root.prSelectedTagFilter;
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
        if (root.prSortMode === 0) {
            // Time Descending (Newest first)
            result.sort(function(a, b) {
                var tA = a.timestamp || "";
                var tB = b.timestamp || "";
                if (tA !== tB) return tA > tB ? -1 : 1;
                return (b.id || 0) - (a.id || 0);
            });
        } else if (root.prSortMode === 1) {
            // Time Ascending (Oldest first)
            result.sort(function(a, b) {
                var tA = a.timestamp || "";
                var tB = b.timestamp || "";
                if (tA !== tB) return tA < tB ? -1 : 1;
                return (a.id || 0) - (b.id || 0);
            });
        } else if (root.prSortMode === 2) {
            // PR ID Descending
            result.sort(function(a, b) {
                return (b.id || 0) - (a.id || 0);
            });
        } else if (root.prSortMode === 3) {
            // PR ID Ascending
            result.sort(function(a, b) {
                return (a.id || 0) - (b.id || 0);
            });
        } else if (root.prSortMode === 4) {
            // Repository A-Z
            result.sort(function(a, b) {
                var rA = (a.repo_name || "").toLowerCase();
                var rB = (b.repo_name || "").toLowerCase();
                if (rA !== rB) return rA < rB ? -1 : 1;
                return (b.id || 0) - (a.id || 0);
            });
        }

        root.filteredPRsList = result;
        root.prTotalMatchingCount = result.length;
        root.prTotalPages = Math.max(1, Math.ceil(result.length / root.prPageSize));
        if (root.prCurrentPage > root.prTotalPages) {
            root.prCurrentPage = 1;
        }

        var start = (root.prCurrentPage - 1) * root.prPageSize;
        root.pagedPRsList = result.slice(start, start + root.prPageSize);
    }

    onPrSearchQueryChanged: {
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }
    onPrSelectedRepoChanged: {
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }
    onPrSelectedStatusChanged: {
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }
    onPrSelectedTagFilterChanged: {
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }
    onPrSortModeChanged: {
        root.updateFilteredPrs();
    }
    onPrPageSizeChanged: {
        root.prTotalPages = Math.max(1, Math.ceil(root.prTotalMatchingCount / root.prPageSize));
        root.prCurrentPage = 1;
        root.updateFilteredPrs();
    }
    onPrCurrentPageChanged: {
        var start = (root.prCurrentPage - 1) * root.prPageSize;
        root.pagedPRsList = root.filteredPRsList.slice(start, start + root.prPageSize);
    }

    // Filtered repositories list for typing / choosing in the PR repo selector
    readonly property var prRepoFilteredList: {
        var allRepos = (backend && backend.prRepositories) ? backend.prRepositories : [];
        var res = ["ALL"];
        for (var i = 0; i < allRepos.length; i++) {
            res.push(allRepos[i]);
        }
        return res;
    }

    // ==========================================
    // Filtered & Paged Unmerged Branches Computation
    // ==========================================
    function updateFilteredBranches() {
        if (!backend || !backend.unmergedBranches) {
            root.filteredBranchesList = [];
            root.pagedBranchesList = [];
            root.branchTotalMatchingCount = 0;
            root.branchTotalPages = 1;
            return;
        }

        var list = backend.unmergedBranches || [];
        var query = root.branchSearchQuery.trim().toLowerCase();
        var repoFilter = root.branchSelectedRepo;
        var result = [];

        for (var i = 0; i < list.length; i++) {
            var b = list[i];

            if (repoFilter !== "ALL" && b.repo_name !== repoFilter) {
                continue;
            }

            if (query !== "") {
                var bName = (b.branch_name || "").toLowerCase();
                var committer = (b.committer || "").toLowerCase();
                var comment = (b.comment || "").toLowerCase();
                var shortHash = (b.short_hash || "").toLowerCase();
                var repoName = (b.repo_name || "").toLowerCase();
                var prepPrId = (b.prepared_pr_id || "").toLowerCase();
                var prepPrTitle = (b.prepared_pr_title || "").toLowerCase();
                if (bName.indexOf(query) === -1 &&
                    committer.indexOf(query) === -1 &&
                    comment.indexOf(query) === -1 &&
                    shortHash.indexOf(query) === -1 &&
                    repoName.indexOf(query) === -1 &&
                    prepPrId.indexOf(query) === -1 &&
                    prepPrTitle.indexOf(query) === -1) {
                    continue;
                }
            }

            result.push(b);
        }

        // Apply Sorting
        if (root.branchSortMode === 0) {
            // Ahead Descending
            result.sort(function(a, b) {
                var aDiff = (b.ahead || 0) - (a.ahead || 0);
                if (aDiff !== 0) return aDiff;
                var tA = a.commit_date || "";
                var tB = b.commit_date || "";
                if (tA !== tB) return tA > tB ? -1 : 1;
                return (a.branch_name || "").localeCompare(b.branch_name || "");
            });
        } else if (root.branchSortMode === 1) {
            // Commit Date Descending (Newest first)
            result.sort(function(a, b) {
                var tA = a.commit_date || "";
                var tB = b.commit_date || "";
                if (tA !== tB) return tA > tB ? -1 : 1;
                return (b.ahead || 0) - (a.ahead || 0);
            });
        } else if (root.branchSortMode === 2) {
            // Branch Name A-Z
            result.sort(function(a, b) {
                return (a.branch_name || "").localeCompare(b.branch_name || "");
            });
        } else if (root.branchSortMode === 3) {
            // Repository A-Z
            result.sort(function(a, b) {
                var rA = (a.repo_name || "").toLowerCase();
                var rB = (b.repo_name || "").toLowerCase();
                if (rA !== rB) return rA < rB ? -1 : 1;
                return (a.branch_name || "").localeCompare(b.branch_name || "");
            });
        }

        root.filteredBranchesList = result;
        root.branchTotalMatchingCount = result.length;
        root.branchTotalPages = Math.max(1, Math.ceil(result.length / root.branchPageSize));
        if (root.branchCurrentPage > root.branchTotalPages) {
            root.branchCurrentPage = 1;
        }

        var start = (root.branchCurrentPage - 1) * root.branchPageSize;
        root.pagedBranchesList = result.slice(start, start + root.branchPageSize);
    }

    onBranchSearchQueryChanged: {
        root.branchCurrentPage = 1;
        root.updateFilteredBranches();
    }
    onBranchSelectedRepoChanged: {
        root.branchCurrentPage = 1;
        root.updateFilteredBranches();
    }
    onBranchSortModeChanged: {
        root.updateFilteredBranches();
    }
    onBranchPageSizeChanged: {
        root.branchTotalPages = Math.max(1, Math.ceil(root.branchTotalMatchingCount / root.branchPageSize));
        root.branchCurrentPage = 1;
        root.updateFilteredBranches();
    }
    onBranchCurrentPageChanged: {
        var start = (root.branchCurrentPage - 1) * root.branchPageSize;
        root.pagedBranchesList = root.filteredBranchesList.slice(start, start + root.branchPageSize);
    }

    // Filtered repositories list for typing / choosing in the Unmerged Branches repo selector
    readonly property var branchRepoFilteredList: {
        var set = {};
        if (backend && backend.unmergedBranches) {
            for (var i = 0; i < backend.unmergedBranches.length; i++) {
                var rn = backend.unmergedBranches[i].repo_name;
                if (rn) set[rn] = true;
            }
        }
        var arr = Object.keys(set).sort();
        return ["ALL"].concat(arr);
    }

    // ==========================================
    // Main Container Split: Repos Table + PR Sidebar
    // ==========================================
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================
        // LEFT: Repositories Page Main Content
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            clip: true

            ColumnLayout {
                id: mainLayout
                anchors.fill: parent
                anchors.margins: root.contentMargins
                spacing: 14

                // Top Toolbar Actions Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "Repositories"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }

                    Text {
                        text: "(" + root.totalMatchingCount + " repos)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#8b949e"
                    }

                    Item { Layout.fillWidth: true }

                    // Pull Requests Sidebar Toggle Button
                    Button {
                        id: togglePrSidebarBtn
                        text: "🔀 PRs (" + root.totalPrsCount + ")"
                        checkable: true
                        checked: root.isPrSidebarOpen && root.sidebarTab === 0
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: (root.isPrSidebarOpen && root.sidebarTab === 0) ? "Hide Pull Requests sidebar" : "Open Pull Requests sidebar with search & filters"
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "🔀"
                                font.pixelSize: 11
                            }
                            Text {
                                text: "PRs (" + root.totalPrsCount + ")"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: togglePrSidebarBtn.checked ? "#ffffff" : ((root.activePrsCount > 0 || root.untaggedPrsCount > 0) ? "#79c0ff" : "#c9d1d9")
                            }
                            Rectangle {
                                visible: root.activePrsCount > 0
                                height: 16
                                width: activePrPillText.implicitWidth + 8
                                radius: 8
                                color: togglePrSidebarBtn.checked ? "#388bfd" : "#1f6feb"
                                Text {
                                    id: activePrPillText
                                    anchors.centerIn: parent
                                    text: root.activePrsCount === 1 ? "1 active PR" : (root.activePrsCount + " active PRs")
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }
                            }
                            Rectangle {
                                visible: root.untaggedPrsCount > 0
                                height: 16
                                width: untaggedPrPillText.implicitWidth + 8
                                radius: 8
                                color: togglePrSidebarBtn.checked ? "#b08800" : "#9e6a03"
                                Text {
                                    id: untaggedPrPillText
                                    anchors.centerIn: parent
                                    text: root.untaggedPrsCount === 1 ? "1 untagged PR" : (root.untaggedPrsCount + " untagged PRs")
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }
                            }
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 155 + (root.untaggedPrsCount > 0 ? untaggedPrPillText.implicitWidth + 12 : 0)
                            radius: 6
                            color: togglePrSidebarBtn.checked ? "#1f6feb" : (togglePrSidebarBtn.hovered ? "#21262d" : "#161b22")
                            border.color: togglePrSidebarBtn.checked ? "#58a6ff" : (root.activePrsCount > 0 ? "#388bfd" : "#30363d")
                            border.width: 1
                        }
                        onClicked: root.togglePrSidebar()
                    }

                    // Unmerged Branches Sidebar Toggle Button
                    Button {
                        id: toggleBranchesSidebarBtn
                        text: "🌿 Branches (" + root.totalBranchesCount + ")"
                        checkable: true
                        checked: root.isPrSidebarOpen && root.sidebarTab === 1
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: (root.isPrSidebarOpen && root.sidebarTab === 1) ? "Hide Unmerged Branches sidebar" : "Open Unmerged Branches sidebar"
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "🌿"
                                font.pixelSize: 11
                            }
                            Text {
                                text: "Branches (" + root.totalBranchesCount + ")"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: toggleBranchesSidebarBtn.checked ? "#ffffff" : (root.totalBranchesCount > 0 ? "#bc8cff" : "#c9d1d9")
                            }
                            Rectangle {
                                property int bCnt: root.totalBranchesCount > 0 ? root.totalBranchesCount : root.unmergedBranchesCount
                                visible: bCnt > 0
                                height: 16
                                width: unmergedBrPillText.implicitWidth + 8
                                radius: 8
                                color: toggleBranchesSidebarBtn.checked ? "#a371f7" : "#8957e5"
                                Text {
                                    id: unmergedBrPillText
                                    anchors.centerIn: parent
                                    property int bCnt: root.totalBranchesCount > 0 ? root.totalBranchesCount : root.unmergedBranchesCount
                                    text: bCnt === 1 ? "1 branch ahead" : (bCnt + " branches ahead")
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }
                            }
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 165
                            radius: 6
                            color: toggleBranchesSidebarBtn.checked ? "#6e40c9" : (toggleBranchesSidebarBtn.hovered ? "#21262d" : "#161b22")
                            border.color: toggleBranchesSidebarBtn.checked ? "#bc8cff" : (root.totalBranchesCount > 0 ? "#8957e5" : "#30363d")
                            border.width: 1
                        }
                        onClicked: root.toggleBranchesSidebar()
                    }

                    Button {
                        text: "🏷️ Category Settings"
                        font.pixelSize: 11
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#bc8cff"
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 140
                            radius: 6
                            color: parent.hovered ? "#21262d" : "#161b22"
                            border.color: "#30363d"
                        }
                        onClicked: repoCategoriesDialog.openDialog()
                    }

                    Button {
                        text: "📑 Open TAGDAY.md"
                        font.pixelSize: 11
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#58a6ff"
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 135
                            radius: 6
                            color: parent.hovered ? "#21262d" : "#161b22"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (backend)
                                backend.open_tagday_markdown_report();
                        }
                    }

                    CheckBox {
                        id: showDeletedCb
                        visible: root.deletedReposCount > 0
                        text: "Show deleted (" + root.deletedReposCount + ")"
                        checked: root.showDeleted
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.checked ? "#f85149" : "#8b949e"
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: parent.indicator.width + 4
                        }
                        onToggled: {
                            root.showDeleted = checked;
                            root.currentPage = 1;
                            root.updateFilteredModel();
                        }
                    }

                    SearchBar {
                        placeholder: "Filter repositories..."
                        onSearchUpdated: function (query) {
                            root.searchQuery = query;
                        }
                    }

                    Button {
                        text: "↻ Refresh"
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#f0f6fc"
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 78
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: backend.refresh_all_data()
                    }
                }

                // Category & Pending Filter Bar with Full Width Wrapping
                Item {
                    Layout.fillWidth: true
                    Layout.preferredWidth: parent ? parent.width : root.width
                    implicitHeight: catFlow.implicitHeight

                    Flow {
                        id: catFlow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 6

                        Repeater {
                            model: {
                                var base = [];
                                if (root.pendingPrsCount > 0) {
                                    base.push("🏷️ PENDING PRs");
                                }
                                if (root.unmergedBranchesCount > 0) {
                                    base.push("🌿 UNMERGED BRANCHES");
                                }
                                if (root.pendingCount > 0 && root.pendingPrsCount === 0 && root.unmergedBranchesCount === 0) {
                                    base.push("⚠️ PENDING");
                                }
                                base.push("ALL");
                                var hasDeletedCat = false;
                                if (backend && backend.repoCategories) {
                                    for (var i = 0; i < backend.repoCategories.length; i++) {
                                        var cname = backend.repoCategories[i].name;
                                        if (cname === "DELETED") {
                                            hasDeletedCat = true;
                                            if (root.deletedReposCount > 0) {
                                                base.push("DELETED");
                                            }
                                        } else {
                                            base.push(cname);
                                        }
                                    }
                                } else {
                                    base.push("GENERIC", "3RDPARTY", "OTHERS");
                                }
                                if (!hasDeletedCat && root.deletedReposCount > 0) {
                                    base.push("DELETED");
                                }
                                return base;
                            }
                            Button {
                                text: {
                                    if (modelData === "🏷️ PENDING PRs")
                                        return "🏷️ PENDING PRs (" + root.pendingPrsCount + ")";
                                    if (modelData === "🌿 UNMERGED BRANCHES")
                                        return "🌿 UNMERGED BRANCHES (" + root.unmergedBranchesCount + ")";
                                    if (modelData === "⚠️ PENDING")
                                        return "⚠️ ALL PENDING (" + root.pendingCount + ")";
                                    if (modelData === "DELETED")
                                        return "🗑️ DELETED (" + root.deletedReposCount + ")";
                                    return modelData;
                                }
                                checkable: true
                                checked: root.selectedCategory === modelData
                                font.pixelSize: 11
                                font.weight: checked ? Font.DemiBold : Font.Normal
                                leftPadding: 12
                                rightPadding: 12
                                topPadding: 4
                                bottomPadding: 4
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: {
                                        if (parent.checked) return "#ffffff";
                                        if (modelData === "🏷️ PENDING PRs") return "#f0883e";
                                        if (modelData === "🌿 UNMERGED BRANCHES") return "#bc8cff";
                                        if (modelData === "⚠️ PENDING") return "#f0883e";
                                        if (modelData === "DELETED") return "#f85149";
                                        return "#8b949e";
                                    }
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    radius: 14
                                    color: {
                                        if (parent.checked) {
                                            if (modelData === "🏷️ PENDING PRs") return "#d29922";
                                            if (modelData === "🌿 UNMERGED BRANCHES") return "#8957e5";
                                            if (modelData === "⚠️ PENDING") return "#d29922";
                                            if (modelData === "DELETED") return "#cf222e";
                                            return (backend ? backend.get_category_color(modelData) : "#1f6feb");
                                        }
                                        return parent.hovered ? "#21262d" : "#161b22";
                                    }
                                    border.color: {
                                        if (parent.checked) {
                                            if (modelData === "🏷️ PENDING PRs") return "#e3b341";
                                            if (modelData === "🌿 UNMERGED BRANCHES") return "#a371f7";
                                            if (modelData === "⚠️ PENDING") return "#e3b341";
                                            if (modelData === "DELETED") return "#ff7b72";
                                            return "#388bfd";
                                        }
                                        if (modelData === "🏷️ PENDING PRs") return "#6e4b10";
                                        if (modelData === "🌿 UNMERGED BRANCHES") return "#5a3e85";
                                        if (modelData === "⚠️ PENDING") return "#6e4b10";
                                        if (modelData === "DELETED") return "#4c1c1b";
                                        return "#30363d";
                                    }
                                }
                                onClicked: root.selectedCategory = modelData
                            }
                        }
                    }
                }

                // Table Header
                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    color: "#161b22"
                    radius: 6
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12 + (repoVBar.visible ? repoVBar.width + 4 : 0)
                        spacing: 10

                        Text {
                            text: "REPOSITORY"
                            Layout.preferredWidth: root.colRepoWidth
                            Layout.minimumWidth: root.colRepoWidth
                            Layout.maximumWidth: root.colRepoWidth
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }
                        Text {
                            text: "STABLE TAG"
                            Layout.preferredWidth: root.colStableWidth
                            Layout.minimumWidth: root.colStableWidth
                            Layout.maximumWidth: root.colStableWidth
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }
                        Text {
                            text: "UNSTABLE TAG"
                            Layout.preferredWidth: root.colUnstableWidth
                            Layout.minimumWidth: root.colUnstableWidth
                            Layout.maximumWidth: root.colUnstableWidth
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }
                        Text {
                            text: "PENDING CHANGES & PULL REQUESTS"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 180
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }
                        Text {
                            text: "BRANCH"
                            Layout.preferredWidth: root.colBranchWidth
                            Layout.minimumWidth: root.colBranchWidth
                            Layout.maximumWidth: root.colBranchWidth
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }
                        Item {
                            Layout.preferredWidth: 64
                        } // Spacer for row actions
                    }
                }

                // Repositories List
                ListView {
                    id: repoListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4

                    model: ListModel {
                        id: filteredRepos
                    }

                    ScrollBar.vertical: ScrollBar {
                        id: repoVBar
                        active: true
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: repoVBar.pressed ? "#58a6ff" : (repoVBar.hovered ? "#8b949e" : "#30363d")
                        }
                        background: Rectangle {
                            implicitWidth: 6
                            color: "transparent"
                        }
                    }

                    delegate: Rectangle {
                        id: rowRect
                        width: repoListView.width - (repoVBar.visible ? repoVBar.width + 4 : 0)
                        height: 52
                        property bool isSelectedInPrSidebar: root.isPrSidebarOpen && root.prSelectedRepo === model.name
                        color: isSelectedInPrSidebar ? "#1c2536" : (itemMouse.containsMouse ? "#1c2128" : "#0d1117")
                        radius: 6
                        border.color: isSelectedInPrSidebar ? "#58a6ff" : (itemMouse.containsMouse ? (model.has_pending_changes ? "#d29922" : "#388bfd") : "#21262d")
                        border.width: isSelectedInPrSidebar ? 2 : 1

                        // Left pending indicator bar
                        Rectangle {
                            width: 3
                            height: parent.height - 12
                            anchors.left: parent.left
                            anchors.leftMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 1.5
                            color: (model.prs_after_tag_count > 0) ? "#f0883e" : "#bc8cff"
                            visible: !!model.has_pending_changes
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            // 1. Repository Name & Category
                            ColumnLayout {
                                Layout.preferredWidth: root.colRepoWidth
                                spacing: 3

                                Text {
                                    text: model.name
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: model.is_deleted ? "#f85149" : "#f0f6fc"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    spacing: 6
                                    Rectangle {
                                        implicitHeight: 18
                                        implicitWidth: catText.implicitWidth + 10
                                        radius: 3
                                        color: model.is_deleted ? "#381113" : "#161b22"
                                        border.color: model.is_deleted ? "#f85149" : (backend ? backend.get_category_color(model.category) : "#30363d")
                                        border.width: 1

                                        Text {
                                            id: catText
                                            anchors.centerIn: parent
                                            text: model.is_deleted ? "DELETED" : (model.category || "GENERIC")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: model.is_deleted ? "#ff7b72" : (backend ? backend.get_category_color(model.category) : "#8b949e")
                                        }
                                    }
                                }
                            }

                            // 2. Stable Tag
                            Item {
                                Layout.preferredWidth: root.colStableWidth
                                Layout.minimumWidth: root.colStableWidth
                                Layout.maximumWidth: root.colStableWidth
                                height: parent.height

                                Rectangle {
                                    visible: !!model.stable_tag && model.stable_tag !== "-"
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 24
                                    width: Math.min(parent.width, stableRow.implicitWidth + 14)
                                    radius: 4
                                    color: "#162b20"
                                    border.color: "#238636"
                                    border.width: 1

                                    Row {
                                        id: stableRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: "🏷️"
                                            font.pixelSize: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            id: stableText
                                            text: model.stable_tag || "-"
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: "#7ee787"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                Text {
                                    visible: !model.stable_tag || model.stable_tag === "-"
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    text: "-"
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 12
                                    color: "#484f58"
                                }
                            }

                            // 3. Unstable Tag
                            Item {
                                Layout.preferredWidth: root.colUnstableWidth
                                Layout.minimumWidth: root.colUnstableWidth
                                Layout.maximumWidth: root.colUnstableWidth
                                height: parent.height

                                Rectangle {
                                    visible: !!model.unstable_tag && model.unstable_tag !== "-"
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 24
                                    width: Math.min(parent.width, unstableRow.implicitWidth + 14)
                                    radius: 4
                                    color: "#142233"
                                    border.color: "#388bfd"
                                    border.width: 1

                                    Row {
                                        id: unstableRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: "⚡"
                                            font.pixelSize: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            id: unstableText
                                            text: model.unstable_tag || "-"
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: "#79c0ff"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                Text {
                                    visible: !model.unstable_tag || model.unstable_tag === "-"
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    text: "-"
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 12
                                    color: "#484f58"
                                }
                            }

                            // 4. Pending Changes & Pull Requests Badges
                            Item {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 180
                                height: parent.height

                                RowLayout {
                                    visible: !!model.has_pending_changes
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 6

                                    // Badge 1: Untagged PRs (Click to view in PR sidebar)
                                    Rectangle {
                                        visible: !!(model.prs_after_tag_count > 0)
                                        height: 26
                                        radius: 4
                                        color: untaggedPrMa.containsMouse ? "#3b2612" : "#281b0f"
                                        border.color: "#d29922"
                                        border.width: 1
                                        implicitWidth: prRow.implicitWidth + 16

                                        Row {
                                            id: prRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: "🏷️"
                                                font.pixelSize: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: model.prs_after_tag_count + " untagged PR" + (model.prs_after_tag_count > 1 ? "s" : "")
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                color: "#f0883e"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: untaggedPrMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.text: "Open PR Sidebar for " + model.name + " (Untagged PRs)"
                                            onClicked: {
                                                root.openPrSidebar(model.name, false);
                                                root.filterPrsByTag("UNTAGGED");
                                            }
                                        }
                                    }

                                    // Badge 2: Unmerged Branches (Click to view in Unmerged Branches sidebar)
                                    Rectangle {
                                        visible: !!(model.unmerged_branches_count > 0)
                                        height: 26
                                        radius: 4
                                        color: unmergedBrMa.containsMouse ? "#2d1b4e" : "#1e172a"
                                        border.color: unmergedBrMa.containsMouse ? "#bc8cff" : "#8957e5"
                                        border.width: 1
                                        implicitWidth: brRow.implicitWidth + 16

                                        Row {
                                             id: brRow
                                             anchors.centerIn: parent
                                             spacing: 4
                                             Text {
                                                 text: "🌿"
                                                 font.pixelSize: 10
                                                 anchors.verticalCenter: parent.verticalCenter
                                             }
                                             Text {
                                                 text: model.unmerged_branches_count + " branch" + (model.unmerged_branches_count > 1 ? "es" : "") + " ahead"
                                                 font.family: "Segoe UI, sans-serif"
                                                 font.pixelSize: 11
                                                 font.weight: Font.DemiBold
                                                 color: "#bc8cff"
                                                 anchors.verticalCenter: parent.verticalCenter
                                             }
                                        }

                                        MouseArea {
                                            id: unmergedBrMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.text: "Open Unmerged Branches Sidebar for " + model.name
                                            onClicked: {
                                                root.openBranchesSidebar(model.name);
                                            }
                                        }
                                    }

                                    // Badge 3: Active PRs (Click to view in PR sidebar)
                                    Rectangle {
                                        visible: !!(model.active_prs_count > 0)
                                        height: 26
                                        radius: 4
                                        color: activePrMa.containsMouse ? "#1c3554" : "#142233"
                                        border.color: "#388bfd"
                                        border.width: 1
                                        implicitWidth: actRow.implicitWidth + 16

                                        Row {
                                            id: actRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: "🔀"
                                                font.pixelSize: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: model.active_prs_count + " active PR" + (model.active_prs_count > 1 ? "s" : "")
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                color: "#79c0ff"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: activePrMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.text: "Open PR Sidebar for " + model.name + " (Active PRs)"
                                            onClicked: {
                                                root.openPrSidebar(model.name, false);
                                                root.filterPrsByStatus("ACTIVE");
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                // Clean badge when up to date
                                Row {
                                    visible: !model.has_pending_changes
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Text {
                                        text: "✓"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: "#238636"
                                    }
                                    Text {
                                        text: "Clean / Up to date"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#3fb950"
                                    }
                                }
                            }

                            // 5. Default Branch
                            Item {
                                Layout.preferredWidth: root.colBranchWidth
                                Layout.minimumWidth: root.colBranchWidth
                                Layout.maximumWidth: root.colBranchWidth
                                height: parent.height

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    Text {
                                        text: "🌿"
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        text: model.default_branch || "main"
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // 6. Action buttons: 🔀 PR Sidebar button + Tag Day link
                            RowLayout {
                                Layout.preferredWidth: 64
                                spacing: 6

                                // PR Sidebar Quick Button
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 4
                                    color: prQuickMa.containsMouse ? "#1f6feb" : "#161b22"
                                    border.color: prQuickMa.containsMouse ? "#58a6ff" : "#30363d"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "🔀"
                                        font.pixelSize: 11
                                    }

                                    MouseArea {
                                        id: prQuickMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.delay: 200
                                        ToolTip.text: "View Pull Requests for " + model.name + " in sidebar"
                                        onClicked: {
                                            root.openPrSidebar(model.name, false);
                                        }
                                    }
                                }

                                // Jump to Tag Day Chevron
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 4
                                    color: tagDayQuickMa.containsMouse ? "#21262d" : "transparent"
                                    border.color: tagDayQuickMa.containsMouse ? "#388bfd" : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "➔"
                                        font.pixelSize: 12
                                        color: model.has_pending_changes ? "#d29922" : "#388bfd"
                                    }

                                    MouseArea {
                                        id: tagDayQuickMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.delay: 200
                                        ToolTip.text: "Open Tag Day report for " + model.name
                                        onClicked: {
                                            if (typeof window !== "undefined" && window.navigateToTagDayRepo) {
                                                window.navigateToTagDayRepo(model.name);
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
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onClicked: {
                                // Clicking anywhere on the row selects this repository in the PR sidebar or navigates to Tag Day
                                if (root.isPrSidebarOpen) {
                                    root.filterPrsByRepo(model.name);
                                } else {
                                    if (typeof window !== "undefined" && window.navigateToTagDayRepo) {
                                        window.navigateToTagDayRepo(model.name);
                                    }
                                }
                            }
                        }
                    }
                }

                // Pagination Bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    color: "#161b22"
                    radius: 6
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Text {
                            text: "Page " + root.currentPage + " of " + Math.max(1, root.totalPages) + " (" + root.totalMatchingCount + " repositories)"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                        }

                        Item { Layout.fillWidth: true }

                        // Page size selector
                        Row {
                            spacing: 4
                            Text {
                                text: "Rows:"
                                font.pixelSize: 12
                                color: "#8b949e"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Repeater {
                                model: [10, 15, 25, 50]
                                Button {
                                    text: modelData.toString()
                                    checkable: true
                                    checked: root.pageSize === modelData
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
                                        implicitWidth: 36
                                        radius: 4
                                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                                        border.color: parent.checked ? "#388bfd" : "#30363d"
                                    }
                                    onClicked: {
                                        root.pageSize = modelData;
                                        root.currentPage = 1;
                                        root.updateFilteredModel();
                                    }
                                }
                            }
                        }

                        Item { width: 8 }

                        // First Page
                        Button {
                            text: "«"
                            enabled: root.currentPage > 1
                            font.pixelSize: 14
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
                            onClicked: {
                                root.currentPage = 1;
                                root.updateFilteredModel();
                            }
                        }

                        // Previous Page
                        Button {
                            text: "‹ Prev"
                            enabled: root.currentPage > 1
                            font.pixelSize: 11
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: parent.enabled ? "#f0f6fc" : "#484f58"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 28
                                implicitWidth: 64
                                radius: 4
                                color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (root.currentPage > 1) {
                                    root.currentPage--;
                                    root.updateFilteredModel();
                                }
                            }
                        }

                        // Next Page
                        Button {
                            text: "Next ›"
                            enabled: root.currentPage < root.totalPages
                            font.pixelSize: 11
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: parent.enabled ? "#f0f6fc" : "#484f58"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 28
                                implicitWidth: 64
                                radius: 4
                                color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (root.currentPage < root.totalPages) {
                                    root.currentPage++;
                                    root.updateFilteredModel();
                                }
                            }
                        }

                        // Last Page
                        Button {
                            text: "»"
                            enabled: root.currentPage < root.totalPages
                            font.pixelSize: 14
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
                            onClicked: {
                                root.currentPage = root.totalPages;
                                root.updateFilteredModel();
                            }
                        }
                    }
                }
            }
        }

        // ==========================================
        // RIGHT: Pull Requests Sidebar (Resizable & Collapsible)
        // ==========================================
        Rectangle {
            id: prSidebarRect
            Layout.preferredWidth: root.isPrSidebarOpen ? root.prSidebarWidth : 0
            Layout.fillHeight: true
            visible: root.isPrSidebarOpen || Layout.preferredWidth > 0
            color: "#161b22"
            border.color: "#30363d"
            border.width: 1
            clip: true
            z: 10

            // Resizable Splitter Drag Handle at left edge
            Rectangle {
                id: prDragHandle
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 6
                color: prDragMa.containsMouse || prDragMa.pressed ? Qt.rgba(88 / 255, 166 / 255, 255 / 255, 0.4) : "transparent"
                z: 20

                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    height: 36
                    radius: 1
                    color: prDragMa.containsMouse || prDragMa.pressed ? "#58a6ff" : "#30363d"
                }

                property real _startX: 0
                property real _startWidth: 0

                MouseArea {
                    id: prDragMa
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.SizeHorCursor

                    onPressed: function(mouse) {
                        prDragHandle._startX = mouse.x;
                        prDragHandle._startWidth = root.prSidebarWidth;
                    }

                    onPositionChanged: function(mouse) {
                        if (pressed) {
                            var delta = mouse.x - prDragHandle._startX;
                            var newW = Math.max(root.minPrSidebarWidth, Math.min(root.maxPrSidebarWidth, prDragHandle._startWidth - delta));
                            root.prSidebarWidth = newW;
                        }
                    }

                    onReleased: {
                        if (backend && typeof backend.setRightSidebarWidth === "function") {
                            backend.setRightSidebarWidth(Math.round(root.prSidebarWidth));
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 10

                // ==========================================
                // Top Tab Bar: Switch between PRs & Unmerged Branches
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    color: "#0d1117"
                    radius: 6
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        // Tab 0: Pull Requests
                        Button {
                            id: tabPrBtn
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            checkable: true
                            checked: root.sidebarTab === 0
                            font.pixelSize: 11
                            font.weight: checked ? Font.DemiBold : Font.Normal
                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: "🔀"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: "Pull Requests (" + root.totalPrsCount + ")"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: tabPrBtn.checked ? Font.DemiBold : Font.Normal
                                    color: tabPrBtn.checked ? "#ffffff" : "#8b949e"
                                }
                                Rectangle {
                                    visible: root.activePrsCount > 0
                                    implicitHeight: 16
                                    implicitWidth: activePrsBadgeText.implicitWidth + 8
                                    radius: 8
                                    color: tabPrBtn.checked ? "#388bfd" : "#1f6feb"
                                    border.color: "#58a6ff"
                                    border.width: 1
                                    Text {
                                        id: activePrsBadgeText
                                        anchors.centerIn: parent
                                        text: root.activePrsCount === 1 ? "1 active PR" : (root.activePrsCount + " active PRs")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                }
                                Rectangle {
                                    visible: root.untaggedPrsCount > 0
                                    implicitHeight: 16
                                    implicitWidth: untaggedPrsBadgeText.implicitWidth + 8
                                    radius: 8
                                    color: tabPrBtn.checked ? "#b08800" : "#9e6a03"
                                    border.color: "#f0883e"
                                    border.width: 1
                                    Text {
                                        id: untaggedPrsBadgeText
                                        anchors.centerIn: parent
                                        text: root.untaggedPrsCount === 1 ? "1 untagged PR" : (root.untaggedPrsCount + " untagged PRs")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                }
                            }
                            background: Rectangle {
                                radius: 4
                                color: tabPrBtn.checked ? "#1f6feb" : (tabPrBtn.hovered ? "#21262d" : "transparent")
                                border.color: tabPrBtn.checked ? "#388bfd" : "transparent"
                            }
                            onClicked: {
                                root.sidebarTab = 0;
                                root.updateFilteredPrs();
                            }
                        }

                        // Tab 1: Branches ahead
                        Button {
                            id: tabBranchesBtn
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            checkable: true
                            checked: root.sidebarTab === 1
                            font.pixelSize: 11
                            font.weight: checked ? Font.DemiBold : Font.Normal
                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: "🌿"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: "Branches ahead (" + root.totalBranchesCount + ")"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: tabBranchesBtn.checked ? Font.DemiBold : Font.Normal
                                    color: tabBranchesBtn.checked ? "#ffffff" : "#8b949e"
                                }
                                Rectangle {
                                    property int bCnt: root.totalBranchesCount > 0 ? root.totalBranchesCount : root.unmergedBranchesCount
                                    visible: bCnt > 0
                                    implicitHeight: 16
                                    implicitWidth: branchesAheadBadgeText.implicitWidth + 8
                                    radius: 8
                                    color: tabBranchesBtn.checked ? "#a371f7" : "#8957e5"
                                    border.color: "#bc8cff"
                                    border.width: 1
                                    Text {
                                        id: branchesAheadBadgeText
                                        anchors.centerIn: parent
                                        property int bCnt: root.totalBranchesCount > 0 ? root.totalBranchesCount : root.unmergedBranchesCount
                                        text: bCnt === 1 ? "1 branch ahead" : (bCnt + " branches ahead")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                }
                            }
                            background: Rectangle {
                                radius: 4
                                color: tabBranchesBtn.checked ? "#6e40c9" : (tabBranchesBtn.hovered ? "#21262d" : "transparent")
                                border.color: tabBranchesBtn.checked ? "#bc8cff" : "transparent"
                            }
                            onClicked: {
                                root.sidebarTab = 1;
                                root.updateFilteredBranches();
                            }
                        }

                        // Close Sidebar Button
                        Button {
                            Layout.preferredWidth: 28
                            Layout.fillHeight: true
                            font.pixelSize: 12
                            ToolTip.visible: hovered
                            ToolTip.text: "Close sidebar"
                            contentItem: Text {
                                text: "✕"
                                font: parent.font
                                color: parent.hovered ? "#f85149" : "#8b949e"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 4
                                color: parent.hovered ? "#30363d" : "transparent"
                            }
                            onClicked: root.closePrSidebar()
                        }
                    }
                }

                // ==========================================
                // TAB 0 CONTENT: PULL REQUESTS VIEW
                // ==========================================
                ColumnLayout {
                    id: prsContentLayout
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.sidebarTab === 0
                    spacing: 12

                    // Sidebar Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "🔀"
                            font.pixelSize: 18
                        }

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: "Pull Requests"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                        Text {
                            text: {
                                var prefix = (root.prSelectedRepo !== "ALL") ? ("📁 " + root.prSelectedRepo) : "All Repositories";
                                return prefix + " (" + root.prTotalMatchingCount + " of " + root.totalPrsCount + ")";
                            }
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: root.prSelectedRepo !== "ALL" ? "#58a6ff" : "#8b949e"
                            elide: Text.ElideRight
                            Layout.maximumWidth: root.prSidebarWidth - 220
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Reset repo filter chip if a repo is currently selected
                    Rectangle {
                        visible: root.prSelectedRepo !== "ALL"
                        implicitHeight: 24
                        implicitWidth: clearRepoText.implicitWidth + 14
                        radius: 4
                        color: clearRepoMa.containsMouse ? "#30363d" : "#21262d"
                        border.color: "#388bfd"

                        Text {
                            id: clearRepoText
                            anchors.centerIn: parent
                            text: "✕ All Repos"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#58a6ff"
                        }

                        MouseArea {
                            id: clearRepoMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Clear repository filter to show PRs from all repositories"
                            onClicked: {
                                root.prSelectedRepo = "ALL";
                            }
                        }
                    }

                    // Patch Titles Button
                    Button {
                        text: "✨ Patch"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: "Patch PR titles with [<TYPE>_<NR>] tags from referenced work items"
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#79c0ff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 26
                            implicitWidth: 62
                            radius: 4
                            color: parent.hovered ? "#1f6feb" : "#16243b"
                            border.color: "#388bfd"
                        }
                        onClicked: {
                            if (backend) backend.patch_pr_titles();
                        }
                    }

                    // Sync PRs Button
                    Button {
                        text: "⚡ Sync"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: "Sync pull requests with Azure DevOps API"
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 26
                            implicitWidth: 56
                            radius: 4
                            color: parent.hovered ? "#238636" : "#2ea043"
                            border.color: "#3fb950"
                        }
                        onClicked: {
                            if (backend) backend.sync_pull_requests_async();
                        }
                    }

                    // Close Sidebar Button
                    Button {
                        text: "✕"
                        font.pixelSize: 12
                        font.weight: Font.Bold
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
                            color: parent.hovered ? "#30363d" : "transparent"
                        }
                        onClicked: root.closePrSidebar()
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                // ==========================================
                // Filters: Search, Status, Tag, Sort
                // ==========================================
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Search Input + Repo Dropdown Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Search Field
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 30
                            color: "#0d1117"
                            radius: 6
                            border.color: prSearchInput.activeFocus ? "#58a6ff" : "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                Text { text: "🔍"; font.pixelSize: 11 }
                                TextInput {
                                    id: prSearchInput
                                    Layout.fillWidth: true
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#f0f6fc"
                                    selectByMouse: true
                                    text: root.prSearchQuery
                                    onTextChanged: root.prSearchQuery = text

                                    Text {
                                        text: "Search by ID, title, author, branch..."
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#484f58"
                                        visible: !prSearchInput.text && !prSearchInput.activeFocus
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Text {
                                    visible: !!prSearchInput.text
                                    text: "✕"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: prSearchInput.text = ""
                                    }
                                }
                            }
                        }

                        // Repository Filter Dropdown
                        ComboBox {
                            id: prRepoCombo
                            implicitHeight: 30
                            implicitWidth: 140
                            model: root.prRepoFilteredList
                            currentIndex: {
                                var idx = root.prRepoFilteredList.indexOf(root.prSelectedRepo);
                                return idx >= 0 ? idx : 0;
                            }
                            onActivated: function(index) {
                                root.prSelectedRepo = root.prRepoFilteredList[index];
                            }
                            font.pixelSize: 11
                            contentItem: Text {
                                text: parent.displayText
                                font: parent.font
                                color: "#f0f6fc"
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                leftPadding: 8
                            }
                            background: Rectangle {
                                color: "#0d1117"
                                radius: 6
                                border.color: "#30363d"
                            }
                        }
                    }

                    // Filter Chips Row: Status + Tag + Sort
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Status Filter Chips
                        Repeater {
                            model: ["ALL", "ACTIVE", "COMPLETED", "ABANDONED"]
                            Button {
                                text: modelData
                                checkable: true
                                checked: root.prSelectedStatus === modelData
                                font.pixelSize: 10
                                font.weight: checked ? Font.DemiBold : Font.Normal
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.checked ? "#ffffff" : "#8b949e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: modelData === "ABANDONED" ? 68 : 54
                                    radius: 4
                                    color: parent.checked ? (modelData === "ACTIVE" ? "#1f6feb" : (modelData === "COMPLETED" ? "#238636" : (modelData === "ABANDONED" ? "#da3633" : "#30363d"))) : (parent.hovered ? "#21262d" : "#161b22")
                                    border.color: parent.checked ? "#58a6ff" : "#30363d"
                                }
                                onClicked: root.filterPrsByStatus(modelData)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Tag filter: Tagged / Untagged
                        Repeater {
                            model: [
                                { key: "ALL", label: "All" },
                                { key: "TAGGED", label: "🏷️ Tagged" },
                                { key: "UNTAGGED", label: "⚠️ Untagged" }
                            ]
                            Button {
                                text: modelData.label
                                checkable: true
                                checked: root.prSelectedTagFilter === modelData.key
                                font.pixelSize: 10
                                font.weight: checked ? Font.DemiBold : Font.Normal
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.checked ? "#ffffff" : "#8b949e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: modelData.key === "ALL" ? 36 : 68
                                    radius: 4
                                    color: parent.checked ? (modelData.key === "TAGGED" ? "#238636" : (modelData.key === "UNTAGGED" ? "#9e6a03" : "#30363d")) : (parent.hovered ? "#21262d" : "#161b22")
                                    border.color: parent.checked ? "#58a6ff" : "#30363d"
                                }
                                onClicked: root.filterPrsByTag(modelData.key)
                            }
                        }
                    }
                }

                // ==========================================
                // Pull Requests List View
                // ==========================================
                ListView {
                    id: prListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.pagedPRsList

                    ScrollBar.vertical: ScrollBar {
                        id: prListVBar
                        policy: ScrollBar.AsNeeded
                        active: true
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: prListVBar.pressed ? "#58a6ff" : (prListVBar.hovered ? "#8b949e" : "#30363d")
                        }
                    }

                    // Empty State
                    Item {
                        anchors.fill: parent
                        visible: root.pagedPRsList.length === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "🔀"
                                font.pixelSize: 32
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: root.prSearchQuery ? "No PRs match your search or filter" : "No pull requests found"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: "#8b949e"
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Button {
                                text: "Clear Filters"
                                visible: root.prSearchQuery !== "" || root.prSelectedRepo !== "ALL" || root.prSelectedStatus !== "ALL" || root.prSelectedTagFilter !== "ALL"
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: 11
                                onClicked: {
                                    root.prSearchQuery = "";
                                    root.prSelectedRepo = "ALL";
                                    root.prSelectedStatus = "ALL";
                                    root.prSelectedTagFilter = "ALL";
                                    root.prCurrentPage = 1;
                                }
                            }
                        }
                    }

                    // PR Card Delegate
                    delegate: Rectangle {
                        id: prCard
                        width: prListView.width - (prListVBar.visible ? prListVBar.width + 4 : 0)
                        property bool isExpanded: false
                        height: prCardCol.implicitHeight + 16
                        color: prCardHover.containsMouse ? "#1c2128" : "#0d1117"
                        radius: 6
                        border.color: isExpanded ? "#388bfd" : (prCardHover.containsMouse ? "#30363d" : "#21262d")
                        border.width: isExpanded ? 1.5 : 1

                        MouseArea {
                            id: prCardHover
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        ColumnLayout {
                            id: prCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            spacing: 6

                            // Top Meta Row: !ID + Repo + Status + Tag Badge
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // PR ID Pill
                                Rectangle {
                                    implicitHeight: 20
                                    implicitWidth: prIdText.implicitWidth + 10
                                    radius: 3
                                    color: "#161b22"
                                    border.color: "#30363d"

                                    Text {
                                        id: prIdText
                                        anchors.centerIn: parent
                                        text: "!" + modelData.id
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Open PR !" + modelData.id + " in TFS / Web"
                                        onClicked: {
                                            if (modelData.web_url) {
                                                Qt.openUrlExternally(modelData.web_url);
                                            }
                                        }
                                    }
                                }

                                // Repo Pill
                                Rectangle {
                                    implicitHeight: 20
                                    implicitWidth: Math.min(140, repoPillRow.implicitWidth + 10)
                                    radius: 3
                                    color: root.prSelectedRepo === modelData.repo_name ? "#1c2e4a" : "#161b22"
                                    border.color: root.prSelectedRepo === modelData.repo_name ? "#388bfd" : "#30363d"

                                    RowLayout {
                                        id: repoPillRow
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 3

                                        Text { text: "📁"; font.pixelSize: 9 }
                                        Text {
                                            text: modelData.repo_name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: root.prSelectedRepo === modelData.repo_name ? "#79c0ff" : "#c9d1d9"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Filter PRs by " + modelData.repo_name
                                        onClicked: {
                                            root.filterPrsByRepo(modelData.repo_name);
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Status Badge
                                Rectangle {
                                    implicitHeight: 18
                                    implicitWidth: statusText.implicitWidth + 8
                                    radius: 3
                                    color: modelData.status === "completed" ? "#162b20" : (modelData.status === "active" ? "#142233" : (modelData.status === "abandoned" ? "#381113" : "#21262d"))
                                    border.color: modelData.status === "completed" ? "#238636" : (modelData.status === "active" ? "#388bfd" : (modelData.status === "abandoned" ? "#da3633" : "#30363d"))
                                    border.width: 1

                                    Text {
                                        id: statusText
                                        anchors.centerIn: parent
                                        text: (modelData.status || "").toUpperCase()
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: modelData.status === "completed" ? "#3fb950" : (modelData.status === "active" ? "#79c0ff" : (modelData.status === "abandoned" ? "#ff7b72" : "#8b949e"))
                                    }
                                }

                                // Tag Badge
                                Rectangle {
                                    implicitHeight: 18
                                    implicitWidth: Math.min(120, tagText.implicitWidth + 8)
                                    radius: 3
                                    color: modelData.is_tagged ? "#162b20" : (modelData.status === "completed" ? "#332200" : "#161b22")
                                    border.color: modelData.is_tagged ? "#238636" : (modelData.status === "completed" ? "#9e6a03" : "#30363d")
                                    border.width: 1

                                    Text {
                                        id: tagText
                                        anchors.centerIn: parent
                                        text: modelData.is_tagged ? ("🏷️ " + modelData.tag_name) : (modelData.status === "completed" ? "⚠️ Untagged" : (modelData.status === "active" ? "⏳ Review" : "—"))
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        font.weight: modelData.is_tagged ? Font.DemiBold : Font.Normal
                                        color: modelData.is_tagged ? "#7ee787" : (modelData.status === "completed" ? "#d29922" : "#8b949e")
                                        elide: Text.ElideRight
                                        width: Math.min(100, implicitWidth)
                                    }
                                }
                            }

                            // Title Row
                            Text {
                                text: modelData.title
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: "#f0f6fc"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            // Branch & Author Meta Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Branch flow
                                Row {
                                    spacing: 4
                                    Text { text: "🌿"; font.pixelSize: 9 }
                                    Text {
                                        text: (modelData.target_branch ? modelData.target_branch.replace("refs/heads/", "") : "main") +
                                              " ‹-- " +
                                              (modelData.source_branch ? modelData.source_branch.replace("refs/heads/", "") : "branch")
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                        elide: Text.ElideMiddle
                                        width: Math.min(220, implicitWidth)
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Author & Time
                                Row {
                                    spacing: 4
                                    Text { text: "👤"; font.pixelSize: 9 }
                                    Text {
                                        text: (modelData.created_by || "Author") + (modelData.timestamp ? " • " + modelData.timestamp.split("T")[0] : "")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                    }
                                }
                            }

                            // Referenced Tasks Row (if any)
                            Flow {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: modelData.tasks && modelData.tasks.length > 0

                                Repeater {
                                    model: modelData.tasks || []
                                    delegate: Rectangle {
                                        height: 18
                                        width: Math.min(180, taskRow.implicitWidth + 8)
                                        radius: 3
                                        color: taskMa.containsMouse ? "#21262d" : "#0d1117"
                                        border.color: modelData.deleted ? "#da3633" : (modelData.type === "Bug" ? "#f85149" : (modelData.type === "User Story" ? "#a371f7" : "#1f6feb"))
                                        border.width: 1

                                        RowLayout {
                                            id: taskRow
                                            anchors.centerIn: parent
                                            spacing: 3

                                            Text {
                                                text: modelData.type === "Bug" ? "🐛" : (modelData.type === "User Story" ? "📖" : "📋")
                                                font.pixelSize: 8
                                            }

                                            Text {
                                                text: "#" + modelData.id
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#58a6ff"
                                            }

                                            Text {
                                                text: modelData.title
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                color: "#c9d1d9"
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: 100
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
                                        ToolTip.delay: 200
                                        ToolTip.text: (modelData.type || "Work Item") + " #" + modelData.id + "\n" + modelData.title + "\nState: " + modelData.state
                                    }
                                }
                            }

                            // Expandable Actions & Links
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: prCardHover.containsMouse || prCard.isExpanded

                                Button {
                                    text: "Open in TFS ↗"
                                    font.pixelSize: 10
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: 85
                                        radius: 3
                                        color: parent.hovered ? "#1f6feb" : "#16243b"
                                        border.color: "#388bfd"
                                    }
                                    onClicked: {
                                        if (modelData.web_url) {
                                            Qt.openUrlExternally(modelData.web_url);
                                        }
                                    }
                                }

                                Button {
                                    text: "📋 Copy Link"
                                    font.pixelSize: 10
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#c9d1d9"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: 80
                                        radius: 3
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend && modelData.web_url) {
                                            backend.copyToClipboard(modelData.web_url);
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // ==========================================
                // Sidebar Pagination Footer
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    color: "#0d1117"
                    radius: 6
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: "Page " + root.prCurrentPage + " of " + root.prTotalPages + " (" + root.prTotalMatchingCount + " PRs)"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: "‹"
                            enabled: root.prCurrentPage > 1
                            font.pixelSize: 13
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: parent.enabled ? "#f0f6fc" : "#484f58"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 24
                                implicitWidth: 26
                                radius: 3
                                color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (root.prCurrentPage > 1) {
                                    root.prCurrentPage--;
                                }
                            }
                        }

                        Button {
                            text: "›"
                            enabled: root.prCurrentPage < root.prTotalPages
                            font.pixelSize: 13
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: parent.enabled ? "#f0f6fc" : "#484f58"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 24
                                implicitWidth: 26
                                radius: 3
                                color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (root.prCurrentPage < root.prTotalPages) {
                                    root.prCurrentPage++;
                                }
                            }
                        }
                    }
                }

                // ==========================================
                // TAB 1 CONTENT: UNMERGED BRANCHES VIEW
                // ==========================================
                ColumnLayout {
                    id: branchesContentLayout
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.sidebarTab === 1
                    spacing: 12

                    // Unmerged Branches Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "🌿"
                            font.pixelSize: 18
                        }

                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: "Unmerged Branches"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Text {
                                text: {
                                    var prefix = (root.branchSelectedRepo !== "ALL") ? ("📁 " + root.branchSelectedRepo) : "All Repositories";
                                    return prefix + " (" + root.branchTotalMatchingCount + " of " + root.totalBranchesCount + ")";
                                }
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: root.branchSelectedRepo !== "ALL" ? "#bc8cff" : "#8b949e"
                                elide: Text.ElideRight
                                Layout.maximumWidth: root.prSidebarWidth - 180
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Reset repo filter chip if a repo is currently selected
                        Rectangle {
                            visible: root.branchSelectedRepo !== "ALL"
                            implicitHeight: 24
                            implicitWidth: clearBranchRepoText.implicitWidth + 14
                            radius: 4
                            color: clearBranchRepoMa.containsMouse ? "#30363d" : "#21262d"
                            border.color: "#8957e5"

                            Text {
                                id: clearBranchRepoText
                                anchors.centerIn: parent
                                text: "✕ All Repos"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: "#bc8cff"
                            }

                            MouseArea {
                                id: clearBranchRepoMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                ToolTip.visible: containsMouse
                                ToolTip.text: "Clear repository filter to show branches from all repositories"
                                onClicked: {
                                    root.branchSelectedRepo = "ALL";
                                }
                            }
                        }
                    }

                    // Search and Filters for Branches
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Search bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 30
                                color: "#0d1117"
                                radius: 6
                                border.color: branchSearchInput.activeFocus ? "#bc8cff" : "#30363d"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        text: "🔍"
                                        font.pixelSize: 11
                                    }

                                    TextInput {
                                        id: branchSearchInput
                                        Layout.fillWidth: true
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        color: "#f0f6fc"
                                        selectByMouse: true
                                        clip: true
                                        text: root.branchSearchQuery
                                        onTextChanged: {
                                            root.branchSearchQuery = text;
                                        }

                                        Text {
                                            anchors.fill: parent
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Filter branch, author, commit, PR..."
                                            font: parent.font
                                            color: "#484f58"
                                            visible: !parent.text && !parent.activeFocus
                                        }
                                    }

                                    Text {
                                        visible: !!branchSearchInput.text
                                        text: "✕"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: branchSearchInput.text = ""
                                        }
                                    }
                                }
                            }

                            // Repository Filter Dropdown
                            ComboBox {
                                id: branchRepoCombo
                                implicitHeight: 30
                                implicitWidth: 140
                                model: root.branchRepoFilteredList
                                currentIndex: {
                                    var idx = root.branchRepoFilteredList.indexOf(root.branchSelectedRepo);
                                    return idx >= 0 ? idx : 0;
                                }
                                onActivated: function(index) {
                                    root.branchSelectedRepo = root.branchRepoFilteredList[index];
                                }
                                font.pixelSize: 11
                                contentItem: Text {
                                    text: parent.displayText
                                    font: parent.font
                                    color: "#f0f6fc"
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    leftPadding: 8
                                }
                                background: Rectangle {
                                    color: "#0d1117"
                                    radius: 6
                                    border.color: "#30363d"
                                }
                            }
                        }

                        // Sorting Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "Sort:"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }

                            ComboBox {
                                id: branchSortCombo
                                Layout.fillWidth: true
                                implicitHeight: 26
                                model: ["Ahead: High to Low", "Commit Date: Newest First", "Branch Name: A-Z", "Repo Name: A-Z"]
                                currentIndex: root.branchSortMode
                                onActivated: function(index) {
                                    root.branchSortMode = index;
                                }
                                font.pixelSize: 10
                                contentItem: Text {
                                    text: parent.displayText
                                    font: parent.font
                                    color: "#c9d1d9"
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    leftPadding: 6
                                }
                                background: Rectangle {
                                    color: "#0d1117"
                                    radius: 4
                                    border.color: "#30363d"
                                }
                            }
                        }
                    }

                    // Unmerged Branches ListView
                    ListView {
                        id: branchListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.pagedBranchesList

                        ScrollBar.vertical: ScrollBar {
                            id: branchListVBar
                            policy: ScrollBar.AsNeeded
                            active: true
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: branchListVBar.pressed ? "#bc8cff" : (branchListVBar.hovered ? "#8b949e" : "#30363d")
                            }
                        }

                        // Empty State
                        Item {
                            anchors.fill: parent
                            visible: root.pagedBranchesList.length === 0

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: "🌿"
                                    font.pixelSize: 32
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    text: root.branchSearchQuery ? "No branches match your search or filter" : "No unmerged branches found"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    text: "All repositories are in sync with main/master"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#484f58"
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: !root.branchSearchQuery
                                }
                            }
                        }

                        // Branch Card Delegate
                        delegate: Rectangle {
                            id: brCardRoot
                            width: branchListView.width - (branchListVBar.visible ? 10 : 0)
                            implicitHeight: brCardLayout.implicitHeight + 16
                            color: brCardMa.containsMouse ? "#161b22" : "#0d1117"
                            radius: 6
                            border.color: brCardMa.containsMouse ? "#8957e5" : "#30363d"
                            border.width: 1

                            MouseArea {
                                id: brCardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.ArrowCursor
                            }

                            ColumnLayout {
                                id: brCardLayout
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                // Row 1: Branch Name + Badges
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: "🌿"
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        text: modelData.branch_name || ""
                                        font.family: "Consolas, Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: modelData.is_abandoned ? "#8b949e" : "#f0f6fc"
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }

                                    // Ahead Badge
                                    Rectangle {
                                        height: 18
                                        radius: 3
                                        color: "#281b0f"
                                        border.color: "#d29922"
                                        border.width: 1
                                        implicitWidth: aheadTxt.implicitWidth + 8

                                        Text {
                                            id: aheadTxt
                                            anchors.centerIn: parent
                                            text: "+" + (modelData.ahead || 0) + " ahead"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: "#f0883e"
                                        }
                                    }

                                    // Behind Badge
                                    Rectangle {
                                        visible: (modelData.behind || 0) > 0
                                        height: 18
                                        radius: 3
                                        color: "#21262d"
                                        border.color: "#6e7681"
                                        border.width: 1
                                        implicitWidth: behindTxt.implicitWidth + 8

                                        Text {
                                            id: behindTxt
                                            anchors.centerIn: parent
                                            text: "-" + (modelData.behind || 0) + " behind"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    // Abandoned Badge
                                    Rectangle {
                                        visible: !!modelData.is_abandoned
                                        height: 18
                                        radius: 3
                                        color: "#381113"
                                        border.color: "#da3633"
                                        border.width: 1
                                        implicitWidth: abTxt.implicitWidth + 8

                                        Text {
                                            id: abTxt
                                            anchors.centerIn: parent
                                            text: "ABANDONED"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: "#f85149"
                                        }
                                    }
                                }

                                // Row 2: Repo Chip, Author, Date, Short Hash
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Repo Chip
                                    Rectangle {
                                        height: 18
                                        radius: 3
                                        color: brRepoMa.containsMouse ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                        implicitWidth: brRepoTxt.implicitWidth + 8

                                        Text {
                                            id: brRepoTxt
                                            anchors.centerIn: parent
                                            text: "📁 " + (modelData.repo_name || "")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: "#58a6ff"
                                        }

                                        MouseArea {
                                            id: brRepoMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.text: "Filter to repository " + modelData.repo_name
                                            onClicked: {
                                                root.branchSelectedRepo = modelData.repo_name;
                                            }
                                        }
                                    }

                                    // Committer Author
                                    Text {
                                        visible: !!modelData.committer
                                        text: "👤 " + modelData.committer
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#c9d1d9"
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 130
                                    }

                                    // Commit Date
                                    Text {
                                        visible: !!modelData.commit_date
                                        text: "📅 " + (modelData.commit_date ? modelData.commit_date.substring(0, 10) : "")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Short Hash
                                    Text {
                                        visible: !!modelData.short_hash
                                        text: "#" + modelData.short_hash
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                    }
                                }

                                // Row 3: Prepared PR (if available)
                                Rectangle {
                                    visible: !!modelData.prepared_pr_id
                                    Layout.fillWidth: true
                                    height: 22
                                    radius: 3
                                    color: prepPrMa.containsMouse ? "#1c3554" : "#142233"
                                    border.color: "#388bfd"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        Text {
                                            text: "🔀 Prepared PR #" + modelData.prepared_pr_id + ": " + (modelData.prepared_pr_title || "")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: "#79c0ff"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: (modelData.prepared_pr_status || "").toUpperCase()
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: modelData.prepared_pr_status === "active" ? "#79c0ff" : "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: prepPrMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "View Pull Request #" + modelData.prepared_pr_id + " in PR tab"
                                        onClicked: {
                                            root.openPrSidebar(modelData.repo_name, false);
                                            root.prSearchQuery = modelData.prepared_pr_id;
                                        }
                                    }
                                }

                                // Row 4: Commit Message Comment
                                Text {
                                    visible: !!modelData.comment
                                    text: "💬 " + (modelData.comment ? modelData.comment.replace(/\r?\n/g, " ") : "")
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.italic: true
                                    color: "#8b949e"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                // Row 5: Action Buttons (Open in TFS, Copy Branch Name)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Button {
                                        text: "↗ Open in TFS"
                                        font.pixelSize: 10
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: "#58a6ff"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 22
                                            implicitWidth: 85
                                            radius: 3
                                            color: parent.hovered ? "#1f6feb" : "#16243b"
                                            border.color: "#388bfd"
                                        }
                                        onClicked: {
                                            var url = modelData.branch_url || modelData.repo_url;
                                            if (url) {
                                                Qt.openUrlExternally(url);
                                            }
                                        }
                                    }

                                    Button {
                                        text: "📋 Copy Name"
                                        font.pixelSize: 10
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: "#c9d1d9"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 22
                                            implicitWidth: 85
                                            radius: 3
                                            color: parent.hovered ? "#30363d" : "#21262d"
                                            border.color: "#30363d"
                                        }
                                        onClicked: {
                                            if (backend && modelData.branch_name) {
                                                backend.copyToClipboard(modelData.branch_name);
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }

                    // Unmerged Branches Pagination Footer
                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        color: "#0d1117"
                        radius: 6
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Page " + root.branchCurrentPage + " of " + root.branchTotalPages + " (" + root.branchTotalMatchingCount + " branches)"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }

                            Item { Layout.fillWidth: true }

                            Button {
                                text: "‹"
                                enabled: root.branchCurrentPage > 1
                                font.pixelSize: 13
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#f0f6fc" : "#484f58"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: 26
                                    radius: 3
                                    color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                    border.color: "#30363d"
                                }
                                onClicked: {
                                    if (root.branchCurrentPage > 1) {
                                        root.branchCurrentPage--;
                                    }
                                }
                            }

                            Button {
                                text: "›"
                                enabled: root.branchCurrentPage < root.branchTotalPages
                                font.pixelSize: 13
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.enabled ? "#f0f6fc" : "#484f58"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: 26
                                    radius: 3
                                    color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                                    border.color: "#30363d"
                                }
                                onClicked: {
                                    if (root.branchCurrentPage < root.branchTotalPages) {
                                        root.branchCurrentPage++;
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

    // ==========================================
    // Repositories Filtering Logic
    // ==========================================
    function updateFilteredModel() {
        root.validateSelectedCategory();
        filteredRepos.clear();
        if (!backend || !backend.repositories)
            return;
        var list = backend.repositories || [];
        var q = (root.searchQuery || "").toLowerCase();
        var cat = root.selectedCategory;

        var matched = [];
        for (var i = 0; i < list.length; i++) {
            var item = list[i];
            var isItemDeleted = !!item.is_deleted || (item.category && item.category.toUpperCase() === "DELETED");

            // By default, don't show deleted repos unless explicitly viewing DELETED category or showDeleted is checked
            if (isItemDeleted && cat !== "DELETED" && !root.showDeleted) {
                continue;
            }

            var matchesQuery = !q || item.name.toLowerCase().indexOf(q) !== -1;
            var matchesCategory = false;
            if (cat === "ALL") {
                matchesCategory = true;
            } else if (cat === "DELETED") {
                matchesCategory = isItemDeleted;
            } else if (cat === "🏷️ PENDING PRs" || cat === "PENDING_PRS") {
                matchesCategory = !isItemDeleted && (!!item.has_untagged_prs || (item.prs_after_tag_count > 0));
            } else if (cat === "🌿 UNMERGED BRANCHES" || cat === "UNMERGED_BRANCHES") {
                matchesCategory = !isItemDeleted && (!!item.has_unmerged_branches || (item.unmerged_branches_count > 0));
            } else if (cat === "⚠️ PENDING" || cat === "PENDING") {
                matchesCategory = !isItemDeleted && !!item.has_pending_changes;
            } else {
                matchesCategory = (item.category === cat);
            }

            if (matchesQuery && matchesCategory) {
                matched.push(item);
            }
        }

        root.totalMatchingCount = matched.length;
        root.totalPages = Math.ceil(matched.length / root.pageSize) || 1;
        if (root.currentPage > root.totalPages) {
            root.currentPage = root.totalPages;
        }
        if (root.currentPage < 1) {
            root.currentPage = 1;
        }

        var startIdx = (root.currentPage - 1) * root.pageSize;
        var endIdx = Math.min(startIdx + root.pageSize, matched.length);

        for (var j = startIdx; j < endIdx; j++) {
            filteredRepos.append(matched[j]);
        }
    }

    Connections {
        target: backend
        function onRepositoriesChanged() {
            root.validateSelectedCategory();
            root.updateFilteredModel();
        }
        function onRepoCategoriesChanged() {
            root.updateFilteredModel();
        }
        function onPullRequestsChanged() {
            root.updateFilteredPrs();
        }
        function onPrRepositoriesChanged() {
            root.updateFilteredPrs();
        }
        function onTagDayDataChanged() {
            root.updateFilteredBranches();
        }
        function onRightSidebarWidthChanged(w) {
            root.prSidebarWidth = Math.max(root.minPrSidebarWidth, Math.min(root.maxPrSidebarWidth, w));
        }
    }

    onSearchQueryChanged: {
        root.currentPage = 1;
        root.updateFilteredModel();
    }
    onSelectedCategoryChanged: {
        root.currentPage = 1;
        root.updateFilteredModel();
    }
    Component.onCompleted: {
        root.updateFilteredModel();
        root.updateFilteredPrs();
        root.updateFilteredBranches();
    }

    RepoCategoriesDialog {
        id: repoCategoriesDialog
    }
}
