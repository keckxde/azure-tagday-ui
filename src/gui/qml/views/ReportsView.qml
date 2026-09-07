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
    property int repoDetailSubTab: 0 // 0: Merged PRs, 1: Unmerged Branches, 2: Active PRs

    function openTagDayRepo(repoName) {
        root.activeReportTab = 1;
        root.selectedRepoName = repoName;
        root.repoDetailSubTab = 0;
    }

    function openSprintReport(sprintName) {
        if (sprintName) {
            root.selectedSprintReport = sprintName;
        } else if (!root.selectedSprintReport && backend && backend.availableSprintList && backend.availableSprintList.length > 0) {
            root.selectedSprintReport = backend.availableSprintList[0];
        }
        root.activeReportTab = 4;
        if (backend && root.selectedSprintReport) {
            root.sprintReportData = backend.get_sprint_report_data(root.selectedSprintReport);
        }
    }

    function refreshSprintReport() {
        if (!root.selectedSprintReport && backend && backend.availableSprintList && backend.availableSprintList.length > 0) {
            root.selectedSprintReport = backend.availableSprintList[0];
        }
        if (backend && root.selectedSprintReport) {
            root.sprintReportData = backend.get_sprint_report_data(root.selectedSprintReport);
        }
    }

    onSelectedSprintReportChanged: {
        if (backend && root.selectedSprintReport) {
            root.sprintReportData = backend.get_sprint_report_data(root.selectedSprintReport);
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
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // Header and Tab Navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Text {
                text: "Reports & Analytics"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 18
                font.weight: Font.Bold
                color: "#f0f6fc"
            }

            Item {
                Layout.fillWidth: true
            }

            // Subtab Switcher
            Row {
                spacing: 6
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
                            implicitHeight: 32
                            implicitWidth: 135
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

            Button {
                text: "↻ Refresh Reports"
                font.pixelSize: 12
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#f0f6fc"
                }
                background: Rectangle {
                    implicitHeight: 32
                    implicitWidth: 130
                    radius: 6
                    color: parent.hovered ? "#30363d" : "#21262d"
                    border.color: "#30363d"
                }
                onClicked: {
                    if (backend) {
                        backend.load_interactive_reports();
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
                                    currentIndex: 0
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
                spacing: 16

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
                    }
                }

                // Metrics Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    StatCard {
                        Layout.fillWidth: true
                        title: "Repos Analyzed"
                        value: ((backend && backend.tagDayData && backend.tagDayData.repos_analyzed) ? backend.tagDayData.repos_analyzed : 0).toString()
                        subtitle: "Tracked in Tag Day scope"
                        accentColor: "#58a6ff"
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Repos with Changes"
                        value: ((backend && backend.tagDayData && backend.tagDayData.repos_with_changes_count) ? backend.tagDayData.repos_with_changes_count : 0).toString()
                        subtitle: "Pushes or PRs after tag"
                        accentColor: "#d29922"
                    }

                    StatCard {
                        Layout.fillWidth: true
                        title: "Untagged Log Entries"
                        value: ((backend && backend.tagDayData && backend.tagDayData.timeline_items_count) ? backend.tagDayData.timeline_items_count : 0).toString()
                        subtitle: "Candidate release items"
                        accentColor: "#3fb950"
                    }
                }

                // Split View: Changed Repositories & Release Timeline
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 16

                    // Left Column: Repositories with changes
                    Rectangle {
                        Layout.preferredWidth: 360
                        Layout.fillHeight: true
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Repositories with Changes"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: ((backend && backend.tagDayData && backend.tagDayData.repos_summary) ? backend.tagDayData.repos_summary.length : 0) + " repos"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                }
                            }

                            ListView {
                                id: tdReposList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 6
                                model: (backend && backend.tagDayData && backend.tagDayData.repos_summary) ? backend.tagDayData.repos_summary : []

                                ScrollBar.vertical: ScrollBar {
                                    active: true
                                    policy: ScrollBar.AsNeeded
                                }

                                delegate: Rectangle {
                                    id: repoCard
                                    width: tdReposList.width - 8
                                    height: 52
                                    radius: 6
                                    readonly property bool isSelected: root.selectedRepoName === modelData.name
                                    color: isSelected ? "#1f293d" : (cardMouse.containsMouse ? "#262c36" : "#21262d")
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

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: repoCard.isSelected ? 14 : 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Text {
                                                text: modelData.name
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: repoCard.isSelected ? Font.Bold : Font.DemiBold
                                                color: repoCard.isSelected ? "#58a6ff" : "#f0f6fc"
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Row {
                                                spacing: 6
                                                Text {
                                                    text: modelData.latest_tag || "-"
                                                    font.family: "Consolas, monospace"
                                                    font.pixelSize: 11
                                                    color: (modelData.latest_tag && modelData.latest_tag !== "-") ? "#3fb950" : "#8b949e"
                                                }
                                                Text {
                                                    text: "•"
                                                    font.pixelSize: 10
                                                    color: "#484f58"
                                                }
                                                Text {
                                                    text: modelData.category || "OTHERS"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    color: "#8b949e"
                                                }
                                            }
                                        }

                                        StatusBadge {
                                            text: (modelData.prs_count + modelData.branches_count) + " updates"
                                            badgeColor: repoCard.isSelected ? "#388bfd" : "#d29922"
                                        }
                                    }

                                    MouseArea {
                                        id: cardMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.selectedRepoName === modelData.name) {
                                                root.selectedRepoName = "";
                                            } else {
                                                root.selectedRepoName = modelData.name;
                                                root.repoDetailSubTab = 0;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Right Column: Changes Timeline OR Repository Details
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1
                        clip: true

                        // View 1: Global Changes Timeline (visible when no repo is selected)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            visible: root.selectedRepo === null

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Candidate Changes Timeline (All Repositories)"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "Click any repository or change to inspect details"
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
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        Text {
                                            text: modelData.repo_name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: itemMouse.containsMouse ? "#58a6ff" : "#8b949e"
                                            Layout.preferredWidth: 130
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
                                            badgeColor: modelData.status === "completed" ? "#238636" : (modelData.status === "active" ? "#1f6feb" : "#d29922")
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
                                                root.repoDetailSubTab = 0;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // View 2: Detailed Repository Inspector (visible when selectedRepo !== null)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10
                            visible: root.selectedRepo !== null

                            // Inspector Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Button {
                                    text: "← All Changes"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                    }
                                    background: Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: 105
                                        radius: 5
                                        color: parent.hovered ? "#21262d" : "#161b22"
                                        border.color: "#30363d"
                                    }
                                    onClicked: root.selectedRepoName = ""
                                }

                                Text {
                                    text: root.selectedRepo ? root.selectedRepo.name : ""
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
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
                                    implicitHeight: 24
                                    implicitWidth: defaultBranchTxt.implicitWidth + 14
                                    radius: 12
                                    color: "#21262d"
                                    border.color: "#30363d"
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: "🌿"
                                            font.pixelSize: 10
                                        }
                                        Text {
                                            id: defaultBranchTxt
                                            text: (root.selectedRepo && root.selectedRepo.default_branch) ? root.selectedRepo.default_branch : "main"
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            color: "#8b949e"
                                        }
                                    }
                                }

                                Button {
                                    text: "Open Web ↗"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#ffffff"
                                    }
                                    background: Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: 95
                                        radius: 5
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

                            // Baseline / Latest Semantic Tag Card
                            Rectangle {
                                Layout.fillWidth: true
                                height: (root.selectedRepo && root.selectedRepo.latest_tag_details && root.selectedRepo.latest_tag_details.comment) ? 72 : 58
                                color: "#0d1117"
                                radius: 6
                                border.color: "#30363d"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 12

                                    Rectangle {
                                        width: 36
                                        height: 36
                                        radius: 6
                                        color: "#161b22"
                                        border.color: (root.selectedRepo && root.selectedRepo.latest_tag !== "-") ? "#238636" : "#30363d"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "🏷️"
                                            font.pixelSize: 16
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: "Latest Semantic Tag:"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                color: "#8b949e"
                                            }
                                            Text {
                                                text: (root.selectedRepo && root.selectedRepo.latest_tag !== "-") ? root.selectedRepo.latest_tag : "No version tag"
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: (root.selectedRepo && root.selectedRepo.latest_tag !== "-") ? "#3fb950" : "#d29922"
                                            }
                                        }

                                        Text {
                                            text: {
                                                if (!root.selectedRepo || !root.selectedRepo.latest_tag_details || !root.selectedRepo.latest_tag_details.commit_date) {
                                                    return "Baseline: All commits and PRs evaluated since repository inception.";
                                                }
                                                var d = root.selectedRepo.latest_tag_details;
                                                return "Committed on " + d.commit_date + (d.committer ? " by " + d.committer : "");
                                            }
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#6e7681"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            visible: !!(root.selectedRepo && root.selectedRepo.latest_tag_details && root.selectedRepo.latest_tag_details.comment)
                                            text: (root.selectedRepo && root.selectedRepo.latest_tag_details) ? ("\"" + root.selectedRepo.latest_tag_details.comment + "\"") : ""
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.italic: true
                                            color: "#8b949e"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            // Sub-tabs for Details
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    text: "Merged PRs (" + (root.selectedRepo ? root.selectedRepo.prs_count : 0) + ")"
                                    checkable: true
                                    checked: root.repoDetailSubTab === 0
                                    font.pixelSize: 11
                                    font.weight: checked ? Font.DemiBold : Font.Normal
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: parent.checked ? "#ffffff" : "#8b949e"
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: 130
                                        radius: 4
                                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                        border.color: parent.checked ? "#388bfd" : "#30363d"
                                    }
                                    onClicked: root.repoDetailSubTab = 0
                                }

                                Button {
                                    text: "Unmerged Branches (" + (root.selectedRepo ? root.selectedRepo.branches_count : 0) + ")"
                                    checkable: true
                                    checked: root.repoDetailSubTab === 1
                                    font.pixelSize: 11
                                    font.weight: checked ? Font.DemiBold : Font.Normal
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: parent.checked ? "#ffffff" : "#8b949e"
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: 165
                                        radius: 4
                                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                        border.color: parent.checked ? "#388bfd" : "#30363d"
                                    }
                                    onClicked: root.repoDetailSubTab = 1
                                }

                                Button {
                                    text: "Active PRs (" + (root.selectedRepo ? root.selectedRepo.active_prs_count : 0) + ")"
                                    checkable: true
                                    checked: root.repoDetailSubTab === 2
                                    font.pixelSize: 11
                                    font.weight: checked ? Font.DemiBold : Font.Normal
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: parent.checked ? "#ffffff" : "#8b949e"
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: 115
                                        radius: 4
                                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                        border.color: parent.checked ? "#388bfd" : "#30363d"
                                    }
                                    onClicked: root.repoDetailSubTab = 2
                                }

                                Button {
                                    text: "All PRs (" + (root.selectedRepo ? (root.selectedRepo.all_prs_count !== undefined ? root.selectedRepo.all_prs_count : (root.selectedRepo.all_prs ? root.selectedRepo.all_prs.length : 0)) : 0) + ")"
                                    checkable: true
                                    checked: root.repoDetailSubTab === 3
                                    font.pixelSize: 11
                                    font.weight: checked ? Font.DemiBold : Font.Normal
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: parent.checked ? "#ffffff" : "#8b949e"
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: 120
                                        radius: 4
                                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                                        border.color: parent.checked ? "#388bfd" : "#30363d"
                                    }
                                    onClicked: root.repoDetailSubTab = 3
                                }

                                Item {
                                    Layout.fillWidth: true
                                }
                            }

                            // Dynamic List based on Sub-Tab
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
                                        model: (root.selectedRepo && root.selectedRepo.prs_after_tag) ? root.selectedRepo.prs_after_tag : []

                                        ScrollBar.vertical: ScrollBar {
                                            active: true
                                            policy: ScrollBar.AsNeeded
                                        }

                                        delegate: Rectangle {
                                            id: prCard
                                            width: repoPrsList.width - 8
                                            implicitHeight: prMainRow.implicitHeight + 20
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
                                                anchors.margins: 10
                                                spacing: 12

                                                ColumnLayout {
                                                    id: prContentCol
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    // Header line
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 8

                                                        Rectangle {
                                                            implicitHeight: 22
                                                            implicitWidth: prIdText.implicitWidth + 12
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
                                                            font.pixelSize: 13
                                                            font.weight: Font.DemiBold
                                                            color: "#f0f6fc"
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.WordWrap
                                                        }

                                                        Rectangle {
                                                            visible: !!(modelData.source_branch || modelData.target_branch)
                                                            implicitHeight: 20
                                                            implicitWidth: branchText.implicitWidth + 10
                                                            radius: 4
                                                            color: "#161b22"
                                                            border.color: "#30363d"
                                                            Text {
                                                                id: branchText
                                                                anchors.centerIn: parent
                                                                text: modelData.source_branch ? (modelData.source_branch + " → " + modelData.target_branch) : (modelData.target_branch || "")
                                                                font.family: "Consolas, monospace"
                                                                font.pixelSize: 10
                                                                color: "#8b949e"
                                                            }
                                                        }
                                                    }

                                                    // Metadata row
                                                    RowLayout {
                                                        spacing: 14
                                                        Text {
                                                            text: "👤 " + (modelData.created_by || "Unknown")
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 11
                                                            color: "#6e7681"
                                                        }
                                                        Text {
                                                            text: "📅 Merged: " + (modelData.closed_date || modelData.date || "")
                                                            font.family: "Consolas, monospace"
                                                            font.pixelSize: 11
                                                            color: "#6e7681"
                                                        }
                                                        StatusBadge {
                                                            text: "MERGED"
                                                            badgeColor: "#3fb950"
                                                        }
                                                        Rectangle {
                                                            implicitHeight: 20
                                                            implicitWidth: tagBadgeRow0.implicitWidth + 10
                                                            radius: 3
                                                            color: modelData.is_tagged ? "#162b20" : "#332200"
                                                            border.color: modelData.is_tagged ? "#238636" : "#9e6a03"
                                                            border.width: 1
                                                            RowLayout {
                                                                id: tagBadgeRow0
                                                                anchors.centerIn: parent
                                                                spacing: 4
                                                                Text {
                                                                    text: modelData.is_tagged ? ("🏷️ " + modelData.tag_name + (modelData.tag_type === "direct" ? " (direct)" : "")) : "⚠️ Untagged (Candidate)"
                                                                    font.family: "Segoe UI, sans-serif"
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.DemiBold
                                                                    color: modelData.is_tagged ? "#3fb950" : "#d29922"
                                                                }
                                                            }
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
                                                                font.pixelSize: 10
                                                                font.weight: Font.Bold
                                                                color: "#8b949e"
                                                            }
                                                            Rectangle {
                                                                implicitHeight: 16
                                                                implicitWidth: taskCountTxt.implicitWidth + 8
                                                                radius: 8
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
                                                            spacing: 6

                                                            Repeater {
                                                                model: modelData.tasks || []
                                                                delegate: Rectangle {
                                                                    implicitHeight: 26
                                                                    implicitWidth: taskContentRow.implicitWidth + 14
                                                                    radius: 4
                                                                    color: taskMouseArea.containsMouse ? "#21262d" : "#161b22"
                                                                    border.color: (modelData.type === "Bug") ? "#f85149" : (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#1f6feb" : "#30363d"
                                                                    border.width: 1

                                                                    RowLayout {
                                                                        id: taskContentRow
                                                                        anchors.centerIn: parent
                                                                        spacing: 6

                                                                        Text {
                                                                            text: (modelData.type === "Bug") ? "🐛" : (modelData.type === "User Story") ? "📖" : (modelData.type === "Feature") ? "⭐" : "📋"
                                                                            font.pixelSize: 10
                                                                        }

                                                                        Text {
                                                                            text: "#" + modelData.id
                                                                            font.family: "Consolas, monospace"
                                                                            font.pixelSize: 11
                                                                            font.weight: Font.Bold
                                                                            color: "#58a6ff"
                                                                        }

                                                                        Text {
                                                                            text: modelData.title
                                                                            font.family: "Segoe UI, sans-serif"
                                                                            font.pixelSize: 11
                                                                            color: "#e6edf3"
                                                                            Layout.maximumWidth: 280
                                                                            elide: Text.ElideRight
                                                                        }

                                                                        Rectangle {
                                                                            implicitHeight: 16
                                                                            implicitWidth: taskStateTxt.implicitWidth + 8
                                                                            radius: 3
                                                                            color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#1f382b" : (modelData.state === "Active") ? "#192b45" : "#21262d"
                                                                            border.color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#388bfd" : "#484f58"
                                                                            border.width: 1
                                                                            Text {
                                                                                id: taskStateTxt
                                                                                anchors.centerIn: parent
                                                                                text: modelData.state
                                                                                font.family: "Segoe UI, sans-serif"
                                                                                font.pixelSize: 9
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
                                                                    ToolTip.text: modelData.type + " #" + modelData.id + ": " + modelData.title + (modelData.assigned_to ? ("\nAssigned to: " + modelData.assigned_to) : "") + "\nStatus: " + modelData.state + "\nClick to open in TFS"
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Description in Markdown
                                                    Rectangle {
                                                        visible: !!(modelData.description && modelData.description.trim().length > 0)
                                                        Layout.fillWidth: true
                                                        implicitHeight: descText.implicitHeight + 16
                                                        color: "#161b22"
                                                        radius: 6
                                                        border.color: "#21262d"
                                                        border.width: 1

                                                        Text {
                                                            id: descText
                                                            anchors.top: parent.top
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.margins: 8
                                                            text: modelData.description ? modelData.description.trim() : ""
                                                            textFormat: Text.MarkdownText
                                                            wrapMode: Text.WordWrap
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 11
                                                            lineHeight: 1.25
                                                            color: "#c9d1d9"
                                                            linkColor: "#58a6ff"
                                                            onLinkActivated: function (link) {
                                                                if (backend)
                                                                    backend.open_url(link);
                                                                else
                                                                    Qt.openUrlExternally(link);
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
                                                        implicitHeight: 26
                                                        implicitWidth: 60
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
                                            text: "No pull requests merged after latest tag."
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 13
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
                                        model: (root.selectedRepo && root.selectedRepo.unmerged_branches) ? root.selectedRepo.unmerged_branches : []

                                        ScrollBar.vertical: ScrollBar {
                                            active: true
                                            policy: ScrollBar.AsNeeded
                                        }

                                        delegate: Rectangle {
                                            width: repoBranchesList.width - 8
                                            height: 58
                                            color: "#0d1117"
                                            radius: 6
                                            border.color: "#30363d"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 10

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3

                                                    RowLayout {
                                                        spacing: 8

                                                        Text {
                                                            text: "🌿 " + modelData.branch_name
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 12
                                                            font.weight: Font.Bold
                                                            color: "#f0f6fc"
                                                        }

                                                        StatusBadge {
                                                            text: "+" + modelData.ahead + " ahead"
                                                            badgeColor: "#d29922"
                                                        }

                                                        StatusBadge {
                                                            visible: modelData.behind > 0
                                                            text: "-" + modelData.behind + " behind"
                                                            badgeColor: "#6e7681"
                                                        }

                                                        Text {
                                                            text: modelData.short_hash ? ("#" + modelData.short_hash) : ""
                                                            font.family: "Consolas, monospace"
                                                            font.pixelSize: 11
                                                            color: "#58a6ff"
                                                        }
                                                    }

                                                    RowLayout {
                                                        spacing: 10
                                                        Text {
                                                            text: (modelData.committer || "Unknown") + " • " + (modelData.commit_date || "")
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 11
                                                            color: "#6e7681"
                                                        }

                                                        Text {
                                                            text: modelData.comment || ""
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 11
                                                            color: "#8b949e"
                                                            elide: Text.ElideRight
                                                            Layout.fillWidth: true
                                                        }
                                                    }
                                                }

                                                Button {
                                                    visible: !!modelData.prepared_pr_id
                                                    text: "PR !" + modelData.prepared_pr_id + " ↗"
                                                    font.pixelSize: 10
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: "#58a6ff"
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 24
                                                        implicitWidth: 80
                                                        radius: 4
                                                        color: parent.hovered ? "#21262d" : "#161b22"
                                                        border.color: "#30363d"
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
                                            font.pixelSize: 13
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
                                        model: (root.selectedRepo && root.selectedRepo.active_prs) ? root.selectedRepo.active_prs : []

                                        ScrollBar.vertical: ScrollBar {
                                            active: true
                                            policy: ScrollBar.AsNeeded
                                        }

                                        delegate: Rectangle {
                                            id: activePrCard
                                            width: repoActivePrsList.width - 8
                                            implicitHeight: activePrMainRow.implicitHeight + 20
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
                                                anchors.margins: 10
                                                spacing: 12

                                                ColumnLayout {
                                                    id: activePrContentCol
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    // Header line
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 8

                                                        Rectangle {
                                                            implicitHeight: 22
                                                            implicitWidth: activePrIdText.implicitWidth + 12
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
                                                            font.pixelSize: 13
                                                            font.weight: Font.DemiBold
                                                            color: "#f0f6fc"
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.WordWrap
                                                        }

                                                        Rectangle {
                                                            visible: !!(modelData.source_branch || modelData.target_branch)
                                                            implicitHeight: 20
                                                            implicitWidth: activeBranchText.implicitWidth + 10
                                                            radius: 4
                                                            color: "#161b22"
                                                            border.color: "#30363d"
                                                            Text {
                                                                id: activeBranchText
                                                                anchors.centerIn: parent
                                                                text: modelData.source_branch ? (modelData.source_branch + " → " + modelData.target_branch) : (modelData.target_branch || "")
                                                                font.family: "Consolas, monospace"
                                                                font.pixelSize: 10
                                                                color: "#8b949e"
                                                            }
                                                        }
                                                    }

                                                    // Metadata row
                                                    RowLayout {
                                                        spacing: 14
                                                        Text {
                                                            text: "👤 " + (modelData.created_by || "Unknown")
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 11
                                                            color: "#6e7681"
                                                        }
                                                        Text {
                                                            text: "📅 Created: " + (modelData.creation_date || modelData.date || "")
                                                            font.family: "Consolas, monospace"
                                                            font.pixelSize: 11
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
                                                                font.pixelSize: 10
                                                                font.weight: Font.Bold
                                                                color: "#8b949e"
                                                            }
                                                            Rectangle {
                                                                implicitHeight: 16
                                                                implicitWidth: activeTaskCountTxt.implicitWidth + 8
                                                                radius: 8
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
                                                            spacing: 6

                                                            Repeater {
                                                                model: modelData.tasks || []
                                                                delegate: Rectangle {
                                                                    implicitHeight: 26
                                                                    implicitWidth: activeTaskContentRow.implicitWidth + 14
                                                                    radius: 4
                                                                    color: activeTaskMouseArea.containsMouse ? "#21262d" : "#161b22"
                                                                    border.color: (modelData.type === "Bug") ? "#f85149" : (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#1f6feb" : "#30363d"
                                                                    border.width: 1

                                                                    RowLayout {
                                                                        id: activeTaskContentRow
                                                                        anchors.centerIn: parent
                                                                        spacing: 6

                                                                        Text {
                                                                            text: (modelData.type === "Bug") ? "🐛" : (modelData.type === "User Story") ? "📖" : (modelData.type === "Feature") ? "⭐" : "📋"
                                                                            font.pixelSize: 10
                                                                        }

                                                                        Text {
                                                                            text: "#" + modelData.id
                                                                            font.family: "Consolas, monospace"
                                                                            font.pixelSize: 11
                                                                            font.weight: Font.Bold
                                                                            color: "#58a6ff"
                                                                        }

                                                                        Text {
                                                                            text: modelData.title
                                                                            font.family: "Segoe UI, sans-serif"
                                                                            font.pixelSize: 11
                                                                            color: "#e6edf3"
                                                                            Layout.maximumWidth: 280
                                                                            elide: Text.ElideRight
                                                                        }

                                                                        Rectangle {
                                                                            implicitHeight: 16
                                                                            implicitWidth: activeTaskStateTxt.implicitWidth + 8
                                                                            radius: 3
                                                                            color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#1f382b" : (modelData.state === "Active") ? "#192b45" : "#21262d"
                                                                            border.color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#388bfd" : "#484f58"
                                                                            border.width: 1
                                                                            Text {
                                                                                id: activeTaskStateTxt
                                                                                anchors.centerIn: parent
                                                                                text: modelData.state
                                                                                font.family: "Segoe UI, sans-serif"
                                                                                font.pixelSize: 9
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
                                                                    ToolTip.text: modelData.type + " #" + modelData.id + ": " + modelData.title + (modelData.assigned_to ? ("\nAssigned to: " + modelData.assigned_to) : "") + "\nStatus: " + modelData.state + "\nClick to open in TFS"
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Description in Markdown
                                                    Rectangle {
                                                        visible: !!(modelData.description && modelData.description.trim().length > 0)
                                                        Layout.fillWidth: true
                                                        implicitHeight: activeDescText.implicitHeight + 16
                                                        color: "#161b22"
                                                        radius: 6
                                                        border.color: "#21262d"
                                                        border.width: 1

                                                        Text {
                                                            id: activeDescText
                                                            anchors.top: parent.top
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.margins: 8
                                                            text: modelData.description ? modelData.description.trim() : ""
                                                            textFormat: Text.MarkdownText
                                                            wrapMode: Text.WordWrap
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 11
                                                            lineHeight: 1.25
                                                            color: "#c9d1d9"
                                                            linkColor: "#58a6ff"
                                                            onLinkActivated: function (link) {
                                                                if (backend)
                                                                    backend.open_url(link);
                                                                else
                                                                    Qt.openUrlExternally(link);
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
                                                        implicitHeight: 26
                                                        implicitWidth: 60
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
                                            font.pixelSize: 13
                                            color: "#8b949e"
                                        }
                                    }
                                }

                                // SubTab 3: All PRs List with Tag Information
                                Item {
                                    id: allPrsSubTabItem
                                    property string prFilter: "ALL"
                                    property string prSearchQuery: ""

                                    function getFilteredPrs() {
                                        var prs = (root.selectedRepo && root.selectedRepo.all_prs) ? root.selectedRepo.all_prs : [];
                                        if (!prs)
                                            return [];
                                        var q = allPrsSubTabItem.prSearchQuery.toLowerCase().trim();
                                        return prs.filter(function (p) {
                                            if (allPrsSubTabItem.prFilter === "TAGGED" && !p.is_tagged)
                                                return false;
                                            if (allPrsSubTabItem.prFilter === "UNTAGGED" && p.is_tagged)
                                                return false;
                                            if (q.length > 0) {
                                                var idMatch = ("" + p.pr_id).indexOf(q) !== -1;
                                                var titleMatch = (p.title || "").toLowerCase().indexOf(q) !== -1;
                                                var authorMatch = (p.created_by || "").toLowerCase().indexOf(q) !== -1;
                                                var tagMatch = (p.tag_name || "").toLowerCase().indexOf(q) !== -1;
                                                return idMatch || titleMatch || authorMatch || tagMatch;
                                            }
                                            return true;
                                        });
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: 8

                                        // Filter and Search Toolbar
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            // Filter buttons: All, Tagged, Untagged
                                            RowLayout {
                                                spacing: 4

                                                Button {
                                                    text: "All"
                                                    checkable: true
                                                    checked: allPrsSubTabItem.prFilter === "ALL"
                                                    font.pixelSize: 10
                                                    font.weight: checked ? Font.DemiBold : Font.Normal
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: parent.checked ? "#ffffff" : "#8b949e"
                                                        horizontalAlignment: Text.AlignHCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 24
                                                        implicitWidth: 45
                                                        radius: 3
                                                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                                                        border.color: parent.checked ? "#388bfd" : "#30363d"
                                                    }
                                                    onClicked: allPrsSubTabItem.prFilter = "ALL"
                                                }

                                                Button {
                                                    text: "🏷️ Tagged"
                                                    checkable: true
                                                    checked: allPrsSubTabItem.prFilter === "TAGGED"
                                                    font.pixelSize: 10
                                                    font.weight: checked ? Font.DemiBold : Font.Normal
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: parent.checked ? "#ffffff" : "#8b949e"
                                                        horizontalAlignment: Text.AlignHCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 24
                                                        implicitWidth: 75
                                                        radius: 3
                                                        color: parent.checked ? "#238636" : (parent.hovered ? "#21262d" : "#161b22")
                                                        border.color: parent.checked ? "#3fb950" : "#30363d"
                                                    }
                                                    onClicked: allPrsSubTabItem.prFilter = "TAGGED"
                                                }

                                                Button {
                                                    text: "⚠️ Untagged"
                                                    checkable: true
                                                    checked: allPrsSubTabItem.prFilter === "UNTAGGED"
                                                    font.pixelSize: 10
                                                    font.weight: checked ? Font.DemiBold : Font.Normal
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: parent.checked ? "#ffffff" : "#8b949e"
                                                        horizontalAlignment: Text.AlignHCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 24
                                                        implicitWidth: 85
                                                        radius: 3
                                                        color: parent.checked ? "#9e6a03" : (parent.hovered ? "#21262d" : "#161b22")
                                                        border.color: parent.checked ? "#d29922" : "#30363d"
                                                    }
                                                    onClicked: allPrsSubTabItem.prFilter = "UNTAGGED"
                                                }
                                            }

                                            // Quick Search Field
                                            Rectangle {
                                                Layout.preferredWidth: 230
                                                Layout.preferredHeight: 26
                                                color: "#0d1117"
                                                radius: 4
                                                border.color: allPrSearchField.activeFocus ? "#58a6ff" : "#30363d"
                                                border.width: 1

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 6
                                                    spacing: 4

                                                    Text {
                                                        text: "🔍"
                                                        font.pixelSize: 10
                                                    }

                                                    TextInput {
                                                        id: allPrSearchField
                                                        Layout.fillWidth: true
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: "#e6edf3"
                                                        clip: true
                                                        selectByMouse: true
                                                        onTextChanged: allPrsSubTabItem.prSearchQuery = text

                                                        Text {
                                                            anchors.fill: parent
                                                            visible: !allPrSearchField.text && !allPrSearchField.activeFocus
                                                            text: "Filter PRs by ID, title, tag..."
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 11
                                                            color: "#6e7681"
                                                        }
                                                    }

                                                    Text {
                                                        visible: !!allPrSearchField.text
                                                        text: "✕"
                                                        font.pixelSize: 10
                                                        color: "#8b949e"
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                allPrSearchField.text = "";
                                                                allPrSearchField.forceActiveFocus();
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: "Showing " + repoAllPrsList.count + " of " + (root.selectedRepo ? (root.selectedRepo.all_prs_count !== undefined ? root.selectedRepo.all_prs_count : (root.selectedRepo.all_prs ? root.selectedRepo.all_prs.length : 0)) : 0) + " PRs"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                color: "#8b949e"
                                            }
                                        }

                                        // PRs ListView
                                        ListView {
                                            id: repoAllPrsList
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            spacing: 6
                                            model: allPrsSubTabItem.getFilteredPrs()

                                            ScrollBar.vertical: ScrollBar {
                                                active: true
                                                policy: ScrollBar.AsNeeded
                                            }

                                            delegate: Rectangle {
                                                id: allPrCard
                                                width: repoAllPrsList.width - 8
                                                implicitHeight: allPrMainRow.implicitHeight + 20
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
                                                    anchors.margins: 10
                                                    spacing: 12

                                                    ColumnLayout {
                                                        id: allPrContentCol
                                                        Layout.fillWidth: true
                                                        spacing: 6

                                                        // Header line
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 8

                                                            Rectangle {
                                                                implicitHeight: 22
                                                                implicitWidth: allPrIdText.implicitWidth + 12
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
                                                                font.pixelSize: 13
                                                                font.weight: Font.DemiBold
                                                                color: "#f0f6fc"
                                                                Layout.fillWidth: true
                                                                wrapMode: Text.WordWrap
                                                            }

                                                            Rectangle {
                                                                visible: !!(modelData.source_branch || modelData.target_branch)
                                                                implicitHeight: 20
                                                                implicitWidth: allBranchText.implicitWidth + 10
                                                                radius: 4
                                                                color: "#161b22"
                                                                border.color: "#30363d"
                                                                Text {
                                                                    id: allBranchText
                                                                    anchors.centerIn: parent
                                                                    text: modelData.source_branch ? (modelData.source_branch + " → " + modelData.target_branch) : (modelData.target_branch || "")
                                                                    font.family: "Consolas, monospace"
                                                                    font.pixelSize: 10
                                                                    color: "#8b949e"
                                                                }
                                                            }
                                                        }

                                                        // Metadata row with Status & Tag info
                                                        RowLayout {
                                                            spacing: 14

                                                            Text {
                                                                text: "👤 " + (modelData.created_by || "Unknown")
                                                                font.family: "Segoe UI, sans-serif"
                                                                font.pixelSize: 11
                                                                color: "#6e7681"
                                                            }

                                                            Text {
                                                                text: (modelData.status === "completed" ? "📅 Merged: " : "📅 Created: ") + (modelData.closed_date || modelData.creation_date || modelData.date || "")
                                                                font.family: "Consolas, monospace"
                                                                font.pixelSize: 11
                                                                color: "#6e7681"
                                                            }

                                                            StatusBadge {
                                                                text: (modelData.status === "completed" || modelData.status === "3") ? "MERGED" : (modelData.status === "active" || modelData.status === "1") ? "ACTIVE" : (modelData.status === "abandoned" || modelData.status === "2") ? "ABANDONED" : (modelData.status_str || "UNKNOWN")
                                                                badgeColor: (modelData.status === "completed" || modelData.status === "3") ? "#3fb950" : (modelData.status === "active" || modelData.status === "1") ? "#1f6feb" : "#8b949e"
                                                            }

                                                            // Tag Information Badge
                                                            Rectangle {
                                                                implicitHeight: 20
                                                                implicitWidth: allPrTagBadgeRow.implicitWidth + 10
                                                                radius: 3
                                                                color: modelData.is_tagged ? "#162b20" : (modelData.status === "completed" || modelData.status === "3") ? "#332200" : "#161b22"
                                                                border.color: modelData.is_tagged ? "#238636" : (modelData.status === "completed" || modelData.status === "3") ? "#9e6a03" : "#30363d"
                                                                border.width: 1

                                                                RowLayout {
                                                                    id: allPrTagBadgeRow
                                                                    anchors.centerIn: parent
                                                                    spacing: 4
                                                                    Text {
                                                                        text: modelData.is_tagged ? ("🏷️ " + modelData.tag_name + (modelData.tag_type === "direct" ? " (direct)" : "")) : (modelData.status === "completed" || modelData.status === "3") ? "⚠️ Untagged (Candidate)" : (modelData.status === "active" || modelData.status === "1") ? "⏳ In Review" : "✕ Untagged"
                                                                        font.family: "Segoe UI, sans-serif"
                                                                        font.pixelSize: 10
                                                                        font.weight: Font.DemiBold
                                                                        color: modelData.is_tagged ? "#3fb950" : (modelData.status === "completed" || modelData.status === "3") ? "#d29922" : "#8b949e"
                                                                    }
                                                                }

                                                                ToolTip.visible: allPrTagHover.hovered
                                                                ToolTip.text: modelData.is_tagged ? (modelData.tag_type === "direct" ? "Direct merge commit tag" : ("Included in release tag " + modelData.tag_name)) : (modelData.status === "completed" || modelData.status === "3") ? "Merged after latest tag or repository has no tags" : ""
                                                                HoverHandler {
                                                                    id: allPrTagHover
                                                                }
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
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.Bold
                                                                    color: "#8b949e"
                                                                }
                                                                Rectangle {
                                                                    implicitHeight: 16
                                                                    implicitWidth: allPrTaskCountTxt.implicitWidth + 8
                                                                    radius: 8
                                                                    color: "#21262d"
                                                                    Text {
                                                                        id: allPrTaskCountTxt
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
                                                                spacing: 6

                                                                Repeater {
                                                                    model: modelData.tasks || []
                                                                    delegate: Rectangle {
                                                                        implicitHeight: 26
                                                                        implicitWidth: allPrTaskContentRow.implicitWidth + 14
                                                                        radius: 4
                                                                        color: allPrTaskMouseArea.containsMouse ? "#21262d" : "#161b22"
                                                                        border.color: (modelData.type === "Bug") ? "#f85149" : (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#1f6feb" : "#30363d"
                                                                        border.width: 1

                                                                        RowLayout {
                                                                            id: allPrTaskContentRow
                                                                            anchors.centerIn: parent
                                                                            spacing: 6

                                                                            Text {
                                                                                text: (modelData.type === "Bug") ? "🐛" : (modelData.type === "User Story") ? "📖" : (modelData.type === "Feature") ? "⭐" : "📋"
                                                                                font.pixelSize: 10
                                                                            }

                                                                            Text {
                                                                                text: "#" + modelData.id
                                                                                font.family: "Consolas, monospace"
                                                                                font.pixelSize: 11
                                                                                font.weight: Font.Bold
                                                                                color: "#58a6ff"
                                                                            }

                                                                            Text {
                                                                                text: modelData.title
                                                                                font.family: "Segoe UI, sans-serif"
                                                                                font.pixelSize: 11
                                                                                color: "#e6edf3"
                                                                                Layout.maximumWidth: 280
                                                                                elide: Text.ElideRight
                                                                            }

                                                                            Rectangle {
                                                                                implicitHeight: 16
                                                                                implicitWidth: allPrTaskStateTxt.implicitWidth + 8
                                                                                radius: 3
                                                                                color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#1f382b" : (modelData.state === "Active") ? "#192b45" : "#21262d"
                                                                                border.color: (modelData.state === "Closed" || modelData.state === "Done" || modelData.state === "Resolved") ? "#238636" : (modelData.state === "Active") ? "#388bfd" : "#484f58"
                                                                                border.width: 1
                                                                                Text {
                                                                                    id: allPrTaskStateTxt
                                                                                    anchors.centerIn: parent
                                                                                    text: modelData.state
                                                                                    font.family: "Segoe UI, sans-serif"
                                                                                    font.pixelSize: 9
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
                                                                        ToolTip.text: modelData.type + " #" + modelData.id + ": " + modelData.title + (modelData.assigned_to ? ("\nAssigned to: " + modelData.assigned_to) : "") + "\nStatus: " + modelData.state + "\nClick to open in TFS"
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // Description in Markdown
                                                        Rectangle {
                                                            visible: !!(modelData.description && modelData.description.trim().length > 0)
                                                            Layout.fillWidth: true
                                                            implicitHeight: allPrDescText.implicitHeight + 16
                                                            color: "#161b22"
                                                            radius: 6
                                                            border.color: "#21262d"
                                                            border.width: 1

                                                            Text {
                                                                id: allPrDescText
                                                                anchors.top: parent.top
                                                                anchors.left: parent.left
                                                                anchors.right: parent.right
                                                                anchors.margins: 8
                                                                text: modelData.description ? modelData.description.trim() : ""
                                                                textFormat: Text.MarkdownText
                                                                wrapMode: Text.WordWrap
                                                                font.family: "Segoe UI, sans-serif"
                                                                font.pixelSize: 11
                                                                lineHeight: 1.25
                                                                color: "#c9d1d9"
                                                                linkColor: "#58a6ff"
                                                                onLinkActivated: function (link) {
                                                                    if (backend)
                                                                        backend.open_url(link);
                                                                    else
                                                                        Qt.openUrlExternally(link);
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
                                                            implicitHeight: 26
                                                            implicitWidth: 60
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
                                                font.pixelSize: 13
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

                // Interactive Artifacts Table
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Published Build Artifacts Explorer"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "Showing recent artifacts"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }

                        // Table Header
                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            color: "#0d1117"
                            radius: 4

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 20
                                spacing: 10

                                Text {
                                    text: "BUILD"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 70
                                }
                                Text {
                                    text: "REPOSITORY"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 150
                                }
                                Text {
                                    text: "BRANCH"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 120
                                }
                                Text {
                                    text: "ARTIFACT NAME"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "SIZE"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 80
                                }
                                Text {
                                    text: "STATUS"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 80
                                }
                            }
                        }

                        ListView {
                            id: artifactList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            model: (backend && backend.storageData && backend.storageData.artifacts_list) ? backend.storageData.artifacts_list : []

                            ScrollBar.vertical: ScrollBar {
                                active: true
                                policy: ScrollBar.AsNeeded
                            }

                            delegate: Rectangle {
                                width: artifactList.width - 8
                                height: 40
                                color: "#21262d"
                                radius: 4

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    Text {
                                        text: "#" + modelData.build_id
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                        Layout.preferredWidth: 70
                                    }

                                    Text {
                                        text: modelData.repo_name || "N/A"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#f0f6fc"
                                        Layout.preferredWidth: 150
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: (modelData.source_branch || "").replace("refs/heads/", "")
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                        Layout.preferredWidth: 120
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
                                        text: (modelData.size_mb || 0) + " MB"
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 11
                                        color: "#d29922"
                                        Layout.preferredWidth: 80
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
                                    if (!backend || !backend.availableSprintList) return 0;
                                    var idx = backend.availableSprintList.indexOf(root.selectedSprintReport);
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
                                    cursorShape: (modelData.tfs_url || "") !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (backend && (modelData.tfs_url || "") !== "") {
                                            backend.open_url(modelData.tfs_url);
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    // ID
                                    Text {
                                        text: "#" + modelData.id
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                        Layout.preferredWidth: 64
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

                                    // Title
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || ""
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
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
                                        Layout.preferredWidth: 120
                                        elide: Text.ElideRight
                                    }

                                    // TFS Link
                                    Button {
                                        text: "↗ TFS"
                                        font.pixelSize: 10
                                        Layout.preferredWidth: 50
                                        contentItem: Text { text: parent.text; font: parent.font; color: "#58a6ff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { implicitHeight: 22; radius: 4; color: parent.hovered ? "#30363d" : "transparent"; border.color: "#30363d" }
                                        onClicked: {
                                            if (backend && (modelData.tfs_url || "") !== "") {
                                                backend.open_url(modelData.tfs_url);
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

                    // Subheader & Filters
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
                                text: "Audit log of work item iteration changes (manual moves & TFS sync shifts) with delay metrics"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Source Filter (All / Manual / TFS Sync)
                        Row {
                            spacing: 4
                            Repeater {
                                model: [
                                    { label: "All Events", value: "all" },
                                    { label: "🖥️ GUI Moves", value: "user_gui" },
                                    { label: "🔄 TFS Sync", value: "tfs_sync" }
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
                                        implicitWidth: 100
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

                        // Search Filter
                        SearchBar {
                            placeholder: "Search item, title, sprint..."
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
                                    Text { text: "TOTAL SHIFT EVENTS"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
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
                            Layout.preferredWidth: 420
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
                                        text: "Sorted by delay"
                                        font.pixelSize: 10
                                        color: "#8b949e"
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
                                        width: topShiftedList.width - 6
                                        height: delayedItemCol.implicitHeight + 14
                                        radius: 6
                                        color: "#0d1117"
                                        border.color: "#30363d"
                                        border.width: 1

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
                                                Text {
                                                    text: "👤 " + (modelData.assigned_to || "Unassigned")
                                                    font.pixelSize: 10
                                                    color: "#8b949e"
                                                }
                                                Item { Layout.fillWidth: true }
                                                Text {
                                                    text: "Current: " + (modelData.iteration_path ? modelData.iteration_path.split("\\").pop() : "None")
                                                    font.pixelSize: 10
                                                    color: "#58a6ff"
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
                                        text: "Latest events first"
                                        font.pixelSize: 10
                                        color: "#8b949e"
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
                                        if (root.shiftSourceFilter !== "all") {
                                            list = list.filter(function(ev) {
                                                return ev.source === root.shiftSourceFilter;
                                            });
                                        }
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
                                        width: shiftEventsList.width - 6
                                        height: eventCol.implicitHeight + 14
                                        radius: 6
                                        color: "#0d1117"
                                        border.color: "#30363d"
                                        border.width: 1

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
