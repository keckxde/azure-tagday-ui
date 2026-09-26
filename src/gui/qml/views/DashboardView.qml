import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root

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
            // Coming Milestones List Card (Starting Current Week)
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
                    spacing: 12

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
                                    text: "Coming Milestones"
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
                                text: "Target dates and delivery milestones scheduled starting from current week"
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

                    // Empty State
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 70
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        visible: !backend || !backend.comingMilestones || backend.comingMilestones.length === 0

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                text: "🚩"
                                font.pixelSize: 22
                                opacity: 0.6
                            }

                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: "No upcoming milestones scheduled starting current week"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: "#f0f6fc"
                                }
                                Text {
                                    text: "Click 'Manage Milestones' to create milestones or auto-detect from work item tags"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                }
                            }
                        }
                    }

                    // Milestones List (Repeater)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: backend && backend.comingMilestones && backend.comingMilestones.length > 0

                        Repeater {
                            model: (backend && backend.comingMilestones) ? backend.comingMilestones : []

                            delegate: Rectangle {
                                id: msItemRect
                                Layout.fillWidth: true
                                implicitHeight: msRowContent.implicitHeight + 16
                                radius: 6
                                color: msItemMa.containsMouse ? "#21262d" : "#0d1117"
                                border.color: msItemMa.containsMouse ? (modelData.category_color || "#58a6ff") : (modelData.is_current_week ? Qt.rgba(210/255, 153/255, 34/255, 0.4) : "#30363d")
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                // Left accent bar
                                Rectangle {
                                    width: 4
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    radius: 2
                                    color: modelData.category_color || (modelData.is_current_week ? "#d29922" : "#58a6ff")
                                }

                                RowLayout {
                                    id: msRowContent
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    anchors.topMargin: 8
                                    anchors.bottomMargin: 8
                                    spacing: 12

                                    // Category Pill
                                    Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: catRow.implicitWidth + 14
                                        radius: 12
                                        color: modelData.category_bg_color || "#1f242c"
                                        border.color: modelData.category_color || "#8b949e"
                                        border.width: 1

                                        RowLayout {
                                            id: catRow
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Text {
                                                text: modelData.category_icon || "🚩"
                                                font.pixelSize: 11
                                            }

                                            Text {
                                                text: modelData.category_name || "Milestone"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: modelData.category_color || "#f0f6fc"
                                            }
                                        }
                                    }

                                    // Milestone Title and Description
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: modelData.name || ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                            }

                                            // Team badge (if present)
                                            Rectangle {
                                                visible: !!modelData.team
                                                implicitHeight: 18
                                                implicitWidth: teamTxt.implicitWidth + 10
                                                radius: 4
                                                color: "#21262d"
                                                border.color: "#30363d"

                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 3
                                                    Text { text: "👥"; font.pixelSize: 9 }
                                                    Text {
                                                        id: teamTxt
                                                        text: modelData.team || ""
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 9
                                                        font.weight: Font.DemiBold
                                                        color: "#8b949e"
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            text: modelData.description || ""
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#8b949e"
                                            visible: !!modelData.description
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    // Date Range / Target Date
                                    RowLayout {
                                        spacing: 6

                                        Text {
                                            text: "📅"
                                            font.pixelSize: 11
                                            color: "#8b949e"
                                        }

                                        Text {
                                            text: {
                                                var s = modelData.start_date || "";
                                                var e = modelData.end_date || "";
                                                var t = modelData.target_date || "";
                                                if (s && e && s !== e) return s + " → " + e;
                                                return t || s || e;
                                            }
                                            font.family: "Consolas, 'Segoe UI', monospace"
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            color: "#c9d1d9"
                                        }
                                    }

                                    // Relative Label Badge (This week, Next week, Today, In Xd)
                                    Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: relLblText.implicitWidth + 14
                                        radius: 11
                                        color: {
                                            if (modelData.is_current_week || modelData.relative_label === "This week") return Qt.rgba(210/255, 153/255, 34/255, 0.2);
                                            if (modelData.relative_label === "Today") return Qt.rgba(63/255, 185/255, 80/255, 0.2);
                                            if (modelData.relative_label === "Next week") return Qt.rgba(88/255, 166/255, 255/255, 0.2);
                                            return Qt.rgba(163/255, 113/255, 247/255, 0.15);
                                        }
                                        border.color: {
                                            if (modelData.is_current_week || modelData.relative_label === "This week") return "#d29922";
                                            if (modelData.relative_label === "Today") return "#3fb950";
                                            if (modelData.relative_label === "Next week") return "#58a6ff";
                                            return "#a371f7";
                                        }
                                        border.width: 1

                                        Text {
                                            id: relLblText
                                            anchors.centerIn: parent
                                            text: modelData.relative_label || modelData.target_date || ""
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: {
                                                if (modelData.is_current_week || modelData.relative_label === "This week") return "#d29922";
                                                if (modelData.relative_label === "Today") return "#3fb950";
                                                if (modelData.relative_label === "Next week") return "#58a6ff";
                                                return "#a371f7";
                                            }
                                        }
                                    }

                                    // Chevron Arrow
                                    Text {
                                        text: "➔"
                                        font.pixelSize: 12
                                        color: msItemMa.containsMouse ? "#58a6ff" : "#484f58"
                                    }
                                }

                                MouseArea {
                                    id: msItemMa
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
                                model: (backend && backend.lastWeekActivity && backend.lastWeekActivity.completed_wis) ? backend.lastWeekActivity.completed_wis.slice(0, 3) : []

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
                                model: (backend && backend.lastWeekActivity && backend.lastWeekActivity.closed_prs) ? backend.lastWeekActivity.closed_prs.slice(0, 2) : []

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
                                model: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.planned_wis) ? backend.currentWeekPlanned.planned_wis.slice(0, 3) : []

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
                                model: (backend && backend.currentWeekPlanned && backend.currentWeekPlanned.active_prs) ? backend.currentWeekPlanned.active_prs.slice(0, 2) : []

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
