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
            // Main Stat Cards Grid (6 Interactive Cards)
            // ==========================================
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 18
                columnSpacing: 18

                // Card 1: Repositories
                StatCard {
                    Layout.fillWidth: true
                    icon: "📁"
                    title: "Repositories"
                    value: ((backend && backend.stats && backend.stats.repos_count) ? backend.stats.repos_count : 0).toString()
                    status: (backend && backend.stats && backend.stats.pending_repos_count > 0) ? "pending" : "clean"
                    badgeText: (backend && backend.stats && backend.stats.pending_repos_count > 0) ? (backend.stats.pending_repos_count + " PENDING") : "NOTHING PENDING"
                    subtitle: (backend && backend.stats && backend.stats.pending_repos_count > 0) ? (backend.stats.pending_repos_count + " have pending changes • Click to explore") : "All repositories up to date • Click to explore"
                    clickable: true
                    onClicked: {
                        if (typeof window !== "undefined" && window.navigateToRepos) {
                            window.navigateToRepos("ALL");
                        } else if (typeof window !== "undefined") {
                            window.currentTabIndex = 1;
                        }
                    }
                }

                // Card 2: Pending Releases (Highlight Attention)
                StatCard {
                    Layout.fillWidth: true
                    icon: "⚠️"
                    title: "Pending Releases"
                    value: ((backend && backend.stats && backend.stats.pending_repos_count !== undefined) ? backend.stats.pending_repos_count : 0).toString()
                    status: (backend && backend.stats && backend.stats.pending_repos_count > 0) ? "pending" : "clean"
                    badgeText: (backend && backend.stats && backend.stats.pending_repos_count > 0) ? "PENDING CHANGES" : "NOTHING PENDING"
                    subtitle: (backend && backend.stats && backend.stats.pending_repos_count > 0) ? (backend.stats.pending_repos_count + " repositories require release • Click to filter") : "Zero pending changes across all repos"
                    clickable: true
                    onClicked: {
                        if (typeof window !== "undefined" && window.navigateToRepos) {
                            window.navigateToRepos("⚠️ PENDING");
                        } else if (typeof window !== "undefined") {
                            window.currentTabIndex = 1;
                        }
                    }
                }

                // Card 3: Latest Stable Tag
                StatCard {
                    Layout.fillWidth: true
                    icon: "🛡️"
                    title: "Latest Stable Tag"
                    value: ((backend && backend.stats && backend.stats.latest_stable_tag) ? backend.stats.latest_stable_tag : "-")
                    valuePixelSize: 24
                    status: "clean"
                    badgeText: "NOTHING PENDING"
                    subtitle: {
                        if (backend && backend.stats && backend.stats.latest_stable_repo) {
                            return backend.stats.latest_stable_repo + (backend.stats.latest_stable_date ? (" • " + backend.stats.latest_stable_date) : "") + " • Verified Stable";
                        }
                        return "No stable tags cached • Click to view";
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

                // Card 4: Latest Unstable Tag
                StatCard {
                    Layout.fillWidth: true
                    icon: "⚡"
                    title: "Latest Unstable Tag"
                    value: ((backend && backend.stats && backend.stats.latest_unstable_tag) ? backend.stats.latest_unstable_tag : "-")
                    valuePixelSize: 24
                    status: (backend && backend.stats && backend.stats.pending_repos_count > 0) ? "pending" : "clean"
                    badgeText: (backend && backend.stats && backend.stats.pending_repos_count > 0) ? "PENDING CHANGES" : "NOTHING PENDING"
                    subtitle: {
                        if (backend && backend.stats && backend.stats.latest_unstable_repo) {
                            return backend.stats.latest_unstable_repo + (backend.stats.latest_unstable_date ? (" • " + backend.stats.latest_unstable_date) : "") + " • Click to view";
                        }
                        return "No unstable tags cached • Click to view";
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

                // Card 5: Pull Requests (Open / Closed / Abandoned Breakdown)
                StatCard {
                    Layout.fillWidth: true
                    icon: "🔀"
                    title: "Pull Requests"
                    showPrBreakdown: true
                    openCount: (backend && backend.stats && backend.stats.prs_open_count !== undefined) ? backend.stats.prs_open_count : 0
                    closedCount: (backend && backend.stats && backend.stats.prs_completed_count !== undefined) ? backend.stats.prs_completed_count : 0
                    abandonedCount: (backend && backend.stats && backend.stats.prs_abandoned_count !== undefined) ? backend.stats.prs_abandoned_count : 0
                    status: (backend && backend.stats && backend.stats.prs_open_count > 0) ? "pending" : "clean"
                    badgeText: (backend && backend.stats && backend.stats.prs_open_count > 0) ? (backend.stats.prs_open_count + " PENDING") : "NOTHING PENDING"
                    subtitle: {
                        if (!backend || !backend.stats) return "Click to view pull requests";
                        if (backend.stats.prs_open_count > 0) {
                            return backend.stats.prs_open_count + " open PR" + (backend.stats.prs_open_count > 1 ? "s" : "") + " awaiting merge • Click to view";
                        }
                        return "All " + backend.stats.prs_count + " pull requests completed • Click to view";
                    }
                    clickable: true
                    onClicked: {
                        if (typeof window !== "undefined" && window.navigateToPullRequests) {
                            window.navigateToPullRequests();
                        } else if (typeof window !== "undefined") {
                            window.currentTabIndex = 2;
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

                // Card 6: Active Work Items
                StatCard {
                    Layout.fillWidth: true
                    icon: "📋"
                    title: "Active Work Items"
                    value: ((backend && backend.stats && backend.stats.active_work_items_count !== undefined) ? backend.stats.active_work_items_count : 0).toString()
                    status: (backend && backend.stats && backend.stats.active_work_items_count > 0) ? "pending" : "clean"
                    badgeText: (backend && backend.stats && backend.stats.active_work_items_count > 0) ? (backend.stats.active_work_items_count + " ACTIVE") : "ALL RESOLVED"
                    subtitle: {
                        if (!backend || !backend.stats) return "Loading work items...";
                        var act = backend.stats.active_work_items_count || 0;
                        var cl = backend.stats.closed_work_items_count || 0;
                        var tot = backend.stats.work_items_count || 0;
                        if (act > 0) {
                            return act + " active / in progress · " + cl + " closed (" + tot + " total) • Click to view";
                        }
                        return "All " + tot + " work items closed / resolved • Nothing pending";
                    }
                    clickable: true
                    onClicked: {
                        if (typeof window !== "undefined") {
                            window.currentTabIndex = 3;
                        }
                    }
                }
            }

            // ==========================================
            // Weekly Overviews: Last Week Activities & Current Week Planned
            // ==========================================
            GridLayout {
                Layout.fillWidth: true
                columns: parent.width > 900 ? 2 : 1
                rowSpacing: 18
                columnSpacing: 18

                // ----------------------------------------------------
                // Card A: Last Week Activities Overview
                // ----------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: lastWeekCol.implicitHeight + 36
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: lastWeekCol
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 14

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

                        // Recent Activity Items List (Top highlights)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "Activity Highlights:"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: "#8b949e"
                            }

                            // Closed PRs previews
                            Repeater {
                                model: (backend && backend.lastWeekActivity && backend.lastWeekActivity.closed_prs) ? backend.lastWeekActivity.closed_prs.slice(0, 3) : []

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

                            // Completed Work Items previews
                            Repeater {
                                model: (backend && backend.lastWeekActivity && backend.lastWeekActivity.completed_wis) ? backend.lastWeekActivity.completed_wis.slice(0, 2) : []

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 5
                                    color: wiMa.containsMouse ? "#21262d" : "#0d1117"
                                    border.color: "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: "✓ #" + modelData.id
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
                    implicitHeight: curWeekCol.implicitHeight + 36
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: curWeekCol
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 14

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

                        // Planned Activities List (Top items)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "Targeted Activities:"
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
                                    border.color: (modelData.urgency_status === "due_this_week") ? "#f0883e" : "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

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
