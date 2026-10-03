import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

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
    property real tdSidebarWidth: (backend && backend.rightSidebarWidth) ? Math.max(380, Math.min(850, backend.rightSidebarWidth)) : 520
    property real minTdSidebarWidth: 360
    property real maxTdSidebarWidth: 850
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
        if (root.activeReportTab === 1) {
            root.isTdSidebarOpen = true;
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

            // ==========================================
            // Tab 0: Actions & File Exports
            // ==========================================
            ScrollView {
                contentWidth: parent.width
                clip: true

                ColumnLayout {
                    width: parent.width - 20
                    spacing: 20

                    // Report 1: Tag Day
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: tagDayCardCol.implicitHeight + 36
                        height: implicitHeight
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: tagDayCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 12

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "🏷️"
                                    font.pixelSize: 22
                                }

                                Text {
                                    text: "Tag Day Release Report"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    height: 22
                                    width: tagBadgeText.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(88 / 255, 166 / 255, 255 / 255, 0.15)
                                    border.color: "#388bfd"
                                    border.width: 1
                                    Text {
                                        id: tagBadgeText
                                        anchors.centerIn: parent
                                        text: "SEMANTIC RELEASES"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                }
                            }

                            // Description
                            Text {
                                text: "Evaluates per-repository changes, unmerged branches, and closed PRs against latest semantic tags. Generates Markdown release notes."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Actions inside the card
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    text: "⚡ Generate Tag Day Report"
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
                                        implicitWidth: 195
                                        radius: 6
                                        color: parent.enabled ? (parent.hovered ? "#388bfd" : "#1f6feb") : "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.generate_tagday_report_async();
                                    }
                                }

                                Button {
                                    text: "📑 Open TAGDAY.md"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#f0f6fc"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 155
                                        radius: 6
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.open_tagday_file();
                                    }
                                }

                                Button {
                                    text: "👁️ Preview in Sidebar"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 160
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "#161b22"
                                        border.color: "#388bfd"
                                    }
                                    onClicked: {
                                        if (typeof window !== "undefined" && typeof window.openRightSidebar === "function" && backend) {
                                            var rep = backend.get_report_content("tagday");
                                            window.openRightSidebar("report_preview", "Tag Day Release Report", "Preview & Markdown Inspector", rep);
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: "Explore Tag Day ➔"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 150
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: root.activeReportTab = 1
                                }
                            }
                        }
                    }

                    // Report 2: Storage & Artifacts
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: storageCardCol.implicitHeight + 36
                        height: implicitHeight
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: storageCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 12

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "📦"
                                    font.pixelSize: 22
                                }

                                Text {
                                    text: "Build Artifact & Storage Analysis"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    height: 22
                                    width: storageBadgeText.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(163 / 255, 113 / 255, 247 / 255, 0.15)
                                    border.color: "#a371f7"
                                    border.width: 1
                                    Text {
                                        id: storageBadgeText
                                        anchors.centerIn: parent
                                        text: "BUILD STORAGE FOOTPRINT"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#a371f7"
                                    }
                                }
                            }

                            // Description
                            Text {
                                text: "Analyzes all builds in Azure DevOps, detects active vs deleted drop folders, tracks GB storage footprint, and exports Wiki Markdown & CSV."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Actions inside the card
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    text: "⚡ Generate Storage Report"
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
                                        implicitWidth: 195
                                        radius: 6
                                        color: parent.enabled ? (parent.hovered ? "#8957e5" : "#6e40c9") : "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.generate_storage_report_async();
                                    }
                                }

                                Button {
                                    text: "📑 Open Report"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#f0f6fc"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 130
                                        radius: 6
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.open_storage_report_file();
                                    }
                                }

                                Button {
                                    text: "👁️ Preview in Sidebar"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#a371f7"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 160
                                        radius: 6
                                        color: parent.hovered ? "#281b3d" : "#161b22"
                                        border.color: "#a371f7"
                                    }
                                    onClicked: {
                                        if (typeof window !== "undefined" && typeof window.openRightSidebar === "function" && backend) {
                                            var rep = backend.get_report_content("storage");
                                            window.openRightSidebar("report_preview", "Storage & Artifacts Report", "Storage Footprint Preview", rep);
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: "Explore Storage ➔"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#a371f7"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 145
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: root.activeReportTab = 2
                                }
                            }
                        }
                    }

                    // Report 3: Release Notes & Version History (REVISION.md)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: revCardCol.implicitHeight + 36
                        height: implicitHeight
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: revCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 12

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "📝"
                                    font.pixelSize: 22
                                }

                                Text {
                                    text: "Release Notes & Version Revision"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    height: 22
                                    width: revBadgeText.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(63 / 255, 185 / 255, 80 / 255, 0.15)
                                    border.color: "#3fb950"
                                    border.width: 1
                                    Text {
                                        id: revBadgeText
                                        anchors.centerIn: parent
                                        text: "MULTI-PACKAGE REVISION"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#3fb950"
                                    }
                                }
                            }

                            // Description
                            Text {
                                text: "Evaluates package release status, semantic tags, and merged PR change logs. Generates multi-package REVISION.md and Word formatted REVISION.docx release tracking documents."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Actions inside the card
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    text: "⚡ Generate Release Notes"
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
                                        implicitWidth: 195
                                        radius: 6
                                        color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.generate_revision_report_async();
                                    }
                                }

                                Button {
                                    text: "📑 Open REVISION.md"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#f0f6fc"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 165
                                        radius: 6
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.open_revision_file();
                                    }
                                }

                                Button {
                                    text: "👁️ Preview in Sidebar"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#3fb950"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 160
                                        radius: 6
                                        color: parent.hovered ? "#1b3823" : "#161b22"
                                        border.color: "#3fb950"
                                    }
                                    onClicked: {
                                        if (typeof window !== "undefined" && typeof window.openRightSidebar === "function" && backend) {
                                            var rep = backend.get_report_content("revision");
                                            window.openRightSidebar("report_preview", "Release Notes & Revision", "REVISION.md Markdown Inspector", rep);
                                        }
                                    }
                                }

                                Button {
                                    text: "📘 DOCX"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 80
                                        radius: 6
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.open_revision_docx();
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: "Explore Release Notes ➔"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#3fb950"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 170
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: root.activeReportTab = 3
                                }
                            }
                        }
                    }

                    // Report 4: Agile Sprint & Timeframe Report
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: sprintCardCol.implicitHeight + 36
                        height: implicitHeight
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: sprintCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 12

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "🚀"
                                    font.pixelSize: 22
                                }

                                Text {
                                    text: "Agile Weekly Sprint & Timeframe Report"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    height: 22
                                    width: sprintBadgeText.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(31 / 255, 111 / 255, 235 / 255, 0.15)
                                    border.color: "#388bfd"
                                    border.width: 1
                                    Text {
                                        id: sprintBadgeText
                                        anchors.centerIn: parent
                                        text: "AGILE VELOCITY & DEADLINES"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                }
                            }

                            // Description
                            Text {
                                text: "Audits User Stories, Requirements, Bugs, and Tasks scheduled for weekly sprint timeframes (week-YYWW). Tracks milestone deadlines, urgency status, team contribution, and exports Wiki Markdown & flat CSV."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Sprint Selector & Actions
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ComboBox {
                                    id: sprintSelectCombo
                                    implicitWidth: 180
                                    implicitHeight: 34
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
                                        border.color: "#30363d"
                                    }
                                    contentItem: Text {
                                        leftPadding: 10
                                        text: sprintSelectCombo.currentText ? ("🎯 " + sprintSelectCombo.currentText) : "Select Sprint..."
                                        font: sprintSelectCombo.font
                                        color: "#58a6ff"
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onActivated: function(index) {
                                        if (backend && backend.availableSprintList && backend.availableSprintList[index]) {
                                            root.selectedSprintReport = backend.availableSprintList[index];
                                        }
                                    }
                                }

                                Button {
                                    text: "⚡ Generate Sprint Report"
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
                                        implicitWidth: 195
                                        radius: 6
                                        color: parent.enabled ? (parent.hovered ? "#388bfd" : "#1f6feb") : "#30363d"
                                    }
                                    onClicked: {
                                        if (backend) {
                                            var targetSprint = sprintSelectCombo.currentText;
                                            backend.generate_sprint_report_async(targetSprint);
                                        }
                                    }
                                }

                                Button {
                                    text: "📑 Open Markdown"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#f0f6fc"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 145
                                        radius: 6
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend) {
                                            var targetSprint = sprintSelectCombo.currentText;
                                            backend.open_sprint_report_file(targetSprint);
                                        }
                                    }
                                }

                                Button {
                                    text: "👁️ Preview in Sidebar"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 160
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "#161b22"
                                        border.color: "#388bfd"
                                    }
                                    onClicked: {
                                        if (typeof window !== "undefined" && typeof window.openRightSidebar === "function" && backend) {
                                            var targetSprint = sprintSelectCombo.currentText;
                                            var rep = backend.get_report_content("sprint", targetSprint);
                                            window.openRightSidebar("report_preview", "Sprint Report: " + targetSprint, "Sprint Velocity & Items Breakdown", rep);
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: "Explore Sprint ➔"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 145
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        root.openSprintReport(sprintSelectCombo.currentText);
                                    }
                                }
                            }
                        }
                    }

                    // Direct Shortcut Banner to Standalone Pull Requests Page
                    Rectangle {
                        Layout.fillWidth: true
                        height: 72
                        color: "#0d1117"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 16

                            Text {
                                text: "🔀"
                                font.pixelSize: 24
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "Looking for Pull Requests?"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Text {
                                    text: "The PR browser has been moved to its own standalone page with full pagination, repository filtering, and chronological sorting."
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    color: "#8b949e"
                                }
                            }

                            Button {
                                text: "Go to Pull Requests ➔"
                                font.pixelSize: 12
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
                                    implicitWidth: 175
                                    radius: 6
                                    color: parent.hovered ? "#388bfd" : "#1f6feb"
                                }
                                onClicked: {
                                    if (typeof window !== "undefined" && window.navigateToPullRequests) {
                                        window.navigateToPullRequests();
                                    } else if (typeof window !== "undefined") {
                                        window.currentTabIndex = 2;
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        height: 10
                    }
                }
            }

            // ==========================================
            // Tab 1: Interactive Tag Day Explorer
            // ==========================================
            ColumnLayout {
                spacing: 14

                // Action Header Card for Tag Day Report
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
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
                            text: "🏷️ Tag Day Release Analysis"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }

                        Text {
                            text: "• Evaluates semantic tags, unmerged branches, and closed PRs"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Button {
                            text: "⚡ Generate Tag Day Report"
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
                                implicitHeight: 32
                                implicitWidth: 195
                                radius: 6
                                color: parent.enabled ? (parent.hovered ? "#388bfd" : "#1f6feb") : "#30363d"
                            }
                            onClicked: {
                                if (backend)
                                    backend.generate_tagday_report_async();
                            }
                        }

                        Button {
                            text: "📑 Open TAGDAY.md"
                            font.pixelSize: 12
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#f0f6fc"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 32
                                implicitWidth: 155
                                radius: 6
                                color: parent.hovered ? "#30363d" : "#21262d"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (backend)
                                    backend.open_tagday_file();
                            }
                        }

                        // Right Sidebar Toggle Button in Header
                        Button {
                            text: root.isTdSidebarOpen ? "Sidebar ◨" : "Sidebar ◧"
                            font.pixelSize: 12
                            ToolTip.visible: hovered
                            ToolTip.text: root.isTdSidebarOpen ? "Collapse right sidebar" : "Open right sidebar"
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: root.isTdSidebarOpen ? "#58a6ff" : "#c9d1d9"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 32
                                implicitWidth: 100
                                radius: 6
                                color: parent.hovered ? "#30363d" : "#21262d"
                                border.color: root.isTdSidebarOpen ? "#388bfd" : "#30363d"
                            }
                            onClicked: root.isTdSidebarOpen = !root.isTdSidebarOpen
                        }
                    }
                }

                // Metrics Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    StatCard {
                        Layout.fillWidth: true
                        title: "Repos Analyzed"
                        value: ((backend && backend.tagDayData && backend.tagDayData.repos_analyzed) ? backend.tagDayData.repos_analyzed : 0).toString()
                        subtitle: "Tracked in Tag Day scope"
                        accentColor: "#58a6ff"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tdRepoFilter = "all"
                        }
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Pending Release Repos"
                        value: ((backend && backend.tagDayData && backend.tagDayData.repos_with_prs_count !== undefined) ? backend.tagDayData.repos_with_prs_count : 0).toString()
                        subtitle: "Untagged merged PRs"
                        accentColor: "#f0883e"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tdRepoFilter = "prs"
                        }
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Unmerged Branch Repos"
                        value: ((backend && backend.tagDayData && backend.tagDayData.repos_with_branches_count !== undefined) ? backend.tagDayData.repos_with_branches_count : 0).toString()
                        subtitle: "Branches ahead of baseline"
                        accentColor: "#bc8cff"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tdRepoFilter = "branches"
                        }
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Untagged Log Entries"
                        value: ((backend && backend.tagDayData && backend.tagDayData.timeline_items_count) ? backend.tagDayData.timeline_items_count : 0).toString()
                        subtitle: "Candidate release items"
                        accentColor: "#3fb950"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.isTdSidebarOpen = true;
                                root.tdSidebarView = 1;
                            }
                        }
                    }
                }

                // Main Content: Primary Repositories List
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

                            // Toolbar: Search Box + Filter Pills + Quick Timeline Switcher
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                // Search Box
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: 360
                                    implicitHeight: 32
                                    radius: 6
                                    color: "#0d1117"
                                    border.color: tdSearchInput.activeFocus ? "#58a6ff" : "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        Text {
                                            text: "🔍"
                                            font.pixelSize: 11
                                            color: "#8b949e"
                                        }

                                        TextInput {
                                            id: tdSearchInput
                                            Layout.fillWidth: true
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            color: "#f0f6fc"
                                            clip: true
                                            text: root.tdRepoSearchQuery
                                            onTextChanged: {
                                                root.tdRepoSearchQuery = text;
                                            }

                                            Text {
                                                anchors.fill: parent
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Filter repositories by name, tag, category..."
                                                font: parent.font
                                                color: "#484f58"
                                                visible: !parent.text && !parent.activeFocus
                                            }
                                        }

                                        Text {
                                            visible: !!tdSearchInput.text
                                            text: "✕"
                                            font.pixelSize: 11
                                            color: "#8b949e"
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: tdSearchInput.text = ""
                                            }
                                        }
                                    }
                                }

                                // Filter Pills: All, Pending PRs, Unmerged Branches, Proposed
                                RowLayout {
                                    spacing: 6

                                    Button {
                                        text: "All (" + ((backend && backend.tagDayData && backend.tagDayData.repos_summary) ? backend.tagDayData.repos_summary.length : 0) + ")"
                                        checkable: true
                                        checked: root.tdRepoFilter === "all"
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
                                            implicitWidth: 70
                                            radius: 5
                                            color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                            border.color: parent.checked ? "#388bfd" : "#30363d"
                                        }
                                        onClicked: root.tdRepoFilter = "all"
                                    }

                                    Button {
                                        readonly property int count: {
                                            if (!backend || !backend.tagDayData || !backend.tagDayData.repos_summary) return 0;
                                            return backend.tagDayData.repos_summary.filter(function(r) { return (r.prs_count || 0) > 0; }).length;
                                        }
                                        text: "🏷️ PRs (" + count + ")"
                                        checkable: true
                                        checked: root.tdRepoFilter === "prs"
                                        font.pixelSize: 11
                                        font.weight: checked ? Font.DemiBold : Font.Normal
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: parent.checked ? "#ffffff" : "#f0883e"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 28
                                            implicitWidth: 84
                                            radius: 5
                                            color: parent.checked ? "#d29922" : (parent.hovered ? "#21262d" : "#0d1117")
                                            border.color: parent.checked ? "#e3b341" : "#6e4b10"
                                        }
                                        onClicked: root.tdRepoFilter = "prs"
                                    }

                                    Button {
                                        readonly property int count: {
                                            if (!backend || !backend.tagDayData || !backend.tagDayData.repos_summary) return 0;
                                            return backend.tagDayData.repos_summary.filter(function(r) { return (r.branches_count || 0) > 0; }).length;
                                        }
                                        text: "🌿 Branches (" + count + ")"
                                        checkable: true
                                        checked: root.tdRepoFilter === "branches"
                                        font.pixelSize: 11
                                        font.weight: checked ? Font.DemiBold : Font.Normal
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: parent.checked ? "#ffffff" : "#bc8cff"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 28
                                            implicitWidth: 104
                                            radius: 5
                                            color: parent.checked ? "#8957e5" : (parent.hovered ? "#21262d" : "#0d1117")
                                            border.color: parent.checked ? "#a371f7" : "#5a3e85"
                                        }
                                        onClicked: root.tdRepoFilter = "branches"
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Open Changes Timeline in Sidebar Button
                                Button {
                                    text: "⏱️ Changes Timeline"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: (root.isTdSidebarOpen && root.tdSidebarView === 1) ? "#ffffff" : "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: 140
                                        radius: 5
                                        color: (root.isTdSidebarOpen && root.tdSidebarView === 1) ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                        border.color: (root.isTdSidebarOpen && root.tdSidebarView === 1) ? "#388bfd" : "#30363d"
                                    }
                                    onClicked: {
                                        root.isTdSidebarOpen = true;
                                        root.tdSidebarView = 1;
                                    }
                                }
                            }

                            // Repositories List
                            ListView {
                                id: tdReposList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 6
                                boundsBehavior: Flickable.StopAtBounds
                                model: {
                                    if (!backend || !backend.tagDayData || !backend.tagDayData.repos_summary) return [];
                                    var list = backend.tagDayData.repos_summary;
                                    if (root.tdRepoFilter === "prs") {
                                        list = list.filter(function(r) { return (r.prs_count || 0) > 0; });
                                    } else if (root.tdRepoFilter === "branches") {
                                        list = list.filter(function(r) { return (r.branches_count || 0) > 0; });
                                    }
                                    var q = (root.tdRepoSearchQuery || "").trim().toLowerCase();
                                    if (q) {
                                        list = list.filter(function(r) {
                                            var n = (r.name || "").toLowerCase();
                                            var c = (r.category || "").toLowerCase();
                                            var b = (r.default_branch || "").toLowerCase();
                                            var t = (r.latest_tag || "").toLowerCase();
                                            var pt = (r.proposed_tag || "").toLowerCase();
                                            return n.indexOf(q) >= 0 || c.indexOf(q) >= 0 || b.indexOf(q) >= 0 || t.indexOf(q) >= 0 || pt.indexOf(q) >= 0;
                                        });
                                    }
                                    return list;
                                }

                                ScrollBar.vertical: ScrollBar {
                                    active: true
                                    policy: ScrollBar.AsNeeded
                                }

                                // Empty State
                                Item {
                                    anchors.fill: parent
                                    visible: tdReposList.count === 0

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Text {
                                            text: "📦"
                                            font.pixelSize: 32
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: root.tdRepoSearchQuery ? "No repositories match your filter" : "No repositories with changes found"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            color: "#8b949e"
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: "All repositories are tagged and up to date."
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#484f58"
                                            Layout.alignment: Qt.AlignHCenter
                                            visible: !root.tdRepoSearchQuery
                                        }
                                    }
                                }

                                delegate: Rectangle {
                                    id: repoCard
                                    width: tdReposList.width - 8
                                    height: 58
                                    radius: 6
                                    readonly property bool isSelected: root.selectedRepoName === modelData.name
                                    color: isSelected ? "#1f293d" : (cardMouse.containsMouse ? "#21262d" : "#0d1117")
                                    border.color: isSelected ? "#388bfd" : (cardMouse.containsMouse ? "#3b434d" : "#30363d")
                                    border.width: isSelected ? 2 : 1

                                    // Left accent bar when selected
                                    Rectangle {
                                        width: 4
                                        height: parent.height - 10
                                        anchors.left: parent.left
                                        anchors.leftMargin: 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        radius: 2
                                        color: "#58a6ff"
                                        visible: repoCard.isSelected
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: repoCard.isSelected ? 14 : 12
                                        anchors.rightMargin: 12
                                        anchors.topMargin: 7
                                        anchors.bottomMargin: 7
                                        spacing: 4

                                        // Line 1: Repo Name, Category Chip, Branch Pill, Spacer, Status Badges
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: "📦"
                                                font.pixelSize: 11
                                            }

                                            Text {
                                                text: modelData.name || ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: repoCard.isSelected ? Font.Bold : Font.DemiBold
                                                color: repoCard.isSelected ? "#58a6ff" : "#f0f6fc"
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: 220
                                            }

                                            // Category Chip
                                            Rectangle {
                                                implicitHeight: 16
                                                implicitWidth: catTxt.implicitWidth + 8
                                                radius: 3
                                                color: (backend && modelData.category) ? backend.get_category_color(modelData.category) : "#8957e5"
                                                opacity: 0.85

                                                Text {
                                                    id: catTxt
                                                    anchors.centerIn: parent
                                                    text: modelData.category || "OTHERS"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#ffffff"
                                                }
                                            }

                                            // Default Branch Pill
                                            Rectangle {
                                                implicitHeight: 16
                                                implicitWidth: brPillTxt.implicitWidth + 8
                                                radius: 3
                                                color: "#21262d"
                                                border.color: "#30363d"

                                                Row {
                                                    id: brPillTxt
                                                    anchors.centerIn: parent
                                                    spacing: 3
                                                    Text {
                                                        text: "🌿"
                                                        font.pixelSize: 8
                                                    }
                                                    Text {
                                                        text: modelData.default_branch || "main"
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 9
                                                        color: "#8b949e"
                                                    }
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Status Badges (PRs, Branches, Active) on right side of Line 1
                                            RowLayout {
                                                spacing: 4
                                                Layout.alignment: Qt.AlignVCenter

                                                StatusBadge {
                                                    visible: (modelData.prs_count || 0) > 0
                                                    text: modelData.prs_count + " PR" + (modelData.prs_count > 1 ? "s" : "")
                                                    badgeColor: "#d29922"
                                                }

                                                StatusBadge {
                                                    visible: (modelData.branches_count || 0) > 0
                                                    text: modelData.branches_count + " branch" + (modelData.branches_count > 1 ? "es" : "")
                                                    badgeColor: "#8957e5"
                                                }

                                                StatusBadge {
                                                    visible: (modelData.active_prs_count || 0) > 0
                                                    text: modelData.active_prs_count + " active"
                                                    badgeColor: "#1f6feb"
                                                }
                                            }
                                        }

                                        // Line 2: Version badges rendered below repo name + Baseline Commit Subtitle
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            // Latest Tag Badge
                                            Rectangle {
                                                implicitHeight: 18
                                                implicitWidth: latestTagTxt.implicitWidth + 10
                                                radius: 3
                                                color: (modelData.latest_tag && modelData.latest_tag !== "-") ? "#12261a" : "#161b22"
                                                border.color: (modelData.latest_tag && modelData.latest_tag !== "-") ? "#238636" : "#30363d"

                                                Text {
                                                    id: latestTagTxt
                                                    anchors.centerIn: parent
                                                    text: (modelData.latest_tag && modelData.latest_tag !== "-") ? ("🏷️ " + modelData.latest_tag) : "No Tag"
                                                    font.family: "Consolas, monospace"
                                                    font.pixelSize: 10
                                                    color: (modelData.latest_tag && modelData.latest_tag !== "-") ? "#3fb950" : "#8b949e"
                                                }
                                            }

                                            // Proposed Tag Arrow & Badge (below repo name)
                                            RowLayout {
                                                spacing: 4
                                                visible: !!modelData.proposed_tag

                                                Text {
                                                    text: "➔"
                                                    font.pixelSize: 9
                                                    color: "#58a6ff"
                                                }

                                                Rectangle {
                                                    implicitHeight: 18
                                                    implicitWidth: propTagTxt.implicitWidth + 10
                                                    radius: 3
                                                    color: "#0d1f33"
                                                    border.color: "#1f6feb"

                                                    Text {
                                                        id: propTagTxt
                                                        anchors.centerIn: parent
                                                        text: "🚀 " + (modelData.proposed_tag || "")
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: "#58a6ff"
                                                    }
                                                }
                                            }

                                            Text {
                                                text: "•"
                                                font.pixelSize: 9
                                                color: "#30363d"
                                            }

                                            // Baseline / Commit Subtitle
                                            Text {
                                                text: {
                                                    if (modelData.latest_tag_details && modelData.latest_tag_details.commit_date) {
                                                        return "Latest commit: " + modelData.latest_tag_details.commit_date + (modelData.latest_tag_details.committer ? " by " + modelData.latest_tag_details.committer : "");
                                                    }
                                                    return "Baseline evaluated since inception";
                                                }
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#6e7681"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: cardMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedRepoName = modelData.name;
                                            root.tdSidebarView = 0;
                                            root.isTdSidebarOpen = true;
                                            if (root.tdRepoFilter === "branches") {
                                                root.repoDetailSubTab = 1; // Unmerged Branches
                                            } else if (root.tdRepoFilter === "prs") {
                                                root.repoDetailSubTab = 0; // Merged PRs
                                            } else {
                                                if ((modelData.prs_count || 0) === 0 && (modelData.branches_count || 0) > 0) {
                                                    root.repoDetailSubTab = 1;
                                                } else {
                                                    root.repoDetailSubTab = 0;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ============================================================
            }

            // ==========================================
            // Tab 2: Interactive Storage & Build Artifacts
            // ==========================================
            ColumnLayout {
                spacing: 16

                // Action Header Card for Storage Report
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
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
                            text: "📦 Build Artifact & Storage Analysis"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }

                        Text {
                            text: "• Analyzes drop folder sizes, active vs reclaimed GB footprint, and CSV/Wiki exports"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Button {
                            text: "⚡ Generate Storage Report"
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
                                implicitHeight: 32
                                implicitWidth: 195
                                radius: 6
                                color: parent.enabled ? (parent.hovered ? "#8957e5" : "#6e40c9") : "#30363d"
                            }
                            onClicked: {
                                if (backend)
                                    backend.generate_storage_report_async();
                            }
                        }

                        Button {
                            text: "📑 Open Report"
                            font.pixelSize: 12
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#f0f6fc"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 32
                                implicitWidth: 125
                                radius: 6
                                color: parent.hovered ? "#30363d" : "#21262d"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (backend)
                                    backend.open_storage_report_file();
                            }
                        }
                    }
                }

                // Storage Metric Cards
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    StatCard {
                        Layout.fillWidth: true
                        title: "Total Builds"
                        value: ((backend && backend.storageData && backend.storageData.total_builds) ? backend.storageData.total_builds : 0).toString()
                        subtitle: "Analyzed in Azure DevOps"
                        accentColor: "#58a6ff"
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Total Storage"
                        value: ((backend && backend.storageData && backend.storageData.total_size_gb) ? backend.storageData.total_size_gb : "0.00") + " GB"
                        subtitle: "Across all builds"
                        accentColor: "#d29922"
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Active Live Storage"
                        value: ((backend && backend.storageData && backend.storageData.active_size_gb) ? backend.storageData.active_size_gb : "0.00") + " GB"
                        subtitle: ((backend && backend.storageData && backend.storageData.active_artifacts_count) ? backend.storageData.active_artifacts_count : 0) + " live drops"
                        accentColor: "#3fb950"
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Reclaimed / Deleted"
                        value: ((backend && backend.storageData && backend.storageData.deleted_size_gb) ? backend.storageData.deleted_size_gb : "0.00") + " GB"
                        subtitle: ((backend && backend.storageData && backend.storageData.deleted_artifacts_count) ? backend.storageData.deleted_artifacts_count : 0) + " deleted drops"
                        accentColor: "#f85149"
                    }
                }

                // Interactive Artifacts Table - Grouped by Repository
                Rectangle {
                    id: artifactsExplorerCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1

                    property string filterText: ""
                    property bool allExpanded: false
                    property int expandCollapseTrigger: 0

                    function expandAll() {
                        allExpanded = true;
                        expandCollapseTrigger++;
                    }

                    function collapseAll() {
                        allExpanded = false;
                        expandCollapseTrigger++;
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // Header with Title, Stats, Search Filter & Expand/Collapse All
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "Published Build Artifacts Explorer"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Rectangle {
                                    color: "#21262d"
                                    radius: 10
                                    border.color: "#30363d"
                                    implicitHeight: 22
                                    implicitWidth: repoCountText.implicitWidth + 14

                                    Text {
                                        id: repoCountText
                                        anchors.centerIn: parent
                                        text: {
                                            var count = (backend && backend.storageData && backend.storageData.artifacts_by_repo) ? backend.storageData.artifacts_by_repo.length : 0;
                                            return count + " Repositories";
                                        }
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#58a6ff"
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            // Filter Field
                            Rectangle {
                                implicitWidth: 220
                                implicitHeight: 28
                                color: "#0d1117"
                                radius: 6
                                border.color: searchInput.activeFocus ? "#58a6ff" : "#30363d"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        text: "🔍"
                                        font.pixelSize: 11
                                        opacity: 0.6
                                    }

                                    TextInput {
                                        id: searchInput
                                        Layout.fillWidth: true
                                        color: "#f0f6fc"
                                        font.pixelSize: 11
                                        clip: true
                                        selectByMouse: true
                                        onTextChanged: artifactsExplorerCard.filterText = text.trim().toLowerCase()

                                        Text {
                                            text: "Filter repositories or artifacts..."
                                            color: "#8b949e"
                                            font.pixelSize: 11
                                            visible: !searchInput.text && !searchInput.activeFocus
                                        }
                                    }

                                    Text {
                                        text: "✕"
                                        color: "#8b949e"
                                        font.pixelSize: 10
                                        visible: searchInput.text.length > 0
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: searchInput.text = ""
                                        }
                                    }
                                }
                            }

                            // Expand All Button
                            Button {
                                text: "📂  Expand All"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#c9d1d9"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    implicitWidth: 95
                                    radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                }
                                onClicked: {
                                    artifactsExplorerCard.expandAll();
                                }
                            }

                            // Collapse All Button
                            Button {
                                text: "📁  Collapse All"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#c9d1d9"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    implicitWidth: 95
                                    radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                }
                                onClicked: {
                                    artifactsExplorerCard.collapseAll();
                                }
                            }
                        }

                        // Grouped Repositories ListView
                        ListView {
                            id: repoGroupList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 8

                            ScrollBar.vertical: ScrollBar {
                                active: true
                                policy: ScrollBar.AsNeeded
                            }

                            model: {
                                var allRepos = (backend && backend.storageData && backend.storageData.artifacts_by_repo) ? backend.storageData.artifacts_by_repo : [];
                                var filter = artifactsExplorerCard.filterText;
                                if (!filter) return allRepos;
                                return allRepos.filter(function(r) {
                                    if (r.repo_name.toLowerCase().indexOf(filter) !== -1) return true;
                                    for (var i = 0; i < r.artifacts.length; i++) {
                                        var a = r.artifacts[i];
                                        if ((a.artifact_name || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.source_branch || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.pipeline_name || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.owner || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.requested_by || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.build_date || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.build_id + "").indexOf(filter) !== -1) {
                                            return true;
                                        }
                                    }
                                    return false;
                                });
                            }

                            // Empty state
                            Item {
                                anchors.centerIn: parent
                                width: 300
                                height: 100
                                visible: repoGroupList.count === 0

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        text: "📦"
                                        font.pixelSize: 28
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: artifactsExplorerCard.filterText ? "No matching repositories or artifacts found" : "No build artifacts recorded in cache"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }

                            delegate: Rectangle {
                                id: repoCard
                                width: repoGroupList.width - 8
                                implicitHeight: repoCol.implicitHeight + 16
                                color: "#0d1117"
                                radius: 6
                                border.color: isHovered ? "#58a6ff44" : "#30363d"
                                border.width: 1

                                property bool isHovered: false
                                property bool isExpanded: artifactsExplorerCard.allExpanded

                                Connections {
                                    target: artifactsExplorerCard
                                    function onExpandCollapseTriggerChanged() {
                                        repoCard.isExpanded = artifactsExplorerCard.allExpanded;
                                    }
                                }

                                ColumnLayout {
                                    id: repoCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    // Repository Group Header
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 38
                                        color: repoCard.isHovered ? "#21262d" : "#161b22"
                                        radius: 4
                                        border.color: "#30363d"
                                        border.width: 1

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: repoCard.isHovered = true
                                            onExited: repoCard.isHovered = false
                                            onClicked: repoCard.isExpanded = !repoCard.isExpanded
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10

                                            Text {
                                                text: repoCard.isExpanded ? "▼" : "▶"
                                                font.pixelSize: 10
                                                color: "#58a6ff"
                                                Layout.preferredWidth: 12
                                            }

                                            Text {
                                                text: "📁"
                                                font.pixelSize: 13
                                            }

                                            Text {
                                                text: modelData.repo_name || "Unknown Repository"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                                Layout.preferredWidth: 200
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                color: "#21262d"
                                                radius: 10
                                                border.color: "#30363d"
                                                implicitHeight: 20
                                                implicitWidth: repoCountLabel.implicitWidth + 12

                                                Text {
                                                    id: repoCountLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.artifacts_count + " artifact" + (modelData.artifacts_count === 1 ? "" : "s") + " (" + modelData.builds_count + " build" + (modelData.builds_count === 1 ? "" : "s") + ")"
                                                    font.pixelSize: 10
                                                    color: "#8b949e"
                                                }
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }

                                            // Count Size Per Group Pill
                                            Rectangle {
                                                color: "#272115"
                                                radius: 12
                                                border.color: "#d2992255"
                                                implicitHeight: 24
                                                implicitWidth: repoSizeLabel.implicitWidth + 16

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    Text {
                                                        text: "Total:"
                                                        font.pixelSize: 10
                                                        color: "#8b949e"
                                                    }

                                                    Text {
                                                        id: repoSizeLabel
                                                        text: modelData.total_size_str || "0.00 MB"
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: "#d29922"
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Sub-Table of Artifacts (when expanded)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: repoCard.isExpanded
                                        spacing: 4

                                        // Sub-table Header
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 26
                                            color: "#161b22"
                                            radius: 3

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                Text {
                                                    text: "BUILD"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 60
                                                }
                                                Text {
                                                    text: "PIPELINE"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 130
                                                }
                                                Text {
                                                    text: "BRANCH"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 100
                                                }
                                                Text {
                                                    text: "ARTIFACT NAME"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: "BUILD DATE"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 110
                                                }
                                                Text {
                                                    text: "OWNER"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 110
                                                }
                                                Text {
                                                    text: "SIZE"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 75
                                                }
                                                Text {
                                                    text: "STATUS"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 65
                                                }
                                            }
                                        }

                                        // Artifact Rows
                                        Repeater {
                                            model: modelData.artifacts || []

                                            delegate: Rectangle {
                                                Layout.fillWidth: true
                                                height: 32
                                                color: artMouse.containsMouse ? "#21262d" : "#161b2288"
                                                radius: 3
                                                border.color: artMouse.containsMouse ? "#30363d" : "transparent"

                                                MouseArea {
                                                    id: artMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: 350
                                                    ToolTip.text: "Build #" + modelData.build_id + (modelData.build_number ? " (" + modelData.build_number + ")" : "") +
                                                                  "\n• Pipeline: " + (modelData.pipeline_name || "Unknown") +
                                                                  "\n• Repository: " + (modelData.repo_name || "Unknown") +
                                                                  "\n• Branch: " + (modelData.source_branch || "-") +
                                                                  "\n• Build Date: " + (modelData.build_date || "-") +
                                                                  "\n• Owner: " + (modelData.owner || "System") +
                                                                  "\n• Artifact: " + (modelData.artifact_name || "drop") +
                                                                  "\n• Size: " + (modelData.size_mb_str || (modelData.size_mb + " MB")) +
                                                                  "\n• Status: " + (modelData.is_deleted ? "Deleted" : "Active")
                                                }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: 8

                                                    Text {
                                                        text: "#" + modelData.build_id
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: "#58a6ff"
                                                        Layout.preferredWidth: 60
                                                    }

                                                    Text {
                                                        text: modelData.pipeline_name || "Unknown Pipeline"
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: "#c9d1d9"
                                                        Layout.preferredWidth: 130
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: (modelData.branch_clean || (modelData.source_branch || "").replace("refs/heads/", ""))
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        color: "#8b949e"
                                                        Layout.preferredWidth: 100
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: modelData.artifact_name || "drop"
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: "#f0f6fc"
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: modelData.build_date || "-"
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        color: "#8b949e"
                                                        Layout.preferredWidth: 110
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: modelData.owner || "System"
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: "#c9d1d9"
                                                        Layout.preferredWidth: 110
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: modelData.size_mb_str || ((modelData.size_mb || 0) + " MB")
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 11
                                                        color: "#d29922"
                                                        Layout.preferredWidth: 75
                                                    }

                                                    StatusBadge {
                                                        text: modelData.is_deleted ? "Deleted" : "Active"
                                                        badgeColor: modelData.is_deleted ? "#da3633" : "#238636"
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

            // ==========================================
            // Tab 3: Interactive Release Notes & Version Overview
            // ==========================================
            ColumnLayout {
                spacing: 16

                // Top Controls & Launchers
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Package Release Milestones & Version Tracking"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                        Text {
                            text: "Tracks stable and unstable semantic version tags across all packages according to REVISION.md."
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "Generate Release Notes"
                        enabled: backend ? !backend.isBusy : false
                        font.weight: Font.DemiBold
                        font.pixelSize: 12
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 160
                            radius: 6
                            color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#30363d"
                        }
                        onClicked: {
                            if (backend)
                                backend.generate_revision_report_async();
                        }
                    }

                    Button {
                        text: "📑 Open REVISION.md"
                        font.pixelSize: 12
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#f0f6fc"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 145
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (backend)
                                backend.open_revision_file();
                        }
                    }

                    Button {
                        text: "📘 DOCX"
                        font.pixelSize: 12
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#58a6ff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 80
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (backend)
                                backend.open_revision_docx();
                        }
                    }
                }

                // Table Container
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

                        // Header
                        Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            color: "#0d1117"
                            border.color: "#21262d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 14

                                Text {
                                    text: "PACKAGE / REPOSITORY"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 220
                                }

                                Text {
                                    text: "CATEGORY"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 140
                                }

                                Text {
                                    text: "STABLE TAG"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 150
                                }

                                Text {
                                    text: "UNSTABLE TAG"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 150
                                }

                                Text {
                                    text: "PENDING RELEASE STATUS"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: "ACTIONS"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 110
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }

                        // Table List
                        ListView {
                            id: releasePackageList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            spacing: 2
                            model: (backend && backend.repositories) ? backend.repositories : []

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                active: true
                            }

                            delegate: Rectangle {
                                width: releasePackageList.width
                                height: 42
                                color: index % 2 === 0 ? "#161b22" : "#1a1f29"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    spacing: 14

                                    Text {
                                        text: modelData.name
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: "#58a6ff"
                                        Layout.preferredWidth: 220
                                        elide: Text.ElideRight
                                    }

                                    StatusBadge {
                                        Layout.preferredWidth: 140
                                        text: modelData.category || "GENERAL"
                                        badgeColor: backend ? backend.get_category_color(modelData.category || "OTHERS") : "#30363d"
                                    }

                                    Text {
                                        text: modelData.stable_tag !== "-" ? ("🛡️ " + modelData.stable_tag) : "–"
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 12
                                        color: modelData.stable_tag !== "-" ? "#3fb950" : "#8b949e"
                                        Layout.preferredWidth: 150
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData.unstable_tag !== "-" ? ("⚡ " + modelData.unstable_tag) : "–"
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 12
                                        color: modelData.unstable_tag !== "-" ? "#79c0ff" : "#8b949e"
                                        Layout.preferredWidth: 150
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData.has_pending_changes ? ("⚠️ " + modelData.pending_status_text) : "✓ Clean / Up to date"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: modelData.has_pending_changes ? "#d29922" : "#3fb950"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Button {
                                        text: "Details 🏷️"
                                        font.pixelSize: 11
                                        Layout.preferredWidth: 110
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: "#58a6ff"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 26
                                            radius: 4
                                            color: parent.hovered ? "#30363d" : "#0d1117"
                                            border.color: "#30363d"
                                        }
                                        onClicked: {
                                            root.openTagDayRepo(modelData.name);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Tab 4: Agile Sprint & Timeframe Explorer
            // ==========================================
            Item {
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

            // ==========================================
            // Tab 5: Iteration Shifts & Impact Analysis
            // ==========================================
            Item {
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
                                    if (backend) backend.generate_rescheduling_report_async(root.shiftReviewFilter);
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
                                    if (backend) backend.generate_rescheduling_report_async(root.shiftReviewFilter);
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
                                    checked: root.shiftReviewFilter === modelData.value
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
                                        root.shiftReviewFilter = modelData.value;
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
                                    checked: root.shiftSourceFilter === modelData.value
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
                                        root.shiftSourceFilter = modelData.value;
                                    }
                                }
                            }
                        }

                        // Scope Toggle: Sprint-to-Sprint Only (ignore Backlog moves)
                        Button {
                            text: root.shiftSprintOnlyFilter ? "🏃 Sprints Only (Active)" : "📋 All Moves"
                            checkable: true
                            checked: root.shiftSprintOnlyFilter
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
                            ToolTip.text: root.shiftSprintOnlyFilter ? "Showing sprint-to-sprint rescheduled items only (initial Backlog scheduling ignored)." : "Click to filter to sprint-to-sprint rescheduled items only."
                            onClicked: {
                                root.shiftSprintOnlyFilter = !root.shiftSprintOnlyFilter;
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Search Filter
                        SearchBar {
                            placeholder: "Search item #, title, sprint..."
                            onSearchUpdated: function(query) {
                                root.shiftSearchQuery = (query || "").toLowerCase();
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
                                        if (root.shiftReviewFilter === "pending") {
                                            list = list.filter(function(it) {
                                                return (it.pending_count || 0) > 0 || it.review_status === "pending";
                                            });
                                        } else if (root.shiftReviewFilter === "accepted") {
                                            list = list.filter(function(it) {
                                                return (it.pending_count || 0) === 0 || it.review_status === "accepted";
                                            });
                                        }

                                        // Search Filter
                                        if (!root.shiftSearchQuery) return list;
                                        return list.filter(function(it) {
                                            var q = root.shiftSearchQuery;
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
                                        if (root.shiftSourceFilter !== "all") {
                                            list = list.filter(function(ev) {
                                                return ev.source === root.shiftSourceFilter;
                                            });
                                        }

                                        // Review Policy Filter
                                        if (root.shiftReviewFilter !== "all") {
                                            list = list.filter(function(ev) {
                                                return (ev.review_status || "pending") === root.shiftReviewFilter;
                                            });
                                        }

                                        // Sprint-to-Sprint Only Filter (ignore initial moves from Backlog/root)
                                        if (root.shiftSprintOnlyFilter) {
                                            list = list.filter(function(ev) {
                                                var os = (ev.old_sprint || ev.old_iteration || "").toLowerCase();
                                                return os !== "" && os !== "none" && os !== "backlog" && os !== "unassigned";
                                            });
                                        }

                                        // Search Query Filter
                                        if (!root.shiftSearchQuery) return list;
                                        return list.filter(function(ev) {
                                            var q = root.shiftSearchQuery;
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
        }
    }
        }

    // ============================================================
    // RIGHT: Tag Day Complete Right Sidebar (Full Page Height)
    // ============================================================
        // RIGHT SIDEBAR: Repository Inspector & Global Changes Timeline
        // ============================================================
        Rectangle {
            id: tdSidebarRect
            Layout.preferredWidth: (root.activeReportTab === 1 && root.isTdSidebarOpen) ? root.tdSidebarWidth : 0
            Layout.fillHeight: true
            visible: root.activeReportTab === 1 && (root.isTdSidebarOpen || Layout.preferredWidth > 0)
            color: "#161b22"
            border.color: "#30363d"
            border.width: 1
            clip: true
            z: 10

            // Resizable Splitter Drag Handle at left edge
            Rectangle {
                id: tdDragHandle
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 6
                color: tdDragMa.containsMouse || tdDragMa.pressed ? Qt.rgba(88 / 255, 166 / 255, 255 / 255, 0.4) : "transparent"
                z: 20

                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    height: 36
                    radius: 1
                    color: tdDragMa.containsMouse || tdDragMa.pressed ? "#58a6ff" : "#30363d"
                }

                property real _startX: 0
                property real _startWidth: 0

                MouseArea {
                    id: tdDragMa
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.SizeHorCursor

                    onPressed: function(mouse) {
                        tdDragHandle._startX = mouse.x;
                        tdDragHandle._startWidth = root.tdSidebarWidth;
                    }

                    onPositionChanged: function(mouse) {
                        if (pressed) {
                            var delta = mouse.x - tdDragHandle._startX;
                            var newW = Math.max(root.minTdSidebarWidth, Math.min(root.maxTdSidebarWidth, tdDragHandle._startWidth - delta));
                            root.tdSidebarWidth = newW;
                        }
                    }

                    onReleased: {
                        if (backend && typeof backend.setRightSidebarWidth === "function") {
                            backend.setRightSidebarWidth(Math.round(root.tdSidebarWidth));
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

                // Top Header Bar: Switch between Selected Repo Inspector & Global Timeline + Close
                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    radius: 6
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        // Tab 0: Selected Repo Inspector
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 4
                            color: root.tdSidebarView === 0 ? "#21262d" : "transparent"
                            border.color: root.tdSidebarView === 0 ? "#388bfd" : "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: "🔍"
                                    font.pixelSize: 11
                                }

                                Text {
                                    text: root.selectedRepo ? root.selectedRepo.name : "Inspector"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: root.tdSidebarView === 0 ? Font.Bold : Font.Normal
                                    color: root.tdSidebarView === 0 ? "#58a6ff" : "#8b949e"
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: root.tdSidebarWidth - 220
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.tdSidebarView = 0
                            }
                        }

                        // Tab 1: Global Changes Timeline
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 4
                            color: root.tdSidebarView === 1 ? "#21262d" : "transparent"
                            border.color: root.tdSidebarView === 1 ? "#388bfd" : "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: "⏱️"
                                    font.pixelSize: 11
                                }

                                Text {
                                    text: "Timeline (" + ((backend && backend.tagDayData && backend.tagDayData.timeline) ? backend.tagDayData.timeline.length : 0) + ")"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: root.tdSidebarView === 1 ? Font.Bold : Font.Normal
                                    color: root.tdSidebarView === 1 ? "#58a6ff" : "#8b949e"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.tdSidebarView = 1
                            }
                        }

                        // Close Sidebar Button
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 4
                            color: closeTdMa.containsMouse ? "#30363d" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 11
                                color: closeTdMa.containsMouse ? "#f0f6fc" : "#8b949e"
                            }

                            MouseArea {
                                id: closeTdMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                ToolTip.visible: containsMouse
                                ToolTip.text: "Close sidebar"
                                onClicked: root.isTdSidebarOpen = false
                            }
                        }
                    }
                }

                // View 1: Global Changes Timeline (visible when tdSidebarView === 1)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    visible: root.tdSidebarView === 1

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Candidate Changes Timeline"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "Click any change to inspect"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                        }
                    }

                    ListView {
                        id: tdTimelineList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        model: (backend && backend.tagDayData && backend.tagDayData.timeline) ? backend.tagDayData.timeline : []

                        ScrollBar.vertical: ScrollBar {
                            active: true
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: Rectangle {
                            id: timelineRow
                            width: tdTimelineList.width - 8
                            height: 48
                            color: itemMouse.containsMouse ? "#1c2128" : "#0d1117"
                            radius: 6
                            border.color: itemMouse.containsMouse ? "#388bfd" : "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: modelData.repo_name
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: itemMouse.containsMouse ? "#58a6ff" : "#8b949e"
                                    Layout.preferredWidth: 110
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.title
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    color: "#f0f6fc"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.date || ""
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 10
                                    color: "#6e7681"
                                }

                                StatusBadge {
                                    text: modelData.status_str || modelData.status
                                    badgeColor: modelData.status === "completed" ? "#238636" : (modelData.status === "active" ? "#1f6feb" : ((modelData.status === "abandoned" || modelData.is_abandoned) ? "#da3633" : "#d29922"))
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.repo_name) {
                                        root.selectedRepoName = modelData.repo_name;
                                        root.tdSidebarView = 0;
                                        root.repoDetailSubTab = 0;
                                    }
                                }
                            }
                        }
                    }
                }

                // View 0: Repository Inspector (visible when tdSidebarView === 0)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.tdSidebarView === 0

                    // Empty State when no repo is selected
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        visible: root.selectedRepo === null

                        Text {
                            text: "🔍"
                            font.pixelSize: 36
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "No Repository Selected"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Click any repository in the list to inspect its merged PRs,\nunmerged branches, and semantic release tags."
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Button {
                            text: "⏱️ Open Changes Timeline"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            Layout.alignment: Qt.AlignHCenter
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 30
                                implicitWidth: 180
                                radius: 5
                                color: parent.hovered ? "#388bfd" : "#1f6feb"
                            }
                            onClicked: root.tdSidebarView = 1
                        }
                    }

                    // Detailed Inspector (visible when selectedRepo !== null)
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10
                        visible: root.selectedRepo !== null

                        // Inspector Header: Title, Category, Branch, Open Web
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: root.selectedRepo ? root.selectedRepo.name : ""
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            StatusBadge {
                                text: root.selectedRepo ? (root.selectedRepo.category || "OTHERS") : ""
                                badgeColor: (backend && root.selectedRepo) ? backend.get_category_color(root.selectedRepo.category || "OTHERS") : "#8957e5"
                            }

                            Rectangle {
                                implicitHeight: 22
                                implicitWidth: defaultBranchTxt.implicitWidth + 12
                                radius: 11
                                color: "#21262d"
                                border.color: "#30363d"
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "🌿"
                                        font.pixelSize: 9
                                    }
                                    Text {
                                        id: defaultBranchTxt
                                        text: (root.selectedRepo && root.selectedRepo.default_branch) ? root.selectedRepo.default_branch : "main"
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                    }
                                }
                            }

                            Button {
                                text: "Web ↗"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#ffffff"
                                }
                                background: Rectangle {
                                    implicitHeight: 26
                                    implicitWidth: 60
                                    radius: 4
                                    color: parent.hovered ? "#388bfd" : "#1f6feb"
                                }
                                onClicked: {
                                    if (root.selectedRepo && root.selectedRepo.web_url) {
                                        if (backend)
                                            backend.open_url(root.selectedRepo.web_url);
                                        else
                                            Qt.openUrlExternally(root.selectedRepo.web_url);
                                    }
                                }
                            }
                        }

                        // Unified Release & Semantic Tag Card
                        Rectangle {
                            id: unifiedTagCard
                            Layout.fillWidth: true
                            implicitHeight: unifiedTagCardRow.implicitHeight + 20
                            height: implicitHeight
                            color: (root.selectedRepo && root.selectedRepo.proposed_tag) ? "#0d1f33" : "#0d1117"
                            radius: 6
                            border.color: (root.selectedRepo && root.selectedRepo.proposed_tag) ? "#1f6feb" : "#30363d"
                            border.width: 1

                            RowLayout {
                                id: unifiedTagCardRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    Layout.alignment: Qt.AlignTop
                                    radius: 6
                                    color: (root.selectedRepo && root.selectedRepo.proposed_tag) ? "#162a45" : "#161b22"
                                    border.color: (root.selectedRepo && root.selectedRepo.proposed_tag) ? "#58a6ff" : ((root.selectedRepo && root.selectedRepo.latest_tag !== "-") ? "#238636" : "#30363d")
                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.selectedRepo && root.selectedRepo.proposed_tag) ? "🚀" : "🏷️"
                                        font.pixelSize: 15
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 5

                                    // Row 1: Tag Indicators & Actions
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "Latest Tag:"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#8b949e"
                                        }
                                        Text {
                                            text: (root.selectedRepo && root.selectedRepo.latest_tag !== "-") ? root.selectedRepo.latest_tag : "No version tag"
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: (root.selectedRepo && root.selectedRepo.latest_tag !== "-") ? "#3fb950" : "#d29922"
                                        }

                                        // Proposed Tag info
                                        RowLayout {
                                            spacing: 6
                                            visible: !!(root.selectedRepo && root.selectedRepo.proposed_tag)

                                            Text {
                                                text: "➔"
                                                font.pixelSize: 11
                                                color: "#58a6ff"
                                            }
                                            Text {
                                                text: (root.selectedRepo && root.selectedRepo.proposed_tag) ? root.selectedRepo.proposed_tag : ""
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: "#58a6ff"
                                            }
                                            Rectangle {
                                                implicitHeight: 18
                                                implicitWidth: 80
                                                radius: 3
                                                color: "#1f6feb"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Weekly <YYWW>"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#ffffff"
                                                }
                                            }
                                        }

                                        // Up to Date status pill
                                        Rectangle {
                                            visible: !(root.selectedRepo && root.selectedRepo.proposed_tag)
                                            implicitHeight: 18
                                            implicitWidth: 74
                                            radius: 3
                                            color: "#13231b"
                                            border.color: "#238636"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "● Up to Date"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#3fb950"
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Tag 'dev' Action Button
                                        Button {
                                            text: (root.selectedRepo && root.selectedRepo.proposed_tag) ? "🏷️ Tag Dev Branch" : "🏷️ Tag 'dev'..."
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            contentItem: Text {
                                                text: parent.text
                                                font: parent.font
                                                color: "#ffffff"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                implicitHeight: 24
                                                implicitWidth: (root.selectedRepo && root.selectedRepo.proposed_tag) ? 120 : 85
                                                radius: 4
                                                color: parent.hovered ? "#2ea043" : "#238636"
                                                border.color: "#3fb950"
                                            }
                                            onClicked: {
                                                if (root.selectedRepo) {
                                                    root.openTaggingModal(root.selectedRepo.name, "dev");
                                                }
                                            }
                                        }
                                    }

                                    // Row 2: Baseline & Commit Information
                                    Text {
                                        text: {
                                            var details = "";
                                            if (!root.selectedRepo || !root.selectedRepo.latest_tag_details || !root.selectedRepo.latest_tag_details.commit_date) {
                                                details = "Baseline: All commits evaluated since inception.";
                                            } else {
                                                var d = root.selectedRepo.latest_tag_details;
                                                details = "Committed on " + d.commit_date + (d.committer ? " by " + d.committer : "");
                                            }
                                            if (root.selectedRepo && root.selectedRepo.proposed_tag) {
                                                var prCount = root.selectedRepo.prs_count || 0;
                                                return details + " • " + prCount + " untagged merged PR" + (prCount === 1 ? "" : "s") + " ready for release.";
                                            }
                                            return details + " • All merged PRs are tagged.";
                                        }
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }

                                    // Row 3: Tag Description / Comment
                                    Rectangle {
                                        visible: !!(root.selectedRepo && root.selectedRepo.latest_tag_details && root.selectedRepo.latest_tag_details.comment)
                                        Layout.fillWidth: true
                                        implicitHeight: commentTxt.implicitHeight + 10
                                        radius: 4
                                        color: "#161b22"
                                        border.color: "#30363d"
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            anchors.topMargin: 4
                                            anchors.bottomMargin: 4
                                            spacing: 6

                                            Text {
                                                text: "💬"
                                                font.pixelSize: 11
                                                Layout.alignment: Qt.AlignTop
                                            }

                                            Text {
                                                id: commentTxt
                                                text: (root.selectedRepo && root.selectedRepo.latest_tag_details) ? root.selectedRepo.latest_tag_details.comment : ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.italic: true
                                                color: "#c9d1d9"
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Sub-tabs for Details (Merged PRs, Active PRs, All PRs, Unmerged Branches)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Button {
                                text: "Merged (" + (root.selectedRepo ? (root.selectedRepo.prs_count || 0) : 0) + ")"
                                checkable: true
                                checked: root.repoDetailSubTab === 0
                                font.pixelSize: 11
                                font.weight: checked ? Font.DemiBold : Font.Normal
                                Layout.fillWidth: true
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.checked ? "#ffffff" : "#8b949e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 26
                                    radius: 4
                                    color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                    border.color: parent.checked ? "#388bfd" : "#30363d"
                                }
                                onClicked: root.repoDetailSubTab = 0
                            }

                            Button {
                                text: "Active (" + (root.selectedRepo ? (root.selectedRepo.active_prs_count || 0) : 0) + ")"
                                checkable: true
                                checked: root.repoDetailSubTab === 2
                                font.pixelSize: 11
                                font.weight: checked ? Font.DemiBold : Font.Normal
                                Layout.fillWidth: true
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.checked ? "#ffffff" : "#8b949e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 26
                                    radius: 4
                                    color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                    border.color: parent.checked ? "#388bfd" : "#30363d"
                                }
                                onClicked: root.repoDetailSubTab = 2
                            }

                            Button {
                                text: "Branches (" + (root.selectedRepo ? (root.selectedRepo.branches_count || 0) : 0) + ")"
                                checkable: true
                                checked: root.repoDetailSubTab === 1
                                font.pixelSize: 11
                                font.weight: checked ? Font.DemiBold : Font.Normal
                                Layout.fillWidth: true
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.checked ? "#ffffff" : "#8b949e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 26
                                    radius: 4
                                    color: parent.checked ? "#8957e5" : (parent.hovered ? "#21262d" : "#0d1117")
                                    border.color: parent.checked ? "#a371f7" : "#30363d"
                                }
                                onClicked: root.repoDetailSubTab = 1
                            }

                            Button {
                                text: "All PRs (" + (root.selectedRepo ? (root.selectedRepo.all_prs_count !== undefined ? root.selectedRepo.all_prs_count : (root.selectedRepo.all_prs ? root.selectedRepo.all_prs.length : 0)) : 0) + ")"
                                checkable: true
                                checked: root.repoDetailSubTab === 3
                                font.pixelSize: 11
                                font.weight: checked ? Font.DemiBold : Font.Normal
                                Layout.fillWidth: true
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.checked ? "#ffffff" : "#8b949e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 26
                                    radius: 4
                                    color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                    border.color: parent.checked ? "#388bfd" : "#30363d"
                                }
                                onClicked: root.repoDetailSubTab = 3
                            }
                        }

                        // StackLayout for Details SubTabs
                        StackLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            currentIndex: root.repoDetailSubTab

                            // SubTab 0: Merged PRs List
                            Item {
                                ListView {
                                    id: repoPrsList
                                    anchors.fill: parent
                                    clip: true
                                    spacing: 6
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: (root.selectedRepo && root.selectedRepo.prs) ? root.selectedRepo.prs : []

                                    ScrollBar.vertical: ScrollBar {
                                        active: true
                                        policy: ScrollBar.AsNeeded
                                    }

                                    delegate: Rectangle {
                                        id: prCard
                                        width: repoPrsList.width - 8
                                        implicitHeight: prMainRow.implicitHeight + 16
                                        height: implicitHeight
                                        color: "#0d1117"
                                        radius: 6
                                        border.color: "#30363d"
                                        border.width: 1

                                        RowLayout {
                                            id: prMainRow
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.margins: 8
                                            spacing: 10

                                            ColumnLayout {
                                                id: prContentCol
                                                Layout.fillWidth: true
                                                spacing: 5

                                                // Header line
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Rectangle {
                                                        implicitHeight: 20
                                                        implicitWidth: prIdText.implicitWidth + 10
                                                        radius: 4
                                                        color: "#161b22"
                                                        border.color: "#30363d"
                                                        Text {
                                                            id: prIdText
                                                            anchors.centerIn: parent
                                                            text: "!" + modelData.pr_id
                                                            font.family: "Consolas, monospace"
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: "#58a6ff"
                                                        }
                                                    }

                                                    Text {
                                                        text: modelData.title
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                        color: "#f0f6fc"
                                                        Layout.fillWidth: true
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }

                                                // Metadata row
                                                RowLayout {
                                                    spacing: 12
                                                    Text {
                                                        text: "👤 " + (modelData.created_by || "Unknown")
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 10
                                                        color: "#6e7681"
                                                    }
                                                    Text {
                                                        text: "📅 Merged: " + (modelData.closed_date || modelData.date || "")
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        color: "#6e7681"
                                                    }
                                                    StatusBadge {
                                                        text: "MERGED"
                                                        badgeColor: "#238636"
                                                    }
                                                }

                                                // Referenced tasks section
                                                ColumnLayout {
                                                    visible: !!(modelData.tasks && modelData.tasks.length > 0)
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    RowLayout {
                                                        spacing: 6
                                                        Text {
                                                            text: "🔗 REFERENCED WORK ITEMS"
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 9
                                                            font.weight: Font.Bold
                                                            color: "#8b949e"
                                                        }
                                                        Rectangle {
                                                            implicitHeight: 14
                                                            implicitWidth: taskCountTxt.implicitWidth + 6
                                                            radius: 7
                                                            color: "#21262d"
                                                            Text {
                                                                id: taskCountTxt
                                                                anchors.centerIn: parent
                                                                text: (modelData.tasks ? modelData.tasks.length : 0)
                                                                font.family: "Segoe UI, sans-serif"
                                                                font.pixelSize: 9
                                                                font.weight: Font.Bold
                                                                color: "#58a6ff"
                                                            }
                                                        }
                                                    }

                                                    Flow {
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        Repeater {
                                                            model: modelData.tasks || []
                                                            delegate: Rectangle {
                                                                implicitHeight: 22
                                                                implicitWidth: taskContentRow.implicitWidth + 10
                                                                radius: 4
                                                                color: taskMouseArea.containsMouse ? "#21262d" : "#161b22"
                                                                border.color: (modelData.type === "Bug") ? "#f85149" : (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#1f6feb" : "#30363d"
                                                                border.width: 1

                                                                RowLayout {
                                                                    id: taskContentRow
                                                                    anchors.centerIn: parent
                                                                    spacing: 4

                                                                    Text {
                                                                        text: (modelData.type === "Bug") ? "🐛" : (modelData.type === "User Story") ? "📖" : (modelData.type === "Feature") ? "⭐" : "📋"
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
                                                                        color: "#e6edf3"
                                                                        Layout.maximumWidth: 180
                                                                        elide: Text.ElideRight
                                                                    }

                                                                    Rectangle {
                                                                        implicitHeight: 14
                                                                        implicitWidth: taskStateTxt.implicitWidth + 6
                                                                        radius: 3
                                                                        color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#1f382b" : (modelData.state === "Active") ? "#192b45" : "#21262d"
                                                                        border.color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#388bfd" : "#484f58"
                                                                        border.width: 1
                                                                        Text {
                                                                            id: taskStateTxt
                                                                            anchors.centerIn: parent
                                                                            text: modelData.state
                                                                            font.family: "Segoe UI, sans-serif"
                                                                            font.pixelSize: 8
                                                                            font.weight: Font.Bold
                                                                            color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#3fb950" : (modelData.state === "Active") ? "#58a6ff" : "#8b949e"
                                                                        }
                                                                    }
                                                                }

                                                                MouseArea {
                                                                    id: taskMouseArea
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: {
                                                                        if (modelData.url) {
                                                                            if (backend)
                                                                                backend.open_url(modelData.url);
                                                                            else
                                                                                Qt.openUrlExternally(modelData.url);
                                                                        }
                                                                    }
                                                                }

                                                                ToolTip.visible: taskMouseArea.containsMouse
                                                                ToolTip.text: modelData.type + " #" + modelData.id + ": " + modelData.title + (modelData.assigned_to ? ("
Assigned to: " + modelData.assigned_to) : "") + "
Status: " + modelData.state + "
Click to open in TFS"
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Open in TFS button
                                            Button {
                                                Layout.alignment: Qt.AlignTop
                                                text: "Open ↗"
                                                font.pixelSize: 10
                                                contentItem: Text {
                                                    text: parent.text
                                                    font: parent.font
                                                    color: "#58a6ff"
                                                }
                                                background: Rectangle {
                                                    implicitHeight: 24
                                                    implicitWidth: 55
                                                    radius: 4
                                                    color: parent.hovered ? "#21262d" : "#161b22"
                                                    border.color: "#30363d"
                                                }
                                                onClicked: {
                                                    var prUrl = root.selectedRepo.web_url + "/pullrequest/" + modelData.pr_id;
                                                    if (backend)
                                                        backend.open_url(prUrl);
                                                    else
                                                        Qt.openUrlExternally(prUrl);
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !repoPrsList.count
                                        text: "No untagged merged pull requests for this repository."
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        color: "#8b949e"
                                    }
                                }
                            }

                            // SubTab 1: Unmerged Branches List
                            Item {
                                ListView {
                                    id: repoBranchesList
                                    anchors.fill: parent
                                    clip: true
                                    spacing: 6
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: (root.selectedRepo && root.selectedRepo.unmerged_branches) ? root.selectedRepo.unmerged_branches : []

                                    ScrollBar.vertical: ScrollBar {
                                        active: true
                                        policy: ScrollBar.AsNeeded
                                    }

                                    delegate: Rectangle {
                                        id: brCard
                                        width: repoBranchesList.width - 8
                                        height: 72
                                        color: "#0d1117"
                                        radius: 6
                                        border.color: modelData.is_abandoned ? "#da3633" : "#30363d"
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 12

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                RowLayout {
                                                    spacing: 8
                                                    Text {
                                                        text: modelData.is_abandoned ? "⛔" : "🌿"
                                                        font.pixelSize: 12
                                                    }

                                                    Text {
                                                        text: modelData.name || modelData.branch_name || ""
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                        color: modelData.is_abandoned ? "#f85149" : "#f0f6fc"
                                                        elide: Text.ElideMiddle
                                                        Layout.maximumWidth: 220
                                                    }

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
                                                            font.pixelSize: 9
                                                            font.weight: Font.DemiBold
                                                            color: "#f0883e"
                                                        }
                                                    }

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
                                                            font.pixelSize: 9
                                                            color: "#8b949e"
                                                        }
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    Text {
                                                        text: "#" + (modelData.short_hash || (modelData.commit_hash ? modelData.commit_hash.substring(0, 7) : ""))
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        color: modelData.is_abandoned ? "#6e7681" : "#58a6ff"
                                                    }
                                                }

                                                RowLayout {
                                                    spacing: 10
                                                    Text {
                                                        text: (modelData.committer || "Unknown") + " • " + (modelData.commit_date || "")
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 10
                                                        color: "#6e7681"
                                                    }

                                                    Text {
                                                        text: modelData.comment || ""
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 10
                                                        color: "#8b949e"
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                            }

                                            Button {
                                                visible: !!modelData.prepared_pr_id
                                                text: "PR !" + modelData.prepared_pr_id + (modelData.is_abandoned ? " (Abandoned) ↗" : " ↗")
                                                font.pixelSize: 10
                                                contentItem: Text {
                                                    text: parent.text
                                                    font: parent.font
                                                    color: modelData.is_abandoned ? "#f85149" : "#58a6ff"
                                                }
                                                background: Rectangle {
                                                    implicitHeight: 24
                                                    implicitWidth: modelData.is_abandoned ? 130 : 75
                                                    radius: 4
                                                    color: parent.hovered ? (modelData.is_abandoned ? "#3d1418" : "#21262d") : (modelData.is_abandoned ? "#261014" : "#161b22")
                                                    border.color: modelData.is_abandoned ? "#da3633" : "#30363d"
                                                }
                                                onClicked: {
                                                    var prUrl = root.selectedRepo.web_url + "/pullrequest/" + modelData.prepared_pr_id;
                                                    if (backend)
                                                        backend.open_url(prUrl);
                                                    else
                                                        Qt.openUrlExternally(prUrl);
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !repoBranchesList.count
                                        text: "No unmerged branches ahead of baseline."
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        color: "#8b949e"
                                    }
                                }
                            }

                            // SubTab 2: Active PRs List
                            Item {
                                ListView {
                                    id: repoActivePrsList
                                    anchors.fill: parent
                                    clip: true
                                    spacing: 6
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: (root.selectedRepo && root.selectedRepo.active_prs) ? root.selectedRepo.active_prs : []

                                    ScrollBar.vertical: ScrollBar {
                                        active: true
                                        policy: ScrollBar.AsNeeded
                                    }

                                    delegate: Rectangle {
                                        id: activePrCard
                                        width: repoActivePrsList.width - 8
                                        implicitHeight: activePrMainRow.implicitHeight + 16
                                        height: implicitHeight
                                        color: "#0d1117"
                                        radius: 6
                                        border.color: "#30363d"
                                        border.width: 1

                                        RowLayout {
                                            id: activePrMainRow
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.margins: 8
                                            spacing: 10

                                            ColumnLayout {
                                                id: activePrContentCol
                                                Layout.fillWidth: true
                                                spacing: 5

                                                // Header line
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Rectangle {
                                                        implicitHeight: 20
                                                        implicitWidth: activePrIdText.implicitWidth + 10
                                                        radius: 4
                                                        color: "#161b22"
                                                        border.color: "#30363d"
                                                        Text {
                                                            id: activePrIdText
                                                            anchors.centerIn: parent
                                                            text: "!" + modelData.pr_id
                                                            font.family: "Consolas, monospace"
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: "#58a6ff"
                                                        }
                                                    }

                                                    Text {
                                                        text: modelData.title
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                        color: "#f0f6fc"
                                                        Layout.fillWidth: true
                                                        wrapMode: Text.WordWrap
                                                    }

                                                    Rectangle {
                                                        visible: !!(modelData.source_branch || modelData.target_branch)
                                                        implicitHeight: 18
                                                        implicitWidth: activeBranchText.implicitWidth + 8
                                                        radius: 3
                                                        color: "#161b22"
                                                        border.color: "#30363d"
                                                        Text {
                                                            id: activeBranchText
                                                            anchors.centerIn: parent
                                                            text: modelData.source_branch ? (modelData.source_branch + " → " + modelData.target_branch) : (modelData.target_branch || "")
                                                            font.family: "Consolas, monospace"
                                                            font.pixelSize: 9
                                                            color: "#8b949e"
                                                        }
                                                    }
                                                }

                                                // Metadata row
                                                RowLayout {
                                                    spacing: 12
                                                    Text {
                                                        text: "👤 " + (modelData.created_by || "Unknown")
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 10
                                                        color: "#6e7681"
                                                    }
                                                    Text {
                                                        text: "📅 Created: " + (modelData.creation_date || modelData.date || "")
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        color: "#6e7681"
                                                    }
                                                    StatusBadge {
                                                        text: "ACTIVE"
                                                        badgeColor: "#1f6feb"
                                                    }
                                                }

                                                // Referenced tasks section
                                                ColumnLayout {
                                                    visible: !!(modelData.tasks && modelData.tasks.length > 0)
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    RowLayout {
                                                        spacing: 6
                                                        Text {
                                                            text: "🔗 REFERENCED WORK ITEMS"
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 9
                                                            font.weight: Font.Bold
                                                            color: "#8b949e"
                                                        }
                                                        Rectangle {
                                                            implicitHeight: 14
                                                            implicitWidth: activeTaskCountTxt.implicitWidth + 6
                                                            radius: 7
                                                            color: "#21262d"
                                                            Text {
                                                                id: activeTaskCountTxt
                                                                anchors.centerIn: parent
                                                                text: (modelData.tasks ? modelData.tasks.length : 0)
                                                                font.family: "Segoe UI, sans-serif"
                                                                font.pixelSize: 9
                                                                font.weight: Font.Bold
                                                                color: "#58a6ff"
                                                            }
                                                        }
                                                    }

                                                    Flow {
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        Repeater {
                                                            model: modelData.tasks || []
                                                            delegate: Rectangle {
                                                                implicitHeight: 22
                                                                implicitWidth: activeTaskContentRow.implicitWidth + 10
                                                                radius: 4
                                                                color: activeTaskMouseArea.containsMouse ? "#21262d" : "#161b22"
                                                                border.color: (modelData.type === "Bug") ? "#f85149" : (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#1f6feb" : "#30363d"
                                                                border.width: 1

                                                                RowLayout {
                                                                    id: activeTaskContentRow
                                                                    anchors.centerIn: parent
                                                                    spacing: 4

                                                                    Text {
                                                                        text: (modelData.type === "Bug") ? "🐛" : (modelData.type === "User Story") ? "📖" : (modelData.type === "Feature") ? "⭐" : "📋"
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
                                                                        color: "#e6edf3"
                                                                        Layout.maximumWidth: 180
                                                                        elide: Text.ElideRight
                                                                    }

                                                                    Rectangle {
                                                                        implicitHeight: 14
                                                                        implicitWidth: activeTaskStateTxt.implicitWidth + 6
                                                                        radius: 3
                                                                        color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#1f382b" : (modelData.state === "Active") ? "#192b45" : "#21262d"
                                                                        border.color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#388bfd" : "#484f58"
                                                                        border.width: 1
                                                                        Text {
                                                                            id: activeTaskStateTxt
                                                                            anchors.centerIn: parent
                                                                            text: modelData.state
                                                                            font.family: "Segoe UI, sans-serif"
                                                                            font.pixelSize: 8
                                                                            font.weight: Font.Bold
                                                                            color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#3fb950" : (modelData.state === "Active") ? "#58a6ff" : "#8b949e"
                                                                        }
                                                                    }
                                                                }

                                                                MouseArea {
                                                                    id: activeTaskMouseArea
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: {
                                                                        if (modelData.url) {
                                                                            if (backend)
                                                                                backend.open_url(modelData.url);
                                                                            else
                                                                                Qt.openUrlExternally(modelData.url);
                                                                        }
                                                                    }
                                                                }

                                                                ToolTip.visible: activeTaskMouseArea.containsMouse
                                                                ToolTip.text: modelData.type + " #" + modelData.id + ": " + modelData.title + (modelData.assigned_to ? ("
Assigned to: " + modelData.assigned_to) : "") + "
Status: " + modelData.state + "
Click to open in TFS"
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Open in TFS button
                                            Button {
                                                Layout.alignment: Qt.AlignTop
                                                text: "Open ↗"
                                                font.pixelSize: 10
                                                contentItem: Text {
                                                    text: parent.text
                                                    font: parent.font
                                                    color: "#58a6ff"
                                                }
                                                background: Rectangle {
                                                    implicitHeight: 24
                                                    implicitWidth: 55
                                                    radius: 4
                                                    color: parent.hovered ? "#21262d" : "#161b22"
                                                    border.color: "#30363d"
                                                }
                                                onClicked: {
                                                    var prUrl = root.selectedRepo.web_url + "/pullrequest/" + modelData.pr_id;
                                                    if (backend)
                                                        backend.open_url(prUrl);
                                                    else
                                                        Qt.openUrlExternally(prUrl);
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !repoActivePrsList.count
                                        text: "No active pull requests currently open."
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        color: "#8b949e"
                                    }
                                }
                            }

                            // SubTab 3: All PRs List with Tag Information
                            Item {
                                id: allPrsSubTabItem

                                property string allPrSearchQuery: ""
                                property string allPrStatusFilter: "all" // "all", "active", "completed", "abandoned"
                                property string allPrTagFilter: "all" // "all", "tagged", "untagged"

                                function getFilteredPrs() {
                                    if (!root.selectedRepo || !root.selectedRepo.all_prs) return [];
                                    var list = root.selectedRepo.all_prs;
                                    if (allPrStatusFilter !== "all") {
                                        list = list.filter(function(pr) {
                                            return pr.status === allPrStatusFilter;
                                        });
                                    }
                                    if (allPrTagFilter === "tagged") {
                                        list = list.filter(function(pr) {
                                            return !!pr.is_tagged;
                                        });
                                    } else if (allPrTagFilter === "untagged") {
                                        list = list.filter(function(pr) {
                                            return !pr.is_tagged && pr.status === "completed";
                                        });
                                    }
                                    if (allPrSearchQuery.trim().length > 0) {
                                        var q = allPrSearchQuery.trim().toLowerCase();
                                        list = list.filter(function(pr) {
                                            var t = (pr.title || "").toLowerCase();
                                            var idStr = (pr.pr_id ? pr.pr_id.toString() : "");
                                            var auth = (pr.created_by || "").toLowerCase();
                                            return t.indexOf(q) >= 0 || idStr.indexOf(q) >= 0 || auth.indexOf(q) >= 0;
                                        });
                                    }
                                    return list;
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    // Filter Bar
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 28
                                            radius: 4
                                            color: "#0d1117"
                                            border.color: allPrSearchInput.activeFocus ? "#58a6ff" : "#30363d"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                anchors.rightMargin: 6
                                                spacing: 4

                                                Text {
                                                    text: "🔍"
                                                    font.pixelSize: 10
                                                    color: "#8b949e"
                                                }

                                                TextInput {
                                                    id: allPrSearchInput
                                                    Layout.fillWidth: true
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 11
                                                    color: "#f0f6fc"
                                                    clip: true
                                                    onTextChanged: {
                                                        allPrsSubTabItem.allPrSearchQuery = text;
                                                    }

                                                    Text {
                                                        anchors.fill: parent
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "Filter PRs by ID, title, author..."
                                                        font: parent.font
                                                        color: "#484f58"
                                                        visible: !parent.text && !parent.activeFocus
                                                    }
                                                }
                                            }
                                        }

                                        Button {
                                            text: "All"
                                            checkable: true
                                            checked: allPrsSubTabItem.allPrStatusFilter === "all"
                                            font.pixelSize: 10
                                            contentItem: Text {
                                                text: parent.text
                                                font: parent.font
                                                color: parent.checked ? "#ffffff" : "#8b949e"
                                            }
                                            background: Rectangle {
                                                implicitHeight: 26
                                                implicitWidth: 38
                                                radius: 3
                                                color: parent.checked ? "#1f6feb" : "#0d1117"
                                                border.color: "#30363d"
                                            }
                                            onClicked: allPrsSubTabItem.allPrStatusFilter = "all"
                                        }

                                        Button {
                                            text: "Active"
                                            checkable: true
                                            checked: allPrsSubTabItem.allPrStatusFilter === "active"
                                            font.pixelSize: 10
                                            contentItem: Text {
                                                text: parent.text
                                                font: parent.font
                                                color: parent.checked ? "#ffffff" : "#8b949e"
                                            }
                                            background: Rectangle {
                                                implicitHeight: 26
                                                implicitWidth: 46
                                                radius: 3
                                                color: parent.checked ? "#1f6feb" : "#0d1117"
                                                border.color: "#30363d"
                                            }
                                            onClicked: allPrsSubTabItem.allPrStatusFilter = "active"
                                        }

                                        Button {
                                            text: "Untagged"
                                            checkable: true
                                            checked: allPrsSubTabItem.allPrTagFilter === "untagged"
                                            font.pixelSize: 10
                                            contentItem: Text {
                                                text: parent.text
                                                font: parent.font
                                                color: parent.checked ? "#ffffff" : "#d29922"
                                            }
                                            background: Rectangle {
                                                implicitHeight: 26
                                                implicitWidth: 60
                                                radius: 3
                                                color: parent.checked ? "#d29922" : "#0d1117"
                                                border.color: "#30363d"
                                            }
                                            onClicked: {
                                                if (allPrsSubTabItem.allPrTagFilter === "untagged")
                                                    allPrsSubTabItem.allPrTagFilter = "all";
                                                else
                                                    allPrsSubTabItem.allPrTagFilter = "untagged";
                                            }
                                        }
                                    }

                                    // PRs ListView
                                    ListView {
                                        id: repoAllPrsList
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: 6
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: allPrsSubTabItem.getFilteredPrs()

                                        ScrollBar.vertical: ScrollBar {
                                            active: true
                                            policy: ScrollBar.AsNeeded
                                        }

                                        delegate: Rectangle {
                                            id: allPrCard
                                            width: repoAllPrsList.width - 8
                                            implicitHeight: allPrMainRow.implicitHeight + 16
                                            height: implicitHeight
                                            color: "#0d1117"
                                            radius: 6
                                            border.color: "#30363d"
                                            border.width: 1

                                            RowLayout {
                                                id: allPrMainRow
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.margins: 8
                                                spacing: 10

                                                ColumnLayout {
                                                    id: allPrContentCol
                                                    Layout.fillWidth: true
                                                    spacing: 5

                                                    // Header line
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 8

                                                        Rectangle {
                                                            implicitHeight: 20
                                                            implicitWidth: allPrIdText.implicitWidth + 10
                                                            radius: 4
                                                            color: "#161b22"
                                                            border.color: "#30363d"
                                                            Text {
                                                                id: allPrIdText
                                                                anchors.centerIn: parent
                                                                text: "!" + modelData.pr_id
                                                                font.family: "Consolas, monospace"
                                                                font.pixelSize: 11
                                                                font.weight: Font.Bold
                                                                color: "#58a6ff"
                                                            }
                                                        }

                                                        Text {
                                                            text: modelData.title
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 12
                                                            font.weight: Font.DemiBold
                                                            color: "#f0f6fc"
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.WordWrap
                                                        }
                                                    }

                                                    // Metadata row
                                                    RowLayout {
                                                        spacing: 10
                                                        Text {
                                                            text: "👤 " + (modelData.created_by || "Unknown")
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 10
                                                            color: "#6e7681"
                                                        }
                                                        Text {
                                                            text: "📅 " + (modelData.closed_date || modelData.creation_date || modelData.date || "")
                                                            font.family: "Consolas, monospace"
                                                            font.pixelSize: 10
                                                            color: "#6e7681"
                                                        }
                                                        StatusBadge {
                                                            text: (modelData.status || "").toUpperCase()
                                                            badgeColor: modelData.status === "completed" ? "#238636" : (modelData.status === "active" ? "#1f6feb" : "#da3633")
                                                        }
                                                        Rectangle {
                                                            visible: modelData.status === "completed"
                                                            implicitHeight: 18
                                                            implicitWidth: tagPillTxt.implicitWidth + 8
                                                            radius: 3
                                                            color: modelData.is_tagged ? "#16281e" : "#281b0f"
                                                            border.color: modelData.is_tagged ? "#238636" : "#d29922"
                                                            border.width: 1
                                                            Text {
                                                                id: tagPillTxt
                                                                anchors.centerIn: parent
                                                                text: modelData.is_tagged ? ("🏷️ Tagged" + (modelData.tag_name ? " (" + modelData.tag_name + ")" : "")) : "⚡ UNTAGGED"
                                                                font.family: "Segoe UI, sans-serif"
                                                                font.pixelSize: 9
                                                                font.weight: Font.Bold
                                                                color: modelData.is_tagged ? "#3fb950" : "#f0883e"
                                                            }
                                                        }
                                                    }

                                                    // Tasks Repeater
                                                    ColumnLayout {
                                                        visible: !!(modelData.tasks && modelData.tasks.length > 0)
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        Flow {
                                                            Layout.fillWidth: true
                                                            spacing: 4

                                                            Repeater {
                                                                model: modelData.tasks || []
                                                                delegate: Rectangle {
                                                                    implicitHeight: 22
                                                                    implicitWidth: allPrTaskContentRow.implicitWidth + 10
                                                                    radius: 4
                                                                    color: allPrTaskMouseArea.containsMouse ? "#21262d" : "#161b22"
                                                                    border.color: (modelData.type === "Bug") ? "#f85149" : (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#1f6feb" : "#30363d"
                                                                    border.width: 1

                                                                    RowLayout {
                                                                        id: allPrTaskContentRow
                                                                        anchors.centerIn: parent
                                                                        spacing: 4

                                                                        Text {
                                                                            text: (modelData.type === "Bug") ? "🐛" : (modelData.type === "User Story") ? "📖" : (modelData.type === "Feature") ? "⭐" : "📋"
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
                                                                            color: "#e6edf3"
                                                                            Layout.maximumWidth: 180
                                                                            elide: Text.ElideRight
                                                                        }

                                                                        Rectangle {
                                                                            implicitHeight: 14
                                                                            implicitWidth: allPrTaskStateTxt.implicitWidth + 6
                                                                            radius: 3
                                                                            color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#1f382b" : (modelData.state === "Active") ? "#192b45" : "#21262d"
                                                                            border.color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#388bfd" : "#484f58"
                                                                            border.width: 1
                                                                            Text {
                                                                                id: allPrTaskStateTxt
                                                                                anchors.centerIn: parent
                                                                                text: modelData.state
                                                                                font.family: "Segoe UI, sans-serif"
                                                                                font.pixelSize: 8
                                                                                font.weight: Font.Bold
                                                                                color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#3fb950" : (modelData.state === "Active") ? "#58a6ff" : "#8b949e"
                                                                            }
                                                                        }
                                                                    }

                                                                    MouseArea {
                                                                        id: allPrTaskMouseArea
                                                                        anchors.fill: parent
                                                                        hoverEnabled: true
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: {
                                                                            if (modelData.url) {
                                                                                if (backend)
                                                                                    backend.open_url(modelData.url);
                                                                                else
                                                                                    Qt.openUrlExternally(modelData.url);
                                                                            }
                                                                        }
                                                                    }

                                                                    ToolTip.visible: allPrTaskMouseArea.containsMouse
                                                                    ToolTip.text: modelData.type + " #" + modelData.id + ": " + modelData.title + (modelData.assigned_to ? ("
Assigned to: " + modelData.assigned_to) : "") + "
Status: " + modelData.state + "
Click to open in TFS"
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Open in TFS button
                                                Button {
                                                    Layout.alignment: Qt.AlignTop
                                                    text: "Open ↗"
                                                    font.pixelSize: 10
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: "#58a6ff"
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 24
                                                        implicitWidth: 55
                                                        radius: 4
                                                        color: parent.hovered ? "#21262d" : "#161b22"
                                                        border.color: "#30363d"
                                                    }
                                                    onClicked: {
                                                        var prUrl = root.selectedRepo.web_url + "/pullrequest/" + modelData.pr_id;
                                                        if (backend)
                                                            backend.open_url(prUrl);
                                                        else
                                                            Qt.openUrlExternally(prUrl);
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !repoAllPrsList.count
                                            text: "No pull requests found for this repository."
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
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

    // Tagging Dialog Modal
    // =========================================================================
    Rectangle {
        id: tagModalOverlay
        anchors.fill: parent
        color: "#99000000"
        visible: root.tagModalOpen
        z: 9999

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (backend && !backend.isBusy)
                    root.tagModalOpen = false;
            }
        }

        Rectangle {
            id: tagModalBox
            width: Math.min(560, parent.width - 32)
            implicitHeight: modalCol.implicitHeight + 40
            anchors.centerIn: parent
            color: "#161b22"
            radius: 10
            border.color: "#388bfd"
            border.width: 1

            MouseArea {
                anchors.fill: parent
                // absorb clicks to prevent closing modal
            }

            ColumnLayout {
                id: modalCol
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                // Modal Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "🏷️ Tag Repository Release"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "✕"
                        font.pixelSize: 13
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 24
                            implicitWidth: 24
                            radius: 12
                            color: parent.hovered ? "#30363d" : "transparent"
                        }
                        onClicked: {
                            if (backend && !backend.isBusy)
                                root.tagModalOpen = false;
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#30363d"
                }

                // Target Repository Selection
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Target Repository:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: "#c9d1d9"
                    }

                    ComboBox {
                        id: modalRepoCombo
                        Layout.fillWidth: true
                        model: {
                            var list = [];
                            if (backend && backend.tagDayData && backend.tagDayData.repos_summary) {
                                for (var i = 0; i < backend.tagDayData.repos_summary.length; i++) {
                                    list.push(backend.tagDayData.repos_summary[i].name);
                                }
                            }
                            if (list.length === 0 && root.selectedRepoName)
                                list.push(root.selectedRepoName);
                            return list;
                        }
                        currentIndex: {
                            var idx = model.indexOf(root.tagModalRepo);
                            return idx >= 0 ? idx : 0;
                        }
                        onActivated: {
                            root.tagModalRepo = currentText;
                            root.tagModalBranches = backend ? backend.get_repo_branches(root.tagModalRepo) : ["dev", "main", "develop"];
                            root.setTagModalBump("patch");
                        }
                    }
                }

                // Target Branch (default: dev)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Target Branch (Dev Branch):"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: "#c9d1d9"
                        }
                        Text {
                            text: "• Tag is attached to latest commit on this branch"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            color: "#8b949e"
                        }
                    }

                    ComboBox {
                        id: modalBranchCombo
                        Layout.fillWidth: true
                        editable: true
                        model: root.tagModalBranches && root.tagModalBranches.length > 0 ? root.tagModalBranches : ["dev", "main", "master", "develop"]
                        currentIndex: {
                            var idx = model.indexOf(root.tagModalBranch);
                            return idx >= 0 ? idx : 0;
                        }
                        onEditTextChanged: {
                            root.tagModalBranch = editText.trim();
                            root.tagModalComment = "Tag Day release " + root.tagModalTagName + " from branch '" + root.tagModalBranch + "'";
                        }
                        onActivated: {
                            root.tagModalBranch = currentText;
                            root.tagModalComment = "Tag Day release " + root.tagModalTagName + " from branch '" + root.tagModalBranch + "'";
                        }
                    }
                }

                // Proposed Tag Name Field
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Tag Name:"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: "#c9d1d9"
                        }

                        Rectangle {
                            implicitHeight: 18
                            implicitWidth: 90
                            radius: 9
                            color: "#1f293d"
                            border.color: "#388bfd"
                            Text {
                                anchors.centerIn: parent
                                text: "Weekly <YYWW>"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                color: "#58a6ff"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Bump quick buttons in modal
                        Button {
                            text: "Patch"
                            font.pixelSize: 10
                            background: Rectangle {
                                implicitHeight: 20
                                implicitWidth: 50
                                radius: 3
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: root.setTagModalBump("patch")
                        }

                        Button {
                            text: "+Minor"
                            font.pixelSize: 10
                            background: Rectangle {
                                implicitHeight: 20
                                implicitWidth: 55
                                radius: 3
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: root.setTagModalBump("minor")
                        }

                        Button {
                            text: "+Major"
                            font.pixelSize: 10
                            background: Rectangle {
                                implicitHeight: 20
                                implicitWidth: 55
                                radius: 3
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: root.setTagModalBump("major")
                        }
                    }

                    TextField {
                        id: modalTagField
                        Layout.fillWidth: true
                        text: root.tagModalTagName
                        font.family: "Consolas, monospace"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: "#58a6ff"
                        background: Rectangle {
                            implicitHeight: 34
                            radius: 6
                            color: "#0d1117"
                            border.color: modalTagField.activeFocus ? "#388bfd" : "#30363d"
                            border.width: modalTagField.activeFocus ? 2 : 1
                        }
                        onTextChanged: {
                            root.tagModalTagName = text.trim();
                        }
                    }
                }

                // Tag Annotation / Comment
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Tag Message / Annotation:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: "#c9d1d9"
                    }

                    TextField {
                        id: modalCommentField
                        Layout.fillWidth: true
                        text: root.tagModalComment
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#f0f6fc"
                        background: Rectangle {
                            implicitHeight: 34
                            radius: 6
                            color: "#0d1117"
                            border.color: modalCommentField.activeFocus ? "#388bfd" : "#30363d"
                            border.width: modalCommentField.activeFocus ? 2 : 1
                        }
                        onTextChanged: {
                            root.tagModalComment = text;
                        }
                    }
                }

                // Status Banner / Feedback
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: statusText.implicitHeight + 16
                    radius: 6
                    visible: root.tagModalStatus !== ""
                    color: root.tagModalIsError ? "#3d1414" : (root.tagModalIsSuccess ? "#12261a" : "#1f293d")
                    border.color: root.tagModalIsError ? "#f85149" : (root.tagModalIsSuccess ? "#3fb950" : "#388bfd")

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8
                        Text {
                            text: root.tagModalIsError ? "❌" : (root.tagModalIsSuccess ? "✅" : "⏳")
                            font.pixelSize: 13
                        }
                        Text {
                            id: statusText
                            text: root.tagModalStatus
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: root.tagModalIsError ? "#f85149" : (root.tagModalIsSuccess ? "#3fb950" : "#58a6ff")
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Modal Actions Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Button {
                        text: root.tagModalIsSuccess ? "Done" : "Cancel"
                        enabled: backend ? !backend.isBusy : true
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#c9d1d9"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 90
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: root.tagModalOpen = false
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: (backend && backend.isBusy) ? "Tagging..." : ("🏷️ Create Tag '" + root.tagModalTagName + "'")
                        enabled: backend ? !backend.isBusy && root.tagModalRepo !== "" && root.tagModalTagName !== "" : false
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
                            implicitWidth: 210
                            radius: 6
                            color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#30363d"
                            border.color: parent.enabled ? "#3fb950" : "#30363d"
                        }
                        onClicked: {
                            root.tagModalStatus = "Tagging branch '" + root.tagModalBranch + "' in " + root.tagModalRepo + "...";
                            root.tagModalIsError = false;
                            root.tagModalIsSuccess = false;
                            if (backend) {
                                backend.create_tag_async(
                                    root.tagModalRepo,
                                    root.tagModalTagName,
                                    root.tagModalBranch,
                                    root.tagModalComment
                                );
                            }
                        }
                    }
                }
            }
        }
    }
}


