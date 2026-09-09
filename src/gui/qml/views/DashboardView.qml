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
