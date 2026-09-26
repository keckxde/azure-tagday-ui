import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root

    function getGanttWeeks() {
        var weeks = [];
        var now = new Date();
        var day = now.getDay();
        var diff = now.getDate() - day + (day === 0 ? -6 : 1);
        var monday = new Date(now.getFullYear(), now.getMonth(), diff, 0, 0, 0, 0);

        for (var i = 0; i < 6; i++) {
            var start = new Date(monday.getTime() + (i * 7 * 86400000));
            var end = new Date(start.getTime() + (6 * 86400000));

            var d = new Date(Date.UTC(start.getFullYear(), start.getMonth(), start.getDate()));
            var dayNum = d.getUTCDay() || 7;
            d.setUTCDate(d.getUTCDate() + 4 - dayNum);
            var yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
            var weekNo = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);

            var startMonth = start.toLocaleString('en-US', { month: 'short' });
            var endMonth = end.toLocaleString('en-US', { month: 'short' });
            var rangeText = startMonth + " " + start.getDate() + " - " + (startMonth === endMonth ? "" : (endMonth + " ")) + end.getDate();

            var sy = start.getFullYear();
            var sm = String(start.getMonth() + 1).padStart(2, '0');
            var sd = String(start.getDate()).padStart(2, '0');
            var isoStart = sy + "-" + sm + "-" + sd;

            var ey = end.getFullYear();
            var em = String(end.getMonth() + 1).padStart(2, '0');
            var ed = String(end.getDate()).padStart(2, '0');
            var isoEnd = ey + "-" + em + "-" + ed;

            weeks.push({
                index: i,
                weekNo: weekNo,
                title: i === 0 ? ("W" + weekNo + " (This)") : (i === 1 ? ("W" + weekNo + " (Next)") : (i === 5 ? ("W" + weekNo + "+") : ("W" + weekNo))),
                range: rangeText,
                isoStart: isoStart,
                isoEnd: isoEnd,
                isCurrent: (i === 0),
                isLast: (i === 5)
            });
        }
        return weeks;
    }

    function getGanttRows() {
        var list = (backend && backend.comingMilestones) ? backend.comingMilestones : [];
        var catMap = {};
        var rows = [];

        if (backend && backend.milestoneCategories) {
            for (var c = 0; c < backend.milestoneCategories.length; c++) {
                var cat = backend.milestoneCategories[c];
                catMap[cat.name] = {
                    category_name: cat.name,
                    category_icon: cat.icon || "🚩",
                    category_color: cat.color || "#58a6ff",
                    category_bg_color: cat.bg_color || "#13233a",
                    milestones: []
                };
            }
        }

        for (var i = 0; i < list.length; i++) {
            var m = list[i];
            var cName = m.category_name || "General";
            if (!catMap[cName]) {
                catMap[cName] = {
                    category_name: cName,
                    category_icon: m.category_icon || "🚩",
                    category_color: m.category_color || "#58a6ff",
                    category_bg_color: m.category_bg_color || "#13233a",
                    milestones: []
                };
            }
            catMap[cName].milestones.push(m);
        }

        for (var k in catMap) {
            if (catMap[k].milestones.length > 0) {
                rows.push(catMap[k]);
            }
        }

        if (rows.length === 0 && backend && backend.milestoneCategories && backend.milestoneCategories.length > 0) {
            for (var j = 0; j < Math.min(2, backend.milestoneCategories.length); j++) {
                rows.push({
                    category_name: backend.milestoneCategories[j].name,
                    category_icon: backend.milestoneCategories[j].icon || "🚩",
                    category_color: backend.milestoneCategories[j].color || "#58a6ff",
                    category_bg_color: backend.milestoneCategories[j].bg_color || "#13233a",
                    milestones: []
                });
            }
        }
        return rows;
    }

    function getMilestonesForWeek(rowMilestones, weekObj) {
        if (!rowMilestones || rowMilestones.length === 0) return [];
        var res = [];
        for (var i = 0; i < rowMilestones.length; i++) {
            var m = rowMilestones[i];
            var mStart = (m.start_date || m.target_date || "").split("T")[0].split(" ")[0].trim();
            var mEnd = (m.end_date || m.target_date || mStart).split("T")[0].split(" ")[0].trim();
            if (!mStart && !mEnd) continue;

            if (weekObj.isLast) {
                if (mEnd >= weekObj.isoStart) {
                    res.push(m);
                }
            } else {
                if (mStart <= weekObj.isoEnd && mEnd >= weekObj.isoStart) {
                    res.push(m);
                }
            }
        }
        return res;
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        clip: true

        ColumnLayout {
            width: parent.width - 40
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20

            Item { height: 8 } // Spacer

            // ==========================================
            // Top Header Banner
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                height: 88
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20

                    ColumnLayout {
                        spacing: 3
                        Text {
                            text: "DevOps Overview"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                        Text {
                            text: "Project: " + ((backend && backend.stats && backend.stats.project_name) ? backend.stats.project_name : "Unknown") + "  •  Last Synced: " + ((backend && backend.stats && backend.stats.last_synced) ? backend.stats.last_synced : "Never")
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Refresh Button
                    Button {
                        text: "↻ Refresh"
                        enabled: backend ? !backend.isBusy : false
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: "Reload dashboard stats and metrics from local database"
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

                    // Live Status Badge
                    Rectangle {
                        height: 34
                        implicitWidth: statusBadgeRow.implicitWidth + 24
                        radius: 17
                        color: (backend && backend.isBusy) ? Qt.rgba(210/255, 153/255, 34/255, 0.15) : Qt.rgba(63/255, 185/255, 80/255, 0.12)
                        border.color: (backend && backend.isBusy) ? "#d29922" : "#3fb950"
                        border.width: 1

                        Row {
                            id: statusBadgeRow
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: (backend && backend.isBusy) ? "#d29922" : "#3fb950"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: (backend && backend.isBusy) ? backend.statusMessage : "Database Ready"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: (backend && backend.isBusy) ? "#d29922" : "#3fb950"
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Main Stat Cards Grid (Interactive Cards)
            // ==========================================
            GridLayout {
                Layout.fillWidth: true
                columns: parent.width > 1000 ? 3 : (parent.width > 680 ? 2 : 1)
                rowSpacing: 18
                columnSpacing: 18

                // Card 1: Repositories & Pull Requests (Integrated)
                StatCard {
                    Layout.fillWidth: true
                    icon: "📁"
                    title: "Repositories & Pull Requests"
                    showRepoPrCombined: true
                    value: ((backend && backend.stats && backend.stats.repos_count) ? backend.stats.repos_count : 0) + " Repos"
                    openCount: (backend && backend.stats && backend.stats.prs_open_count !== undefined) ? backend.stats.prs_open_count : 0
                    closedCount: (backend && backend.stats && backend.stats.prs_completed_count !== undefined) ? backend.stats.prs_completed_count : 0
                    abandonedCount: (backend && backend.stats && backend.stats.prs_abandoned_count !== undefined) ? backend.stats.prs_abandoned_count : 0
                    status: (backend && backend.stats && (backend.stats.pending_repos_count > 0 || backend.stats.prs_open_count > 0)) ? "pending" : "clean"
                    badgeText: {
                        if (backend && backend.stats && backend.stats.pending_repos_count > 0) {
                            return backend.stats.pending_repos_count + " REPOS PENDING";
                        } else if (backend && backend.stats && backend.stats.prs_open_count > 0) {
                            return backend.stats.prs_open_count + " PRs OPEN";
                        }
                        return "ALL UP TO DATE";
                    }
                    subtitle: {
                        if (!backend || !backend.stats) return "Loading repositories and pull requests...";
                        var rCount = backend.stats.repos_count || 0;
                        var oPrs = backend.stats.prs_open_count || 0;
                        var totPrs = backend.stats.prs_count || 0;
                        return rCount + " repositories · " + oPrs + " open PRs awaiting merge (" + totPrs + " total) • Click to explore";
                    }
                    clickable: true
                    onClicked: {
                        if (typeof window !== "undefined" && window.navigateToRepos) {
                            window.navigateToRepos("ALL");
                        } else if (typeof window !== "undefined") {
                            window.currentTabIndex = 1;
                        }
                    }
                    onOpenPillClicked: {
                        if (typeof window !== "undefined" && window.navigateToPullRequests) {
                            window.navigateToPullRequests("ACTIVE", true);
                        }
                    }
                    onClosedPillClicked: {
                        if (typeof window !== "undefined" && window.navigateToPullRequests) {
                            window.navigateToPullRequests("COMPLETED", true);
                        }
                    }
                    onAbandonedPillClicked: {
                        if (typeof window !== "undefined" && window.navigateToPullRequests) {
                            window.navigateToPullRequests("ABANDONED", true);
                        }
                    }
                }

                // Card 2: Latest Stable Tag (with Pending Release info)
                StatCard {
                    Layout.fillWidth: true
                    icon: "🛡️"
                    title: "Latest Stable Tag"
                    value: ((backend && backend.stats && backend.stats.latest_stable_tag) ? backend.stats.latest_stable_tag : "-")
                    valuePixelSize: 24
                    status: (backend && backend.stats && backend.stats.untagged_prs_repos_count > 0) ? "pending" : "clean"
                    badgeText: (backend && backend.stats && backend.stats.untagged_prs_repos_count > 0) ? (backend.stats.untagged_prs_repos_count + " RELEASES PENDING") : "VERIFIED STABLE"
                    subtitle: {
                        if (!backend || !backend.stats) return "Click to view tags";
                        var repo = backend.stats.latest_stable_repo || "";
                        var dt = backend.stats.latest_stable_date ? (" • " + backend.stats.latest_stable_date) : "";
                        var untagged = backend.stats.untagged_prs_repos_count || 0;
                        if (repo) {
                            return repo + dt + (untagged > 0 ? (" • " + untagged + " repos pending release") : " • Verified Stable");
                        }
                        return "No stable tags cached" + (untagged > 0 ? (" • " + untagged + " repos pending release") : " • Click to view");
                    }
                    clickable: true
                    onClicked: {
                        if (typeof window !== "undefined" && window.navigateToRepos) {
                            window.navigateToRepos("ALL");
                        } else if (typeof window !== "undefined") {
                            window.currentTabIndex = 1;
                        }
                    }
                }

                // Card 3: Latest Unstable Tag (with Pending Release info)
                StatCard {
                    Layout.fillWidth: true
                    icon: "⚡"
                    title: "Latest Unstable Tag"
                    value: ((backend && backend.stats && backend.stats.latest_unstable_tag) ? backend.stats.latest_unstable_tag : "-")
                    valuePixelSize: 24
                    status: (backend && backend.stats && (backend.stats.untagged_prs_repos_count > 0 || backend.stats.pending_repos_count > 0)) ? "pending" : "clean"
                    badgeText: {
                        if (backend && backend.stats && backend.stats.untagged_prs_repos_count > 0) {
                            return backend.stats.untagged_prs_repos_count + " PENDING RELEASES";
                        } else if (backend && backend.stats && backend.stats.pending_repos_count > 0) {
                            return backend.stats.pending_repos_count + " PENDING CHANGES";
                        }
                        return "NO RELEASES PENDING";
                    }
                    subtitle: {
                        if (!backend || !backend.stats) return "Click to view tags";
                        var repo = backend.stats.latest_unstable_repo || "";
                        var dt = backend.stats.latest_unstable_date ? (" • " + backend.stats.latest_unstable_date) : "";
                        var untagged = backend.stats.untagged_prs_repos_count || 0;
                        if (repo) {
                            return repo + dt + (untagged > 0 ? (" • " + untagged + " untagged repos pending release") : " • Click to view");
                        }
                        return "No unstable tags cached" + (untagged > 0 ? (" • " + untagged + " untagged repos pending release") : " • Click to view");
                    }
                    clickable: true
                    onClicked: {
                        if (typeof window !== "undefined" && window.navigateToRepos) {
                            if (backend && backend.stats && backend.stats.untagged_prs_repos_count > 0) {
                                window.navigateToRepos("🏷️ PENDING PRs");
                            } else {
                                window.navigateToRepos("ALL");
                            }
                        } else if (typeof window !== "undefined") {
                            window.currentTabIndex = 1;
                        }
                    }
                }
            }

            // ==========================================
            // Coming Milestones Timeline (Gantt-Style View)
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: comingMilestonesCol.implicitHeight + 36
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: comingMilestonesCol
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "🚩"
                            font.pixelSize: 18
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true

                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "Coming Milestones Timeline"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Rectangle {
                                    implicitHeight: 20
                                    implicitWidth: comingCountText.implicitWidth + 12
                                    radius: 10
                                    color: (backend && backend.comingMilestones && backend.comingMilestones.length > 0) ? Qt.rgba(210/255, 153/255, 34/255, 0.18) : "#21262d"
                                    border.color: (backend && backend.comingMilestones && backend.comingMilestones.length > 0) ? "#d29922" : "#30363d"

                                    Text {
                                        id: comingCountText
                                        anchors.centerIn: parent
                                        text: ((backend && backend.comingMilestones) ? backend.comingMilestones.length : 0) + " Upcoming"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: (backend && backend.comingMilestones && backend.comingMilestones.length > 0) ? "#d29922" : "#8b949e"
                                    }
                                }
                            }

                            Text {
                                text: "Gantt timeline of scheduled delivery milestones by category along weekly timeline"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }

                        Button {
                            text: "⚙ Manage Milestones"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#58a6ff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 28
                                implicitWidth: 140
                                radius: 5
                                color: parent.hovered ? "#30363d" : "#21262d"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (typeof window !== "undefined" && window.openMilestonesManager) {
                                    window.openMilestonesManager();
                                }
                            }
                        }
                    }

                    // Gantt Table Container
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: ganttCol.implicitHeight + 2
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1
                        clip: true

                        ColumnLayout {
                            id: ganttCol
                            anchors.fill: parent
                            spacing: 0

                            // 1. Time Axis Header Row
                            RowLayout {
                                Layout.fillWidth: true
                                implicitHeight: 38
                                spacing: 0

                                // Left Type Header
                                Rectangle {
                                    Layout.preferredWidth: 140
                                    Layout.fillHeight: true
                                    color: "#161b22"
                                    border.color: "#30363d"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "TYPE / CATEGORY"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.5
                                        color: "#8b949e"
                                    }
                                }

                                // Timeline Week Columns
                                Repeater {
                                    model: root.getGanttWeeks()

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        color: modelData.isCurrent ? Qt.rgba(210/255, 153/255, 34/255, 0.12) : "#161b22"
                                        border.color: modelData.isCurrent ? "#d29922" : "#30363d"
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1

                                            Text {
                                                text: modelData.title
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: modelData.isCurrent ? "#d29922" : (modelData.index === 1 ? "#58a6ff" : "#f0f6fc")
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }

                                            Text {
                                                text: modelData.range
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 9
                                                color: modelData.isCurrent ? "#e3b341" : "#8b949e"
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. Rows per Type (Category)
                            Repeater {
                                model: root.getGanttRows()

                                delegate: RowLayout {
                                    id: rowLayoutItem
                                    Layout.fillWidth: true
                                    implicitHeight: Math.max(38, rowTrackCol.implicitHeight + 8)
                                    spacing: 0

                                    readonly property var categoryData: modelData

                                    // Left Type / Category Cell
                                    Rectangle {
                                        Layout.preferredWidth: 140
                                        Layout.fillHeight: true
                                        color: "#0d1117"
                                        border.color: "#21262d"
                                        border.width: 1

                                        // Left color indicator bar
                                        Rectangle {
                                            width: 3
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            color: categoryData.category_color || "#58a6ff"
                                        }

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                text: categoryData.category_icon || "🚩"
                                                font.pixelSize: 11
                                            }

                                            Text {
                                                text: categoryData.category_name || "General"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: categoryData.category_color || "#f0f6fc"
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: 90
                                            }
                                        }
                                    }

                                    // Week Track Grid Cells
                                    RowLayout {
                                        id: rowTrackCol
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 0

                                        Repeater {
                                            model: root.getGanttWeeks()

                                            delegate: Rectangle {
                                                id: cellRect
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                implicitHeight: Math.max(38, chipsCol.implicitHeight + 8)
                                                color: modelData.isCurrent ? Qt.rgba(210/255, 153/255, 34/255, 0.04) : "transparent"
                                                border.color: "#21262d"
                                                border.width: 1

                                                readonly property var currentWeekObj: modelData
                                                readonly property var cellMilestones: root.getMilestonesForWeek(categoryData.milestones, currentWeekObj)

                                                ColumnLayout {
                                                    id: chipsCol
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    spacing: 3

                                                    Repeater {
                                                        model: cellRect.cellMilestones

                                                        delegate: Rectangle {
                                                            Layout.fillWidth: true
                                                            implicitHeight: 24
                                                            radius: 4
                                                            color: msChipMa.containsMouse ? Qt.darker(modelData.category_bg_color || "#1f242c", 1.2) : (modelData.category_bg_color || "#13233a")
                                                            border.color: msChipMa.containsMouse ? "#ffffff" : (modelData.category_color || "#58a6ff")
                                                            border.width: 1
                                                            clip: true

                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 6
                                                                anchors.rightMargin: 6
                                                                spacing: 4

                                                                Text {
                                                                    text: modelData.name || ""
                                                                    font.family: "Segoe UI, sans-serif"
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.Bold
                                                                    color: modelData.category_color || "#f0f6fc"
                                                                    elide: Text.ElideRight
                                                                    Layout.fillWidth: true
                                                                }

                                                                Text {
                                                                    text: modelData.relative_label || modelData.target_date || ""
                                                                    font.family: "Segoe UI, sans-serif"
                                                                    font.pixelSize: 8
                                                                    font.weight: Font.DemiBold
                                                                    color: "#8b949e"
                                                                }
                                                            }

                                                            ToolTip.visible: msChipMa.containsMouse
                                                            ToolTip.text: {
                                                                var t = modelData.name + " (" + (modelData.category_name || "Milestone") + ")\n";
                                                                var dates = modelData.start_date && modelData.end_date && modelData.start_date !== modelData.end_date ? (modelData.start_date + " → " + modelData.end_date) : (modelData.target_date || modelData.start_date || "");
                                                                if (dates) t += "Date: " + dates + "\n";
                                                                if (modelData.relative_label) t += "Timeline: " + modelData.relative_label + "\n";
                                                                if (modelData.team) t += "Team: " + modelData.team + "\n";
                                                                if (modelData.description) t += "Description: " + modelData.description;
                                                                return t.trim();
                                                            }

                                                            MouseArea {
                                                                id: msChipMa
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
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Weekly Overviews: Last Week Activities & Current Week Planned
            // ==========================================
            GridLayout {
                id: weeklyOverviewsGrid
                Layout.fillWidth: true
                columns: parent.width > 900 ? 2 : 1
                rowSpacing: 18
                columnSpacing: 18

                property real maxCardHeight: Math.max(lastWeekCol.implicitHeight, curWeekCol.implicitHeight) + 36

                // ----------------------------------------------------
                // Card A: Last Week Activities Overview
                // ----------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: weeklyOverviewsGrid.columns === 2 ? weeklyOverviewsGrid.maxCardHeight : (lastWeekCol.implicitHeight + 36)
                    implicitHeight: weeklyOverviewsGrid.columns === 2 ? weeklyOverviewsGrid.maxCardHeight : (lastWeekCol.implicitHeight + 36)
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: lastWeekCol
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "🕒"
                                font.pixelSize: 18
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true

                                Text {
                                    text: "Last Week Activities"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Text {
                                    text: (backend && backend.lastWeekActivity && backend.lastWeekActivity.range_label) ? backend.lastWeekActivity.range_label : "Past week overview"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                }
                            }

                            // Sprint Badge
                            Rectangle {
                                implicitHeight: 22
                                implicitWidth: lastWeekSprintText.implicitWidth + 14
                                radius: 11
                                color: "#21262d"
                                border.color: "#30363d"

                                Text {
                                    id: lastWeekSprintText
                                    anchors.centerIn: parent
                                    text: (backend && backend.lastWeekActivity && backend.lastWeekActivity.sprint_name) ? backend.lastWeekActivity.sprint_name : "Previous"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                }
                            }
                        }

                        // Milestones Section (if any)
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: (backend && backend.lastWeekActivity && backend.lastWeekActivity.milestones && backend.lastWeekActivity.milestones.length > 0)
                            spacing: 4

                            RowLayout {
                                spacing: 4
                                Text {
                                    text: "🚩"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: "Milestones in Sprint:"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#d29922"
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: (backend && backend.lastWeekActivity && backend.lastWeekActivity.milestones) ? backend.lastWeekActivity.milestones : []

                                    delegate: Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: lastMsRow.implicitWidth + 14
                                        radius: 11
                                        color: modelData.category_bg_color || "#272115"
                                        border.color: modelData.category_color || "#d29922"
                                        border.width: 1

                                        RowLayout {
                                            id: lastMsRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: modelData.category_icon || "🚩"
                                                font.pixelSize: 10
                                            }
                                            Text {
                                                text: modelData.name || ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: modelData.category_color || "#f0f6fc"
                                            }
                                            Text {
                                                text: modelData.target_date ? "(" + modelData.target_date + ")" : ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                color: "#8b949e"
                                                visible: !!modelData.target_date
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Metrics Pill Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Metric 1: Closed PRs
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 6
                                color: "#0d1117"
                                border.color: "#30363d"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        text: ((backend && backend.lastWeekActivity && backend.lastWeekActivity.closed_prs_count !== undefined) ? backend.lastWeekActivity.closed_prs_count : 0).toString()
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#238636"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Text {
                                        text: "PRs Merged"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        color: "#8b949e"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }

                            // Metric 2: Completed Work Items
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 6
                                color: "#0d1117"
                                border.color: "#30363d"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        text: ((backend && backend.lastWeekActivity && backend.lastWeekActivity.completed_wis_count !== undefined) ? backend.lastWeekActivity.completed_wis_count : 0).toString()
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Text {
                                        text: "WIs Resolved"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        color: "#8b949e"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }

                            // Metric 3: Release Tags
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 6
                                color: "#0d1117"
                                border.color: "#30363d"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        text: ((backend && backend.lastWeekActivity && backend.lastWeekActivity.tags_count !== undefined) ? backend.lastWeekActivity.tags_count : 0).toString()
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#bc8cff"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Text {
                                        text: "Releases Tagged"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        color: "#8b949e"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }
                        }

                        // Recent Activity Items List (Top highlights: Stories, Bugs & PRs)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "Activity Highlights (Stories & Bugs):"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: "#8b949e"
                            }

                            // Completed Work Items previews (Stories & Bugs with [xx_xxx] priority first)
                            Repeater {
                                model: (backend && backend.lastWeekActivity && backend.lastWeekActivity.completed_wis) ? backend.lastWeekActivity.completed_wis.slice(0, 8) : []

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 5
                                    color: wiMa.containsMouse ? "#21262d" : "#0d1117"
                                    border.color: (modelData.bracket_tag || modelData.is_prio1) ? "#238636" : "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 6

                                        // Type badge icon
                                        Text {
                                            text: modelData.is_bug ? "🐞" : (modelData.is_story ? "📘" : "✓")
                                            font.pixelSize: 11
                                        }

                                        // Bracket tag pill if any (e.g. [OI_01], [MP_02], [SCN_01])
                                        Rectangle {
                                            visible: !!modelData.bracket_tag
                                            implicitHeight: 18
                                            implicitWidth: bracketPillText.implicitWidth + 8
                                            radius: 3
                                            color: Qt.rgba(35/255, 134/255, 54/255, 0.25)
                                            border.color: "#238636"

                                            Text {
                                                id: bracketPillText
                                                anchors.centerIn: parent
                                                text: modelData.bracket_tag || ""
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#3fb950"
                                            }
                                        }

                                        Text {
                                            text: "#" + modelData.id
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
                                        }

                                        Text {
                                            text: modelData.title
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#f0f6fc"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: modelData.assigned_to || "Unassigned"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: wiMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (typeof window !== "undefined" && window.navigateToWorkItem) {
                                                window.navigateToWorkItem(modelData.id);
                                            }
                                        }
                                    }
                                }
                            }

                            // Closed PRs previews
                            Repeater {
                                model: (backend && backend.lastWeekActivity && backend.lastWeekActivity.closed_prs) ? backend.lastWeekActivity.closed_prs.slice(0, 6) : []

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 5
                                    color: itemMa.containsMouse ? "#21262d" : "#0d1117"
                                    border.color: "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: "🔀 !" + modelData.id
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#3fb950"
                                        }

                                        Text {
                                            text: modelData.title
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#f0f6fc"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: modelData.repo_name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: itemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (typeof window !== "undefined" && window.navigateToPullRequests) {
                                                window.navigateToPullRequests(modelData.repo_name, false);
                                            }
                                        }
                                    }
                                }
                            }

                            // Empty placeholder when no activities
                            Text {
                                visible: (!backend || !backend.lastWeekActivity || !backend.lastWeekActivity.total_count)
                                text: "No pull requests merged or work items closed in last week's interval."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                                Layout.topMargin: 4
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        // Footer Action Button
                        Button {
                            Layout.fillWidth: true
                            text: "📊 Open Last Week Sprint Report ➔"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#58a6ff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 30
                                radius: 5
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (typeof window !== "undefined" && window.navigateToSprint) {
                                    var sp = (backend && backend.lastWeekActivity && backend.lastWeekActivity.sprint_name) ? backend.lastWeekActivity.sprint_name : "";
                                    window.navigateToSprint(sp);
                                }
                            }
                        }
                    }
                }

                // ----------------------------------------------------
                // Card B: Current Week Planned Activities Overview
                // ----------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: weeklyOverviewsGrid.columns === 2 ? weeklyOverviewsGrid.maxCardHeight : (curWeekCol.implicitHeight + 36)
                    implicitHeight: weeklyOverviewsGrid.columns === 2 ? weeklyOverviewsGrid.maxCardHeight : (curWeekCol.implicitHeight + 36)
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: curWeekCol
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "🎯"
                                font.pixelSize: 18
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true

                                Text {
                                    text: "Current Week Planned"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Text {
                                    text: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.range_label) ? backend.currentWeekPlanned.range_label : "Active week targets"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                }
                            }

                            // Active Sprint Badge (with live indicator dot)
                            Rectangle {
                                implicitHeight: 22
                                implicitWidth: curSprintBadgeRow.implicitWidth + 14
                                radius: 11
                                color: Qt.rgba(63/255, 185/255, 80/255, 0.15)
                                border.color: "#3fb950"

                                Row {
                                    id: curSprintBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: "#3fb950"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.sprint_name) ? backend.currentWeekPlanned.sprint_name : "Current"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#3fb950"
                                    }
                                }
                            }
                        }

                        // Milestones Section (if any)
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.milestones && backend.currentWeekPlanned.milestones.length > 0)
                            spacing: 4

                            RowLayout {
                                spacing: 4
                                Text {
                                    text: "🚩"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: "Active Milestones:"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#58a6ff"
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.milestones) ? backend.currentWeekPlanned.milestones : []

                                    delegate: Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: curMsRow.implicitWidth + 14
                                        radius: 11
                                        color: modelData.category_bg_color || "#13233a"
                                        border.color: modelData.category_color || "#58a6ff"
                                        border.width: 1

                                        RowLayout {
                                            id: curMsRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: modelData.category_icon || "🎯"
                                                font.pixelSize: 10
                                            }
                                            Text {
                                                text: modelData.name || ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: modelData.category_color || "#f0f6fc"
                                            }
                                            Text {
                                                text: modelData.target_date ? "(" + modelData.target_date + ")" : ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                color: "#8b949e"
                                                visible: !!modelData.target_date
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Metrics Pill Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Metric 1: Planned Work Items
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 6
                                color: "#0d1117"
                                border.color: "#30363d"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        text: ((backend && backend.currentWeekPlanned && backend.currentWeekPlanned.planned_wis_count !== undefined) ? backend.currentWeekPlanned.planned_wis_count : 0).toString()
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Text {
                                        text: "Planned Tasks"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        color: "#8b949e"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }

                            // Metric 2: Due This Week
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 6
                                color: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.due_this_week_count > 0) ? Qt.rgba(240/255, 136/255, 62/255, 0.12) : "#0d1117"
                                border.color: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.due_this_week_count > 0) ? "#f0883e" : "#30363d"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        text: ((backend && backend.currentWeekPlanned && backend.currentWeekPlanned.due_this_week_count !== undefined) ? backend.currentWeekPlanned.due_this_week_count : 0).toString()
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.due_this_week_count > 0) ? "#f0883e" : "#8b949e"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Text {
                                        text: "Due This Week"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        color: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.due_this_week_count > 0) ? "#f0883e" : "#8b949e"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }

                            // Metric 3: Active PRs
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 6
                                color: "#0d1117"
                                border.color: "#30363d"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        text: ((backend && backend.currentWeekPlanned && backend.currentWeekPlanned.active_prs_count !== undefined) ? backend.currentWeekPlanned.active_prs_count : 0).toString()
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: "#bc8cff"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Text {
                                        text: "Active PRs"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        color: "#8b949e"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }
                        }

                        // Planned Activities List (Top items: Stories & Bugs with [xx_xxx] priority first)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "Targeted Activities (Stories & Bugs):"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: "#8b949e"
                            }

                            // Planned Work Items
                            Repeater {
                                model: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.planned_wis) ? backend.currentWeekPlanned.planned_wis.slice(0, 8) : []

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 5
                                    color: curWiMa.containsMouse ? "#21262d" : "#0d1117"
                                    border.color: (modelData.urgency_status === "due_this_week") ? "#f0883e" : ((modelData.bracket_tag || modelData.is_prio1) ? "#238636" : "#30363d")

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 6

                                        // Type badge icon
                                        Text {
                                            text: modelData.is_bug ? "🐞" : (modelData.is_story ? "📘" : "📋")
                                            font.pixelSize: 11
                                        }

                                        // Bracket tag pill if any (e.g. [OI_01], [MP_02], [SCN_01])
                                        Rectangle {
                                            visible: !!modelData.bracket_tag
                                            implicitHeight: 18
                                            implicitWidth: curBracketPillText.implicitWidth + 8
                                            radius: 3
                                            color: Qt.rgba(35/255, 134/255, 54/255, 0.25)
                                            border.color: "#238636"

                                            Text {
                                                id: curBracketPillText
                                                anchors.centerIn: parent
                                                text: modelData.bracket_tag || ""
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#3fb950"
                                            }
                                        }

                                        Text {
                                            text: "#" + modelData.id
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: (modelData.urgency_status === "due_this_week") ? "#f0883e" : "#58a6ff"
                                        }

                                        Text {
                                            text: modelData.title
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#f0f6fc"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        // Deadline / Urgency Pill if due this week
                                        Rectangle {
                                            visible: modelData.urgency_status === "due_this_week"
                                            implicitHeight: 18
                                            implicitWidth: duePillText.implicitWidth + 8
                                            radius: 3
                                            color: Qt.rgba(240/255, 136/255, 62/255, 0.2)
                                            border.color: "#f0883e"

                                            Text {
                                                id: duePillText
                                                anchors.centerIn: parent
                                                text: "DUE THIS WEEK"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 8
                                                font.weight: Font.Bold
                                                color: "#f0883e"
                                            }
                                        }

                                        Text {
                                            text: modelData.assigned_to || "Unassigned"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: curWiMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (typeof window !== "undefined" && window.navigateToWorkItem) {
                                                window.navigateToWorkItem(modelData.id);
                                            }
                                        }
                                    }
                                }
                            }

                            // Active PRs
                            Repeater {
                                model: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.active_prs) ? backend.currentWeekPlanned.active_prs.slice(0, 6) : []

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 5
                                    color: curPrMa.containsMouse ? "#21262d" : "#0d1117"
                                    border.color: "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: "🔀 !" + modelData.id
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#bc8cff"
                                        }

                                        Text {
                                            text: modelData.title
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#f0f6fc"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: modelData.repo_name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: curPrMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (typeof window !== "undefined" && window.navigateToPullRequests) {
                                                window.navigateToPullRequests("ACTIVE", true);
                                            }
                                        }
                                    }
                                }
                            }

                            // Empty placeholder when no planned items
                            Text {
                                visible: (!backend || !backend.currentWeekPlanned || !backend.currentWeekPlanned.total_count)
                                text: "No work items or active pull requests assigned to this week's sprint."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                                Layout.topMargin: 4
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        // Footer Action Button
                        Button {
                            Layout.fillWidth: true
                            text: "🚀 Explore Current Sprint Workload ➔"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#58a6ff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 30
                                radius: 5
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (typeof window !== "undefined" && window.navigateToWorkloadSprint) {
                                    var sp = (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.sprint_name) ? backend.currentWeekPlanned.sprint_name : "";
                                    window.navigateToWorkloadSprint("", sp);
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Quick Navigation Bar
            // ==========================================
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
                        text: "Quick Jump:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: "#8b949e"
                    }

                    Button {
                        text: "📁 Repositories (" + ((backend && backend.stats) ? backend.stats.repos_count : 0) + ")"
                        font.pixelSize: 11
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#58a6ff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 28
                            implicitWidth: 150
                            radius: 4
                            color: parent.hovered ? "#30363d" : "#0d1117"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (typeof window !== "undefined" && window.navigateToRepos) window.navigateToRepos("ALL");
                            else window.currentTabIndex = 1;
                        }
                    }

                    Button {
                        text: "⚠️ Pending (" + ((backend && backend.stats) ? backend.stats.pending_repos_count : 0) + ")"
                        font.pixelSize: 11
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#d29922"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 28
                            implicitWidth: 130
                            radius: 4
                            color: parent.hovered ? "#30363d" : "#0d1117"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (typeof window !== "undefined" && window.navigateToRepos) window.navigateToRepos("⚠️ PENDING");
                            else window.currentTabIndex = 1;
                        }
                    }

                    Button {
                        text: "🔀 Pull Requests (" + ((backend && backend.stats) ? backend.stats.prs_count : 0) + ")"
                        font.pixelSize: 11
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#a371f7"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 28
                            implicitWidth: 150
                            radius: 4
                            color: parent.hovered ? "#30363d" : "#0d1117"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (typeof window !== "undefined" && window.navigateToPullRequests) window.navigateToPullRequests();
                            else window.currentTabIndex = 2;
                        }
                    }

                    Button {
                        text: "📑 Reports & Analytics"
                        font.pixelSize: 11
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#f0f6fc"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 28
                            implicitWidth: 150
                            radius: 4
                            color: parent.hovered ? "#30363d" : "#0d1117"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (typeof window !== "undefined") window.currentTabIndex = 4;
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Item { height: 24 } // Bottom spacer
        }
    }
}
