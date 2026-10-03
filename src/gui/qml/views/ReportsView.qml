import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"
import "reports"

Item {
    id: root
    property int activeReportTab: 0 // 0: Overview & Triggers, 1: Tag Day Interactive, 2: Storage & Artifacts Interactive, 3: Release Notes, 4: Sprint Report, 5: Iteration Shifts
    property string selectedRepoName: ""
    property string selectedSprintReport: ""
    property var sprintReportData: null
    property int sprintFilterType: 0 // 0: All, 1: Stories, 2: Bugs, 3: Tasks, 4: Assignees
    property string shiftSearchQuery: ""
    property string shiftSourceFilter: "all" // "all", "user_gui", "tfs_sync"
    property string shiftReviewFilter: "all" // "all", "pending", "accepted"
    property bool shiftSprintOnlyFilter: false
    property string tdRepoFilter: "all" // "all", "prs", "branches"
    property bool isTdSidebarOpen: true
    property real minTdSidebarWidth: 380
    property real maxTdSidebarWidth: Math.max(650, Math.floor(root.width * 0.52))
    property real tdSidebarWidth: (backend && backend.rightSidebarWidth && backend.rightSidebarWidth >= 400) ? Math.max(minTdSidebarWidth, Math.min(maxTdSidebarWidth, backend.rightSidebarWidth)) : Math.max(minTdSidebarWidth, Math.floor(root.width * 0.50))
    property string tdRepoSearchQuery: ""
    property int tdSidebarView: 0 // 0: Selected Repo Inspector, 1: Global Changes Timeline

    // Tagging Modal & Release Proposal State
    property bool tagModalOpen: false
    property string tagModalRepo: ""
    property string tagModalBranch: "dev"
    property string tagModalTagName: ""
    property string tagModalComment: ""
    property string tagModalStatus: ""
    property bool tagModalIsError: false
    property bool tagModalIsSuccess: false
    property var tagModalBranches: ["dev", "main", "develop"]

    Connections {
        target: backend
        function onTagCreated(repoName, tagName, success, message) {
            if (root.tagModalOpen) {
                root.tagModalStatus = message;
                root.tagModalIsError = !success;
                root.tagModalIsSuccess = success;
            }
        }
    }

    function openTaggingModal(repoName, branchName) {
        var rName = repoName;
        if (!rName) {
            if (root.selectedRepo)
                rName = root.selectedRepo.name;
            else if (backend && backend.tagDayData && backend.tagDayData.repos_summary && backend.tagDayData.repos_summary.length > 0)
                rName = backend.tagDayData.repos_summary[0].name;
            else
                rName = "";
        }
        root.tagModalRepo = rName;
        root.tagModalBranch = branchName || "dev";
        root.tagModalBranches = (backend && rName) ? backend.get_repo_branches(rName) : ["dev", "main", "develop"];
        var propTag = (backend && rName) ? backend.propose_repo_tag(rName, "patch") : "v01.00.2638";
        root.tagModalTagName = propTag;
        root.tagModalComment = "Tag Day release " + propTag + " from branch '" + root.tagModalBranch + "'";
        root.tagModalStatus = "";
        root.tagModalIsError = false;
        root.tagModalIsSuccess = false;
        root.tagModalOpen = true;
    }

    function setTagModalBump(bumpType) {
        if (backend && root.tagModalRepo) {
            var newTag = backend.propose_repo_tag(root.tagModalRepo, bumpType);
            root.tagModalTagName = newTag;
            root.tagModalComment = "Tag Day release " + newTag + " from branch '" + root.tagModalBranch + "'";
        }
    }

    readonly property var selectedRepo: {
        if (!selectedRepoName || !backend || !backend.tagDayData || !backend.tagDayData.repos_summary)
            return null;
        var list = backend.tagDayData.repos_summary;
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === selectedRepoName) {
                return list[i];
            }
        }
        return null;
    }
    property int repoDetailSubTab: 0 // 0: Merged PRs, 1: Unmerged Branches, 2: Active PRs, 3: All PRs

    function openTagDayRepo(repoName, defaultTab) {
        root.activeReportTab = 1;
        root.isTdSidebarOpen = true;
        root.tdSidebarView = 0;
        root.selectedRepoName = repoName;
        if (defaultTab !== undefined) {
            root.repoDetailSubTab = defaultTab;
        } else if (root.tdRepoFilter === "branches") {
            root.repoDetailSubTab = 1;
        } else {
            root.repoDetailSubTab = 0;
        }
    }

    function getDefaultSprint() {
        if (!backend || !backend.availableSprintList || backend.availableSprintList.length === 0)
            return "";
        var cur = backend.currentSprintName || "";
        if (cur && backend.availableSprintList.indexOf(cur) >= 0)
            return cur;
        return backend.availableSprintList[0];
    }

    function openSprintReport(sprintName) {
        if (sprintName) {
            root.selectedSprintReport = sprintName;
        } else if (!root.selectedSprintReport) {
            root.selectedSprintReport = root.getDefaultSprint();
        }
        root.activeReportTab = 4;
        if (backend && root.selectedSprintReport) {
            root.sprintReportData = backend.get_sprint_report_data(root.selectedSprintReport);
        }
    }

    function refreshSprintReport() {
        if (!root.selectedSprintReport) {
            root.selectedSprintReport = root.getDefaultSprint();
        }
        if (backend && root.selectedSprintReport) {
            root.sprintReportData = backend.get_sprint_report_data(root.selectedSprintReport);
        }
    }

    function openStorageReport() {
        root.activeReportTab = 2;
    }

    Component.onCompleted: {
        if (!root.selectedSprintReport) {
            root.selectedSprintReport = root.getDefaultSprint();
        }
    }

    onSelectedSprintReportChanged: {
        if (backend && root.selectedSprintReport) {
            root.sprintReportData = backend.get_sprint_report_data(root.selectedSprintReport);
        }
    }

    onActiveReportTabChanged: {
        root.isTdSidebarOpen = true;
        if (root.activeReportTab === 1) {
            if (!root.selectedRepoName && backend && backend.tagDayData && backend.tagDayData.repos_summary && backend.tagDayData.repos_summary.length > 0) {
                var found = null;
                for (var i = 0; i < backend.tagDayData.repos_summary.length; i++) {
                    if ((backend.tagDayData.repos_summary[i].prs_count || 0) > 0) {
                        found = backend.tagDayData.repos_summary[i];
                        break;
                    }
                }
                root.selectedRepoName = found ? found.name : backend.tagDayData.repos_summary[0].name;
            }
        } else if (root.activeReportTab === 4) {
            root.refreshSprintReport();
        }
    }

    Connections {
        target: backend
        function onWorkItemsChanged() {
            root.refreshSprintReport();
        }
        function onSprintReportGenerated(data, mdText) {
            root.refreshSprintReport();
        }
        function onTagDayDataChanged() {
            if (root.activeReportTab === 1 && !root.selectedRepoName && backend && backend.tagDayData && backend.tagDayData.repos_summary && backend.tagDayData.repos_summary.length > 0) {
                var found = null;
                for (var i = 0; i < backend.tagDayData.repos_summary.length; i++) {
                    if ((backend.tagDayData.repos_summary[i].prs_count || 0) > 0) {
                        found = backend.tagDayData.repos_summary[i];
                        break;
                    }
                }
                root.selectedRepoName = found ? found.name : backend.tagDayData.repos_summary[0].name;
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================
        // LEFT: Main Reports Page Content
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.minimumWidth: Math.floor(root.width * 0.48)
            Layout.fillHeight: true
            color: "transparent"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // Header and Tab Navigation
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Reports & Analytics"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Subtab Switcher
                    Row {
                        spacing: 5
                        Repeater {
                            model: ["📊 Reports Overview", "🏷️ Tag Day Explorer", "📦 Storage & Artifacts", "📝 Release Notes", "🚀 Sprint Report", "⏱️ Iteration Shifts"]
                            Button {
                                text: modelData
                                checkable: true
                                checked: root.activeReportTab === index
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
                                    implicitWidth: 125
                                    radius: 6
                                    color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                                    border.color: parent.checked ? "#388bfd" : "#30363d"
                                }
                                onClicked: {
                                    root.activeReportTab = index;
                                    if (index === 4) {
                                        root.refreshSprintReport();
                                    }
                                }
                            }
                        }
                    }
                }

                // Content Area by Tab
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.activeReportTab

                    // Tab 0: Actions & File Exports
                    ReportsOverviewTab {
                        root: root
                    }

                    // Tab 1: Interactive Tag Day Explorer
                    ReportsTagDayExplorerTab {
                        root: root
                    }

                    // Tab 2: Interactive Storage & Build Artifacts
                    ReportsStorageArtifactsTab {
                        root: root
                    }

                    // Tab 3: Interactive Release Notes & Version Overview
                    ReportsReleaseNotesTab {
                        root: root
                    }

                    // Tab 4: Agile Sprint & Timeframe Explorer
                    ReportsSprintReportTab {
                        root: root
                    }

                    // Tab 5: Iteration Shifts & Impact Analysis
                    ReportsIterationShiftsTab {
                        root: root
                    }
                }
            }
        }

        // ============================================================
        // RIGHT SIDEBAR: Repository Inspector & Global Changes Timeline
        // ============================================================
        ReportsTagDaySidebar {
            root: root
        }
    }

    // =========================================================================
    // MODAL DIALOG: Tag Repository (Create Git Tag)
    // =========================================================================
    ReportsTaggingModal {
        root: root
    }
}
