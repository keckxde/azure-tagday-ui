import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root

    property string selectedTimeframe: backend ? backend.teamMotivationTimeframe : "last_week"
    property string selectedCustomSprint: backend ? backend.teamMotivationCustomSprint : ""
    property string searchQuery: ""
    property var selectedMember: null
    property bool isProfileDrawerOpen: false
    property string copyToastMessage: ""
    property string activeTab: "overview" // "overview", "leaderboards", "roster", "badges"

    readonly property var motivationData: (backend && backend.teamMotivationData) ? backend.teamMotivationData : {}
    readonly property var teamSummary: motivationData && motivationData.team_summary ? motivationData.team_summary : {}
    readonly property var timeAnalytics: teamSummary && teamSummary.time_analytics ? teamSummary.time_analytics : null
    readonly property var podiumList: motivationData && motivationData.podium ? motivationData.podium : []
    readonly property var leaderboards: motivationData && motivationData.leaderboards ? motivationData.leaderboards : {}
    readonly property var membersList: motivationData && motivationData.members ? motivationData.members : []
    readonly property var top4To10List: {
        if (!membersList || membersList.length <= 3) return [];
        var result = [];
        var maxLen = Math.min(10, membersList.length);
        for (var i = 3; i < maxLen; i++) {
            var mem = membersList[i];
            if (mem && ((mem.score || 0) > 0 || root.selectedTimeframe === "all_time")) {
                result.push({
                    rank: i + 1,
                    member: mem
                });
            }
        }
        return result;
    }
    readonly property var allBadgesList: motivationData && motivationData.all_badges ? motivationData.all_badges : []
    readonly property var staleRadarList: motivationData && motivationData.stale_radar ? motivationData.stale_radar : []

    function setTimeframe(tf, sprintName) {
        root.selectedTimeframe = tf;
        root.selectedCustomSprint = sprintName || "";
        if (backend) {
            backend.set_team_motivation_timeframe(tf, root.selectedCustomSprint);
        }
    }

    function openMemberProfile(memberObj) {
        if (!memberObj) return;
        root.selectedMember = memberObj;
        if (typeof window !== "undefined" && typeof window.openRightSidebar === "function") {
            window.openRightSidebar("contributor_profile", memberObj.name, "Contributor & Gamification Profile", memberObj);
        } else {
            root.isProfileDrawerOpen = true;
        }
    }

    function copySummaryToClipboard() {
        if (backend) {
            var md = backend.get_team_motivation_markdown_summary();
            if (typeof backend.copy_to_clipboard === "function") {
                backend.copy_to_clipboard(md);
            } else if (typeof backend.copyToClipboard === "function") {
                backend.copyToClipboard(md);
            }
            root.copyToastMessage = "✅ Copied Sprint Retro Summary to Clipboard!";
            copyToastTimer.restart();
        }
    }

    Timer {
        id: copyToastTimer
        interval: 3000
        onTriggered: root.copyToastMessage = ""
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        clip: true

        ColumnLayout {
            width: Math.max(940, parent.width - 48)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20

            Item { height: 6 } // Top spacing

            // ==========================================
            // Hero Header & Motivational Pulse Banner
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headerCol.implicitHeight + 36
                radius: 10
                color: "#161b22"
                border.color: "#30363d"
                border.width: 1

                // Subtle Top Gradient Glow
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 3
                    radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#e3b341" }
                        GradientStop { position: 0.25; color: "#7ee787" }
                        GradientStop { position: 0.5; color: "#56d364" }
                        GradientStop { position: 0.75; color: "#a371f7" }
                        GradientStop { position: 1.0; color: "#58a6ff" }
                    }
                }

                ColumnLayout {
                    id: headerCol
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    // Top Row: Title, Motivation Pulse & Action Buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Trophy Icon & Title
                        Rectangle {
                            width: 44
                            height: 44
                            radius: 10
                            color: "#272115"
                            border.color: "#d29922"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "🏆"
                                font.pixelSize: 22
                            }
                        }

                        ColumnLayout {
                            spacing: 3
                            Text {
                                text: "Team Hall of Fame & Sprint Motivation"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 20
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Text {
                                text: motivationData && motivationData.range_label ? motivationData.range_label : "Sprint activity, PRs, commits, branches, builds & badges"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Motivational Quote Pill
                        Rectangle {
                            visible: motivationData && motivationData.motivational_pulse
                            implicitHeight: 32
                            implicitWidth: pulseRow.implicitWidth + 24
                            radius: 16
                            color: "#1f242c"
                            border.color: "#388bfd"
                            border.width: 1

                            RowLayout {
                                id: pulseRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: motivationData ? motivationData.motivational_pulse : ""
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#79c0ff"
                                }
                            }
                        }

                        // Preview Retro Summary in Sidebar Button
                        Rectangle {
                            implicitHeight: 34
                            implicitWidth: prevBtnRow.implicitWidth + 20
                            radius: 6
                            color: prevMa.containsMouse ? "#212836" : "#161b22"
                            border.color: "#388bfd"
                            border.width: 1

                            RowLayout {
                                id: prevBtnRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "👁️"
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: "Preview Retro"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: "#58a6ff"
                                }
                            }

                            MouseArea {
                                id: prevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof window !== "undefined" && typeof window.openRightSidebar === "function" && backend) {
                                        var rep = backend.get_report_content("team_motivation");
                                        window.openRightSidebar("report_preview", "Sprint Retro & Team Motivation", "Sprint Summary Markdown", rep);
                                    }
                                }
                            }
                        }

                        // Copy Retro Summary Button
                        Rectangle {
                            implicitHeight: 34
                            implicitWidth: copyBtnRow.implicitWidth + 24
                            radius: 6
                            color: copyMa.containsMouse ? "#238636" : "#2ea043"
                            border.color: "#3fb950"
                            border.width: 1

                            RowLayout {
                                id: copyBtnRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "📋"
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: "Copy Retro Summary"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: "#ffffff"
                                }
                            }

                            MouseArea {
                                id: copyMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.copySummaryToClipboard()
                            }
                        }

                        // Refresh Button
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 6
                            color: refreshMa.containsMouse ? "#21262d" : "#0d1117"
                            border.color: "#30363d"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "🔄"
                                font.pixelSize: 14
                            }

                            ToolTip.visible: refreshMa.containsMouse
                            ToolTip.text: "Recompute Motivation Stats"
                            ToolTip.delay: 200

                            MouseArea {
                                id: refreshMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (backend) backend.recompute_team_motivation();
                                }
                            }
                        }
                    }

                    // Toast message notification
                    Rectangle {
                        visible: root.copyToastMessage !== ""
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 4
                        color: "#162b20"
                        border.color: "#3fb950"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.copyToastMessage
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#3fb950"
                        }
                    }

                    // Timeframe Selector Tabs
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "⏱️ Timeframe:"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }

                        Repeater {
                            model: [
                                { id: "last_week", label: "📅 Last Week (Default)", tip: "Summarizes completed last sprint/week activity" },
                                { id: "current_week", label: "⚡ Current Sprint (Live)", tip: "Live real-time progress for active sprint" },
                                { id: "last_4_weeks", label: "🗓️ Past 4 Weeks", tip: "Four-week sprint cycle velocity & consistency" },
                                { id: "all_time", label: "👑 All-Time Legends", tip: "All-time Hall of Fame rankings & records" }
                            ]

                            Rectangle {
                                property bool isSelected: root.selectedTimeframe === modelData.id
                                implicitHeight: 30
                                implicitWidth: tfText.implicitWidth + 20
                                radius: 6
                                color: isSelected ? "#1f6feb" : (tfMa.containsMouse ? "#21262d" : "#0d1117")
                                border.color: isSelected ? "#388bfd" : "#30363d"
                                border.width: 1

                                Text {
                                    id: tfText
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: parent.isSelected ? Font.Bold : Font.Normal
                                    color: parent.isSelected ? "#ffffff" : "#c9d1d9"
                                }

                                ToolTip.visible: tfMa.containsMouse
                                ToolTip.text: modelData.tip
                                ToolTip.delay: 200

                                MouseArea {
                                    id: tfMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setTimeframe(modelData.id)
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Custom Sprint Dropdown selector if available
                        RowLayout {
                            visible: backend && backend.availableSprintList && backend.availableSprintList.length > 0
                            spacing: 6

                            Text {
                                text: "Select Sprint:"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }

                            ComboBox {
                                id: sprintCombo
                                implicitHeight: 30
                                implicitWidth: 140
                                model: backend ? backend.availableSprintList : []
                                currentIndex: 0
                                onActivated: {
                                    var sp = currentText;
                                    root.setTimeframe("sprint", sp);
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Team Motivation Tab Navigation Bar
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: tabNavLayout.implicitHeight + 16
                radius: 8
                color: "#161b22"
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    id: tabNavLayout
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Repeater {
                        model: [
                            {
                                id: "overview",
                                icon: "🏆",
                                label: "Overview & Podium",
                                desc: "Sprint KPIs, Top 10 & Radar",
                                badge: (podiumList && podiumList.length > 0) ? (Math.min(10, membersList.length) + " Ranked") : "",
                                badgeColor: "#ffd700"
                            },
                            {
                                id: "leaderboards",
                                icon: "🥇",
                                label: "Leaderboards & Rhythm",
                                desc: "Category Champions & Time",
                                badge: "8 Categories",
                                badgeColor: "#58a6ff"
                            },
                            {
                                id: "roster",
                                icon: "👥",
                                label: "Team Roster",
                                desc: "All Contributors & Profiles",
                                badge: (membersList && membersList.length > 0) ? (membersList.length + " Members") : "",
                                badgeColor: "#3fb950"
                            },
                            {
                                id: "badges",
                                icon: "🎖️",
                                label: "Badges & Achievements",
                                desc: "Unlockable Badges Gallery",
                                badge: (allBadgesList && allBadgesList.length > 0) ? (allBadgesList.length + " Badges") : "",
                                badgeColor: "#d2a8ff"
                            }
                        ]

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 50
                            radius: 6
                            property bool isSelected: root.activeTab === modelData.id
                            color: isSelected 
                                ? Qt.rgba(31/255, 111/255, 235/255, 0.18) 
                                : (tabMa.containsMouse ? "#21262d" : "#0d1117")
                            border.color: isSelected 
                                ? "#58a6ff" 
                                : (tabMa.containsMouse ? "#388bfd" : "#30363d")
                            border.width: isSelected ? 2 : 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    text: modelData.icon
                                    font.pixelSize: 18
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        spacing: 6
                                        Text {
                                            text: modelData.label
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: parent.parent.parent.parent.isSelected ? Font.Bold : Font.DemiBold
                                            color: parent.parent.parent.parent.isSelected ? "#ffffff" : "#c9d1d9"
                                        }

                                        Rectangle {
                                            visible: modelData.badge !== ""
                                            implicitHeight: 16
                                            implicitWidth: tabBadgeTxt.implicitWidth + 8
                                            radius: 8
                                            color: "#161b22"
                                            border.color: modelData.badgeColor
                                            border.width: 1

                                            Text {
                                                id: tabBadgeTxt
                                                anchors.centerIn: parent
                                                text: modelData.badge
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: modelData.badgeColor
                                            }
                                        }
                                    }

                                    Text {
                                        text: modelData.desc
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: parent.parent.parent.isSelected ? "#79c0ff" : "#8b949e"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeTab = modelData.id
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Team Pulse KPI Statistics Cards
            // ==========================================
            GridLayout {
                visible: root.activeTab === "overview"
                Layout.fillWidth: true
                columns: width > 1200 ? 5 : (width > 800 ? 3 : 1)
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: [
                        { label: "Total Points", value: (teamSummary ? (teamSummary.total_points || 0) : 0) + " pts", icon: "🌟", color: "#ffd700", bg: "#2a2200", tip: "Composite motivation and achievement score" },
                        { label: "Code Commits", value: (teamSummary ? (teamSummary.commits_count || 0) : 0) + " commits", icon: "💻", color: "#7ee787", bg: "#122a18", tip: "Total code commits pushed to repositories" },
                        { label: "PRs Merged / Open", value: (teamSummary ? (teamSummary.prs_closed || 0) : 0) + " / " + (teamSummary ? (teamSummary.prs_created || 0) : 0), icon: "🏁", color: "#3fb950", bg: "#162b20", tip: "Pull requests closed / merged vs opened" },
                        { label: "PR Reviews & Approvals", value: (teamSummary ? (teamSummary.prs_reviewed || 0) : 0) + " rev • " + (teamSummary ? (teamSummary.prs_approved || 0) : 0) + " app", icon: "🔍", color: "#39c5cf", bg: "#0d2d30", tip: "Peer PR reviews conducted and approvals/acceptances" },
                        { label: "Feature Branches", value: (teamSummary ? (teamSummary.branches_closed || 0) : 0) + " / " + (teamSummary ? (teamSummary.branches_started || 0) : 0), icon: "🌳", color: "#79c0ff", bg: "#16243b", tip: "Feature branches merged vs started" },
                        { label: "Tasks Done", value: (teamSummary ? (teamSummary.tasks_completed || 0) : 0) + " (" + (teamSummary ? (teamSummary.bugs_resolved || 0) : 0) + " bugs)", icon: "🔨", color: "#a371f7", bg: "#271052", tip: "Completed work items & resolved bugs" },
                        { label: "Release Tags", value: (teamSummary ? (teamSummary.tags_pushed || 0) : 0) + " tagged", icon: "🏷️", color: "#d2a8ff", bg: "#2c1b4d", tip: "Production and sprint milestone release tags" },
                        { label: "CI Builds", value: (teamSummary ? (teamSummary.builds_succeeded || 0) : 0) + "/" + (teamSummary ? (teamSummary.builds_total || 0) : 0) + " (" + (teamSummary ? (teamSummary.build_success_rate || 100) : 100) + "%)", icon: "🏗️", color: "#56d364", bg: "#142d1b", tip: "Successful CI builds vs total builds executed" },
                        { label: "Work Rhythm", value: (timeAnalytics ? timeAnalytics.daytime_pct : 0) + "% Day • " + (timeAnalytics ? timeAnalytics.night_pct : 0) + "% Night", icon: "⏰", color: "#f0883e", bg: "#3e1e0d", tip: "Daytime (9-18h), Night-Owl (21-5h), and Weekend activity breakdown" },
                    ]

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 74
                        radius: 8
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Rectangle {
                                width: 36
                                height: 36
                                radius: 8
                                color: modelData.bg
                                border.color: modelData.color
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.pixelSize: 18
                                }
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true
                                Text {
                                    text: String(modelData.value)
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.label
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                }
                            }
                        }

                        ToolTip.visible: cardMa.containsMouse
                        ToolTip.text: modelData.tip
                        ToolTip.delay: 200

                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }

            // ==========================================
            // Sprint Podium (Top 3 Gold, Silver, Bronze)
            // ==========================================
            Item {
                visible: (root.activeTab === "overview") && (podiumList.length > 0)
                Layout.fillWidth: true
                implicitHeight: 190

                RowLayout {
                    anchors.fill: parent
                    spacing: 16

                    Repeater {
                        model: podiumList

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 10
                            color: modelData.rank === 1 ? "#1c1912" : (modelData.rank === 2 ? "#191c20" : "#1e1713")
                            border.color: modelData.rank === 1 ? "#ffd700" : (modelData.rank === 2 ? "#c9d1d9" : "#f0883e")
                            border.width: modelData.rank === 1 ? 2 : 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 8

                                // Top row: Medal & Title
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: modelData.medal + " " + modelData.title
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: modelData.rank === 1 ? "#ffd700" : (modelData.rank === 2 ? "#f0f6fc" : "#f0883e")
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: (modelData.member.score || 0) + " pts"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                }

                                // Contributor Info
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        width: 40
                                        height: 40
                                        radius: 20
                                        color: modelData.rank === 1 ? "#3b2d00" : "#21262d"
                                        border.color: modelData.rank === 1 ? "#ffd700" : "#58a6ff"
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.member.initials || "??"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            color: "#f0f6fc"
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 2
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.member.name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                            color: "#f0f6fc"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: (modelData.member.prs_closed || 0) + " PRs merged • " + (modelData.member.prs_reviewed || 0) + " reviews (" + (modelData.member.prs_approved || 0) + " approved) • " + (modelData.member.commits_count || 0) + " commits"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                // Badges Row & Streak Pill
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    // Streak Badge
                                    Rectangle {
                                        visible: modelData.member.current_streak_weeks > 0
                                        implicitHeight: 22
                                        implicitWidth: streakTxt.implicitWidth + 12
                                        radius: 11
                                        color: "#3f1a18"
                                        border.color: "#ff7b72"
                                        border.width: 1

                                        Text {
                                            id: streakTxt
                                            anchors.centerIn: parent
                                            text: "🔥 " + modelData.member.current_streak_weeks + "w Streak"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: "#ff7b72"
                                        }
                                    }

                                    // Earned Badge Icons
                                    Repeater {
                                        model: (modelData.member.badges || []).slice(0, 4)

                                        Rectangle {
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: modelData.bg_color || "#21262d"
                                            border.color: modelData.color || "#30363d"
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.icon || "🎖️"
                                                font.pixelSize: 11
                                            }

                                            ToolTip.visible: badgeMa.containsMouse
                                            ToolTip.text: modelData.name + ": " + modelData.description
                                            ToolTip.delay: 150

                                            MouseArea {
                                                id: badgeMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "Inspect →"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#58a6ff"
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openMemberProfile(modelData.member)
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Places 4–10 (Honor Roll & Contenders)
            // ==========================================
            Rectangle {
                visible: (root.activeTab === "overview") && (top4To10List.length > 0)
                Layout.fillWidth: true
                implicitHeight: top4To10Col.implicitHeight + 28
                radius: 10
                color: "#161b22"
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: top4To10Col
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // Section Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 6
                            color: "#1c2438"
                            border.color: "#388bfd"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "🏅"
                                font.pixelSize: 14
                            }
                        }

                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            Text {
                                text: "Hall of Fame Contenders — Places 4 to 10"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Text {
                                text: "Top ranking team contributors chasing the podium with high activity and achievements"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                color: "#8b949e"
                            }
                        }

                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: top10CountTxt.implicitWidth + 12
                            radius: 11
                            color: "#1f334d"
                            border.color: "#58a6ff"
                            border.width: 1
                            Text {
                                id: top10CountTxt
                                anchors.centerIn: parent
                                text: top4To10List.length + " Contenders"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#79c0ff"
                            }
                        }
                    }

                    // Table / Row list of ranks 4 to 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: top4To10List

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 6
                                color: rowMa.containsMouse ? "#21262d" : "#0d1117"
                                border.color: rowMa.containsMouse ? "#58a6ff" : "#21262d"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    // Rank Badge Pill
                                    Rectangle {
                                        width: 32
                                        height: 24
                                        radius: 12
                                        color: modelData.rank === 4 ? "#2e2300" : (modelData.rank <= 5 ? "#1b2738" : "#1c2128")
                                        border.color: modelData.rank === 4 ? "#d29922" : (modelData.rank <= 5 ? "#388bfd" : "#30363d")
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "#" + modelData.rank
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: modelData.rank === 4 ? "#e3b341" : (modelData.rank <= 5 ? "#58a6ff" : "#8b949e")
                                        }
                                    }

                                    // Initials circle
                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: "#21262d"
                                        border.color: "#30363d"
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.member.initials || "??"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: "#c9d1d9"
                                        }
                                    }

                                    // Name & Persona
                                    ColumnLayout {
                                        Layout.preferredWidth: 160
                                        spacing: 1

                                        Text {
                                            text: modelData.member.name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            color: "#f0f6fc"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: (modelData.member.time_stats && modelData.member.time_stats.persona) ? modelData.member.time_stats.persona : "Contributor"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 9
                                            color: "#8b949e"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    // Activity Metrics Summary Chips
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        clip: true

                                        Text {
                                            text: (modelData.member.prs_closed || 0) + " PRs merged"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: (modelData.member.prs_closed || 0) > 0 ? "#3fb950" : "#6e7681"
                                        }
                                        Text { text: "•"; font.pixelSize: 8; color: "#30363d" }
                                        Text {
                                            text: (modelData.member.commits_count || 0) + " commits"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: (modelData.member.commits_count || 0) > 0 ? "#7ee787" : "#6e7681"
                                        }
                                        Text { text: "•"; font.pixelSize: 8; color: "#30363d" }
                                        Text {
                                            text: (modelData.member.tasks_completed || 0) + " tasks"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: (modelData.member.tasks_completed || 0) > 0 ? "#a371f7" : "#6e7681"
                                        }
                                        Text { text: "•"; font.pixelSize: 8; color: "#30363d" }
                                        Text {
                                            text: (modelData.member.prs_reviewed || 0) + " rev (" + (modelData.member.prs_approved || 0) + " app)"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: (modelData.member.prs_reviewed || 0) > 0 ? "#39c5cf" : "#6e7681"
                                        }
                                    }

                                    // Streak Pill
                                    Rectangle {
                                        visible: modelData.member.current_streak_weeks > 0
                                        implicitHeight: 18
                                        implicitWidth: stTxt.implicitWidth + 8
                                        radius: 9
                                        color: "#3f1a18"
                                        border.color: "#ff7b72"
                                        border.width: 1

                                        Text {
                                            id: stTxt
                                            anchors.centerIn: parent
                                            text: "🔥 " + modelData.member.current_streak_weeks + "w"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: "#ff7b72"
                                        }
                                    }

                                    // Badges preview
                                    Row {
                                        spacing: 3
                                        Repeater {
                                            model: (modelData.member.badges || []).slice(0, 3)
                                            Rectangle {
                                                width: 18
                                                height: 18
                                                radius: 9
                                                color: modelData.bg_color || "#21262d"
                                                border.color: modelData.color || "#30363d"
                                                border.width: 1
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.icon || "🎖️"
                                                    font.pixelSize: 9
                                                }
                                                ToolTip.visible: bMa.containsMouse
                                                ToolTip.text: modelData.name + ": " + modelData.description
                                                ToolTip.delay: 150
                                                MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true }
                                            }
                                        }
                                    }

                                    // Score
                                    Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: scTxt.implicitWidth + 14
                                        radius: 12
                                        color: "#0d2344"
                                        border.color: "#1f6feb"
                                        border.width: 1

                                        Text {
                                            id: scTxt
                                            anchors.centerIn: parent
                                            text: (modelData.member.score || 0) + " pts"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
                                        }
                                    }

                                    Text {
                                        text: "→"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: rowMa.containsMouse ? "#58a6ff" : "#484f58"
                                    }
                                }

                                MouseArea {
                                    id: rowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openMemberProfile(modelData.member)
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Team Activity Rhythms & 24-Hour / 7-Day Time Distribution
            // ==========================================
            Rectangle {
                visible: root.activeTab === "leaderboards"
                Layout.fillWidth: true
                implicitHeight: rhythmCol.implicitHeight + 36
                radius: 10
                color: "#161b22"
                border.color: "#30363d"
                border.width: 1

                property string timelineFilter: "all"

                ColumnLayout {
                    id: rhythmCol
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    // Title Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 34
                            height: 34
                            radius: 6
                            color: "#271052"
                            border.color: "#a371f7"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "⏰"
                                font.pixelSize: 18
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            Text {
                                text: "Team Work Rhythms & Activity Matrix"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Text {
                                text: "Precise temporal breakdown of commits, PRs, work items, and builds across the 24-hour day and 7-day week."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }

                        // Peak Day & Hour Pill
                        Rectangle {
                            visible: timeAnalytics !== null && timeAnalytics.total_samples > 0
                            implicitHeight: 28
                            implicitWidth: peakTxt.implicitWidth + 20
                            radius: 14
                            color: "#16243b"
                            border.color: "#58a6ff"
                            border.width: 1

                            Text {
                                id: peakTxt
                                anchors.centerIn: parent
                                text: "🔥 Peak: " + (timeAnalytics ? (timeAnalytics.peak_day + " @" + timeAnalytics.peak_hour_label) : "")
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: "#79c0ff"
                            }
                        }
                    }

                    // 4 Rhythm Persona Cards
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width > 1000 ? 4 : (width > 600 ? 2 : 1)
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: [
                                {
                                    title: "Daytime Core",
                                    badge: "☀️ Core Work",
                                    hours: "09:00 – 18:00 (Mon-Fri)",
                                    pct: timeAnalytics ? (timeAnalytics.daytime_pct + "%") : "0%",
                                    count: timeAnalytics ? (timeAnalytics.daytime_count + " events") : "0 events",
                                    breakdown: timeAnalytics && timeAnalytics.daytime_breakdown ? timeAnalytics.daytime_breakdown : "No daytime events",
                                    color: "#3fb950",
                                    bg: "#102a18"
                                },
                                {
                                    title: "Night Owls",
                                    badge: "🦉 Late Night",
                                    hours: "21:00 – 05:00",
                                    pct: timeAnalytics ? (timeAnalytics.night_pct + "%") : "0%",
                                    count: timeAnalytics ? (timeAnalytics.night_count + " events") : "0 events",
                                    breakdown: timeAnalytics && timeAnalytics.night_breakdown ? timeAnalytics.night_breakdown : "No late night events",
                                    color: "#a371f7",
                                    bg: "#271052"
                                },
                                {
                                    title: "Early Birds",
                                    badge: "🌅 Sunrise Surge",
                                    hours: "05:00 – 09:00 (Mon-Fri)",
                                    pct: timeAnalytics ? (timeAnalytics.early_bird_pct + "%") : "0%",
                                    count: timeAnalytics ? (timeAnalytics.early_bird_count + " events") : "0 events",
                                    breakdown: timeAnalytics && timeAnalytics.early_bird_breakdown ? timeAnalytics.early_bird_breakdown : "No early bird events",
                                    color: "#f0883e",
                                    bg: "#381a08"
                                },
                                {
                                    title: "The Week-enders",
                                    badge: "⚡ Weekend Warriors",
                                    hours: "Saturday & Sunday",
                                    pct: timeAnalytics ? (timeAnalytics.weekend_pct + "%") : "0%",
                                    count: timeAnalytics ? (timeAnalytics.weekend_count + " events") : "0 events",
                                    breakdown: timeAnalytics && timeAnalytics.weekend_breakdown ? timeAnalytics.weekend_breakdown : "No weekend events",
                                    color: "#d29922",
                                    bg: "#382900"
                                }
                            ]

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 76
                                radius: 8
                                color: "#0d1117"
                                border.color: modelData.color
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 32
                                        height: 32
                                        radius: 6
                                        color: modelData.bg
                                        border.color: modelData.color
                                        border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.badge.split(" ")[0]
                                            font.pixelSize: 16
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 2
                                        Layout.fillWidth: true
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: modelData.title
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: modelData.pct
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                color: modelData.color
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: modelData.hours
                                                font.family: "Consolas, monospace"
                                                font.pixelSize: 9
                                                color: "#8b949e"
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: modelData.count
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#c9d1d9"
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.breakdown
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 9
                                            color: "#79c0ff"
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Activity Type Filter Pills
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Timeline Filter:"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                        }

                        Repeater {
                            model: [
                                { id: "all", label: "✨ All Activities" },
                                { id: "commits", label: "💻 Commits" },
                                { id: "prs", label: "🔀 Pull Requests" },
                                { id: "tasks", label: "🔨 Tasks & State" },
                                { id: "builds", label: "🏗️ CI Builds" }
                            ]

                            Rectangle {
                                implicitHeight: 24
                                implicitWidth: pillTxt.implicitWidth + 18
                                radius: 12
                                color: rhythmCol.parent.timelineFilter === modelData.id ? "#388bfd33" : "#21262d"
                                border.color: rhythmCol.parent.timelineFilter === modelData.id ? "#58a6ff" : "#30363d"
                                border.width: 1

                                Text {
                                    id: pillTxt
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    font.weight: rhythmCol.parent.timelineFilter === modelData.id ? Font.Bold : Font.Normal
                                    color: rhythmCol.parent.timelineFilter === modelData.id ? "#58a6ff" : "#8b949e"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rhythmCol.parent.timelineFilter = modelData.id
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // 24-Hour & 7-Day Visual Matrix Charts
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        // Left: 24-Hour Activity Profile
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 60
                            implicitHeight: 155
                            radius: 8
                            color: "#0d1117"
                            border.color: "#21262d"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "⏰ 24-Hour Activity Timeline"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: "🟣 Night • 🟠 Early • 🟢 Day • 🟡 Eve"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        color: "#8b949e"
                                    }
                                }

                                // 24-Hour Bars Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 3

                                    Repeater {
                                        model: (timeAnalytics && timeAnalytics.hourly_details) ? timeAnalytics.hourly_details : 24

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            color: "transparent"

                                            property var detail: (timeAnalytics && timeAnalytics.hourly_details && timeAnalytics.hourly_details[index]) ? timeAnalytics.hourly_details[index] : null
                                            property string curFilter: rhythmCol.parent.timelineFilter
                                            property int val: {
                                                if (!detail) {
                                                    return (timeAnalytics && timeAnalytics.hourly_distribution) ? timeAnalytics.hourly_distribution[index] : 0;
                                                }
                                                if (curFilter === "commits") return detail.commits || 0;
                                                if (curFilter === "prs") return detail.prs || 0;
                                                if (curFilter === "tasks") return detail.tasks || 0;
                                                if (curFilter === "builds") return detail.builds || 0;
                                                return detail.count || 0;
                                            }
                                            property int maxVal: {
                                                if (!timeAnalytics) return 1;
                                                var m = 1;
                                                if (timeAnalytics.hourly_details) {
                                                    for (var i = 0; i < timeAnalytics.hourly_details.length; i++) {
                                                        var d = timeAnalytics.hourly_details[i];
                                                        var v = d.count;
                                                        if (curFilter === "commits") v = d.commits;
                                                        else if (curFilter === "prs") v = d.prs;
                                                        else if (curFilter === "tasks") v = d.tasks;
                                                        else if (curFilter === "builds") v = d.builds;
                                                        if (v > m) m = v;
                                                    }
                                                } else if (timeAnalytics.hourly_distribution) {
                                                    for (var j = 0; j < timeAnalytics.hourly_distribution.length; j++) {
                                                        if (timeAnalytics.hourly_distribution[j] > m) m = timeAnalytics.hourly_distribution[j];
                                                    }
                                                }
                                                return m;
                                            }
                                            property color barColor: {
                                                if (curFilter === "commits") return "#58a6ff";
                                                if (curFilter === "prs") return "#bc8cff";
                                                if (curFilter === "tasks") return "#3fb950";
                                                if (curFilter === "builds") return "#f0883e";
                                                if (index < 5 || index >= 21) return "#a371f7"; // Night
                                                if (index >= 5 && index < 9) return "#f0883e";  // Early
                                                if (index >= 9 && index < 18) return "#3fb950"; // Day
                                                return "#d29922";                               // Evening
                                            }

                                            // Bar Rectangle
                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                height: Math.max(4, Math.round((parent.val / parent.maxVal) * (parent.height - 4)))
                                                radius: 2
                                                color: parent.barColor
                                                opacity: hMa.containsMouse ? 1.0 : (parent.val > 0 ? 0.85 : 0.25)
                                            }

                                            ToolTip.visible: hMa.containsMouse
                                            ToolTip.text: {
                                                var timeStr = (index < 10 ? "0" : "") + index + ":00";
                                                var rhythmStr = (index < 5 || index >= 21 ? "Night" : (index < 9 ? "Early" : (index < 18 ? "Daytime" : "Evening")));
                                                if (detail && detail.breakdown) {
                                                    return timeStr + " (" + rhythmStr + ") — " + (detail.count || 0) + " total\n" + detail.breakdown;
                                                }
                                                return timeStr + " (" + rhythmStr + ") — " + parent.val + " events";
                                            }
                                            ToolTip.delay: 100

                                            MouseArea {
                                                id: hMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                            }
                                        }
                                    }
                                }

                                // Axis labels
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "00h"; font.pixelSize: 8; color: "#6e7681" }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "06h"; font.pixelSize: 8; color: "#6e7681" }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "12h"; font.pixelSize: 8; color: "#6e7681" }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "18h"; font.pixelSize: 8; color: "#6e7681" }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "23h"; font.pixelSize: 8; color: "#6e7681" }
                                }
                            }
                        }

                        // Right: 7-Day Sprint Distribution
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 40
                            implicitHeight: 155
                            radius: 8
                            color: "#0d1117"
                            border.color: "#21262d"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "📅 Weekly Rhythm (Mon – Sun)"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: timeAnalytics ? (timeAnalytics.peak_day + " focus") : ""
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#58a6ff"
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 6

                                    Repeater {
                                        model: timeAnalytics && timeAnalytics.daily_distribution ? timeAnalytics.daily_distribution : [
                                            {day: "Mon", full_day: "Monday", short: "M", count: 0, commits: 0, prs: 0, tasks: 0, builds: 0, breakdown: "No activity"},
                                            {day: "Tue", full_day: "Tuesday", short: "T", count: 0, commits: 0, prs: 0, tasks: 0, builds: 0, breakdown: "No activity"},
                                            {day: "Wed", full_day: "Wednesday", short: "W", count: 0, commits: 0, prs: 0, tasks: 0, builds: 0, breakdown: "No activity"},
                                            {day: "Thu", full_day: "Thursday", short: "T", count: 0, commits: 0, prs: 0, tasks: 0, builds: 0, breakdown: "No activity"},
                                            {day: "Fri", full_day: "Friday", short: "F", count: 0, commits: 0, prs: 0, tasks: 0, builds: 0, breakdown: "No activity"},
                                            {day: "Sat", full_day: "Saturday", short: "S", count: 0, commits: 0, prs: 0, tasks: 0, builds: 0, breakdown: "No activity"},
                                            {day: "Sun", full_day: "Sunday", short: "S", count: 0, commits: 0, prs: 0, tasks: 0, builds: 0, breakdown: "No activity"}
                                        ]

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 4

                                            property string curFilter: rhythmCol.parent.timelineFilter
                                            property int dayVal: {
                                                if (curFilter === "commits") return modelData.commits || 0;
                                                if (curFilter === "prs") return modelData.prs || 0;
                                                if (curFilter === "tasks") return modelData.tasks || 0;
                                                if (curFilter === "builds") return modelData.builds || 0;
                                                return modelData.count || 0;
                                            }
                                            property int maxDayVal: {
                                                if (!timeAnalytics || !timeAnalytics.daily_distribution) return 1;
                                                var m = 1;
                                                for (var i = 0; i < timeAnalytics.daily_distribution.length; i++) {
                                                    var d = timeAnalytics.daily_distribution[i];
                                                    var v = d.count;
                                                    if (curFilter === "commits") v = d.commits;
                                                    else if (curFilter === "prs") v = d.prs;
                                                    else if (curFilter === "tasks") v = d.tasks;
                                                    else if (curFilter === "builds") v = d.builds;
                                                    if (v > m) m = v;
                                                }
                                                return m;
                                            }
                                            property bool isWknd: index >= 5

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                color: "transparent"

                                                Rectangle {
                                                    anchors.bottom: parent.bottom
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    height: Math.max(4, Math.round((parent.parent.dayVal / parent.parent.maxDayVal) * (parent.height - 4)))
                                                    radius: 3
                                                    color: {
                                                        if (curFilter === "commits") return "#58a6ff";
                                                        if (curFilter === "prs") return "#bc8cff";
                                                        if (curFilter === "tasks") return "#3fb950";
                                                        if (curFilter === "builds") return "#f0883e";
                                                        if (parent.parent.isWknd) return "#d29922";
                                                        return (timeAnalytics && modelData.day === timeAnalytics.peak_day) ? "#58a6ff" : "#238636";
                                                    }
                                                    opacity: dMa.containsMouse ? 1.0 : (parent.parent.dayVal > 0 ? 0.85 : 0.3)
                                                }

                                                ToolTip.visible: dMa.containsMouse
                                                ToolTip.text: {
                                                    var dayName = modelData.full_day || modelData.day;
                                                    var totalStr = (modelData.count || 0) + " total events";
                                                    if (modelData.breakdown) {
                                                        return dayName + (parent.parent.isWknd ? " (Weekend)" : "") + " — " + totalStr + "\n" + modelData.breakdown;
                                                    }
                                                    return dayName + ": " + parent.parent.dayVal + " events";
                                                }
                                                ToolTip.delay: 100

                                                MouseArea {
                                                    id: dMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                }
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.short || modelData.day
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                font.weight: parent.isWknd ? Font.Bold : Font.Normal
                                                color: parent.isWknd ? "#d29922" : "#8b949e"
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
            // Category Competitions & Mini Leaderboards Grid
            // ==========================================
            Text {
                visible: root.activeTab === "leaderboards"
                text: "⚔️ Category Champions & Competitions"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: "#f0f6fc"
                Layout.topMargin: 6
            }

            GridLayout {
                visible: root.activeTab === "leaderboards"
                Layout.fillWidth: true
                columns: width > 1150 ? 4 : (width > 850 ? 2 : 1)
                columnSpacing: 14
                rowSpacing: 14

                Repeater {
                    model: [
                        { key: "syntax_master", cat: leaderboards ? leaderboards.syntax_master : null },
                        { key: "cleaners", cat: leaderboards ? leaderboards.cleaners : null },
                        { key: "decliners", cat: leaderboards ? leaderboards.decliners : null },
                        { key: "fast_closer", cat: leaderboards ? leaderboards.fast_closer : null },
                        { key: "oldest_task", cat: leaderboards ? leaderboards.oldest_task : null },
                        { key: "evidences", cat: leaderboards ? leaderboards.evidences : null },
                        { key: "state_movers", cat: leaderboards ? leaderboards.state_movers : null },
                        { key: "prs_closed", cat: leaderboards ? leaderboards.prs_closed : null },
                        { key: "prs_approved", cat: leaderboards ? leaderboards.prs_approved : null },
                        { key: "prs_reviewed", cat: leaderboards ? leaderboards.prs_reviewed : null },
                        { key: "commits", cat: leaderboards ? leaderboards.commits : null },
                        { key: "night_owls", cat: leaderboards ? leaderboards.night_owls : null },
                        { key: "weekend_warriors", cat: leaderboards ? leaderboards.weekend_warriors : null },
                        { key: "early_birds", cat: leaderboards ? leaderboards.early_birds : null },
                        { key: "daytime", cat: leaderboards ? leaderboards.daytime : null },
                        { key: "branches_closed", cat: leaderboards ? leaderboards.branches_closed : null },
                        { key: "branches_started", cat: leaderboards ? leaderboards.branches_started : null },
                        { key: "tasks_completed", cat: leaderboards ? leaderboards.tasks_completed : null },
                        { key: "bugs_resolved", cat: leaderboards ? leaderboards.bugs_resolved : null },
                        { key: "builds", cat: leaderboards ? leaderboards.builds : null },
                        { key: "tags", cat: leaderboards ? leaderboards.tags : null },
                        { key: "streaks", cat: leaderboards ? leaderboards.streaks : null },
                        { key: "prs_created", cat: leaderboards ? leaderboards.prs_created : null },
                        { key: "overall", cat: leaderboards ? leaderboards.overall : null },
                    ]

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 160
                        radius: 8
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            // Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: modelData.cat ? (modelData.cat.icon + " " + modelData.cat.title) : "Leaderboard"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: "#21262d"
                            }

                            // Top Entries List
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: modelData.cat && modelData.cat.entries ? modelData.cat.entries.slice(0, 3) : []

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: modelData.medal
                                            font.pixelSize: 11
                                            Layout.preferredWidth: 18
                                        }

                                        Text {
                                            text: modelData.name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: modelData.rank === 1 ? Font.Bold : Font.Normal
                                            color: modelData.rank === 1 ? "#f0f6fc" : "#c9d1d9"
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.value + " " + (modelData.unit || "")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: "#58a6ff"
                                        }
                                    }
                                }

                                Item {
                                    visible: !modelData.cat || !modelData.cat.entries || modelData.cat.entries.length === 0
                                    Layout.fillWidth: true
                                    height: 30
                                    Text {
                                        anchors.centerIn: parent
                                        text: "No activity recorded for period"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#6e7681"
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            // ==========================================
            // Backlog State Hygiene & Stale Task Radar ("The Ignorer Watch")
            // ==========================================
            Rectangle {
                visible: root.activeTab === "overview"
                Layout.fillWidth: true
                implicitHeight: hygieneCol.implicitHeight + 36
                radius: 10
                color: "#161b22"
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: hygieneCol
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    // Title Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 34
                            height: 34
                            radius: 6
                            color: "#1a2332"
                            border.color: "#58a6ff"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "🧹"
                                font.pixelSize: 18
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            Text {
                                text: "Backlog State Hygiene & Stale Item Radar"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                            Text {
                                text: "Tracking state transition velocity: 'The Cleaner' (accurate grooming), 'The Decliner' (quality gatekeeping), and 'The Ignorer' (idle un-transitioned tasks)."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }
                    }

                    // Hygiene Persona Metrics (Cleaner vs Decliner vs Stale Items)
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width > 1000 ? 3 : (width > 650 ? 2 : 1)
                        columnSpacing: 12
                        rowSpacing: 12

                        // The Cleaner Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 74
                            radius: 8
                            color: "#0d1117"
                            border.color: "#238636"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 19
                                    color: "#162b20"
                                    border.color: "#238636"
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: "🧹"
                                        font.pixelSize: 18
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Text {
                                        text: "The Cleaner (State Grooming)"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: "#3fb950"
                                    }
                                    Text {
                                        text: teamSummary && teamSummary.cleaner_leader ? (teamSummary.cleaner_leader.name + " (" + teamSummary.cleaner_leader.value + " groomed)") : "No grooming recorded"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "Grooms and closes completed items promptly"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                    }
                                }
                            }
                        }

                        // The Decliner / Gatekeeper Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 74
                            radius: 8
                            color: "#0d1117"
                            border.color: "#8957e5"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 19
                                    color: "#271052"
                                    border.color: "#8957e5"
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: "🛡️"
                                        font.pixelSize: 18
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Text {
                                        text: "The Gatekeeper (Pushbacks)"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: "#a371f7"
                                    }
                                    Text {
                                        text: teamSummary && teamSummary.decliner_leader ? (teamSummary.decliner_leader.name + " (" + teamSummary.decliner_leader.value + " pushbacks)") : (teamSummary ? (teamSummary.total_pushbacks || 0) + " pushbacks total" : "0 pushbacks")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "Reopens tasks if not meeting acceptance criteria"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                    }
                                }
                            }
                        }

                        // The Stale Radar Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 74
                            radius: 8
                            color: "#0d1117"
                            border.color: (staleRadarList && staleRadarList.length > 0) ? "#d29922" : "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 19
                                    color: (staleRadarList && staleRadarList.length > 0) ? "#382900" : "#21262d"
                                    border.color: (staleRadarList && staleRadarList.length > 0) ? "#d29922" : "#30363d"
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: "⚠️"
                                        font.pixelSize: 18
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Stale Task Radar (Ignorer Watch)"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: (staleRadarList && staleRadarList.length > 0) ? "#e3b341" : "#8b949e"
                                    }
                                    Text {
                                        text: (staleRadarList ? staleRadarList.length : 0) + " items idle ≥14 days"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#f0f6fc"
                                    }
                                    Text {
                                        text: "Open tasks assigned without state changes"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                    }
                                }
                            }
                        }
                    }

                    // Stale Tasks Radar Table List (if any idle tasks exist)
                    ColumnLayout {
                        visible: staleRadarList && staleRadarList.length > 0
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "⚠️ Attention Required: Top Idle Open Tasks (≥14 Days Without State Update)"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#e3b341"
                        }

                        Repeater {
                            model: (staleRadarList || []).slice(0, 8)

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: 6
                                color: "#0d1117"
                                border.color: "#21262d"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    // Type Badge
                                    Rectangle {
                                        implicitHeight: 20
                                        implicitWidth: wiTypeTxt.implicitWidth + 8
                                        radius: 3
                                        color: modelData.type === "Bug" ? "#3f1a18" : (modelData.type === "Story" ? "#16243b" : "#21262d")
                                        border.color: modelData.type === "Bug" ? "#ff7b72" : (modelData.type === "Story" ? "#58a6ff" : "#30363d")
                                        border.width: 1

                                        Text {
                                            id: wiTypeTxt
                                            anchors.centerIn: parent
                                            text: modelData.type || "Task"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: modelData.type === "Bug" ? "#ff7b72" : (modelData.type === "Story" ? "#79c0ff" : "#c9d1d9")
                                        }
                                    }

                                    // ID & Title
                                    Text {
                                        text: "#" + modelData.id + " " + modelData.title
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    // Assigned To
                                    Text {
                                        text: "👤 " + (modelData.assigned_to || "Unassigned")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                    }

                                    // Idle Duration Pill
                                    Rectangle {
                                        implicitHeight: 20
                                        implicitWidth: idleTxt.implicitWidth + 10
                                        radius: 10
                                        color: modelData.days_idle >= 30 ? "#3f1a18" : "#382900"
                                        border.color: modelData.days_idle >= 30 ? "#ff7b72" : "#d29922"
                                        border.width: 1

                                        Text {
                                            id: idleTxt
                                            anchors.centerIn: parent
                                            text: modelData.days_idle + " days idle 💤"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: modelData.days_idle >= 30 ? "#ff7b72" : "#e3b341"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Full Team Contributor Table & Badges Showcase
            // ==========================================
            RowLayout {
                visible: root.activeTab === "roster"
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 12

                Text {
                    text: "👥 Team Contributor Hall of Fame & Activity Breakdown"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }

                Item { Layout.fillWidth: true }

                // Search Filter
                Rectangle {
                    implicitWidth: 220
                    implicitHeight: 32
                    radius: 6
                    color: "#0d1117"
                    border.color: searchInput.activeFocus ? "#58a6ff" : "#30363d"
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
                            id: searchInput
                            Layout.fillWidth: true
                            color: "#f0f6fc"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            clip: true
                            onTextChanged: root.searchQuery = text

                            Text {
                                anchors.fill: parent
                                text: "Filter contributors..."
                                color: "#6e7681"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                visible: !searchInput.text && !searchInput.activeFocus
                            }
                        }
                    }
                }
            }

            // Table Header
            Rectangle {
                visible: root.activeTab === "roster"
                Layout.fillWidth: true
                height: 34
                color: "#161b22"
                radius: 6
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text { text: "RANK"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 40 }
                    Text { text: "CONTRIBUTOR"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.fillWidth: true }
                    Text { text: "SCORE"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 55; horizontalAlignment: Text.AlignRight }
                    Text { text: "RHYTHM"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "STREAK"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "COMMITS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 55; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "BRANCHES"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "PRS (M/C)"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "TASKS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 45; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "BUILDS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "BADGES EARNED"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 140 }
                }
            }

            // Members Table Rows
            ColumnLayout {
                visible: root.activeTab === "roster"
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: {
                        var list = membersList || [];
                        if (!root.searchQuery) return list;
                        var q = root.searchQuery.toLowerCase();
                        return list.filter(function(m) {
                            return m.name.toLowerCase().indexOf(q) !== -1;
                        });
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 46
                        radius: 6
                        color: rowMa.containsMouse ? "#1c2128" : "#0d1117"
                        border.color: rowMa.containsMouse ? "#388bfd" : "#21262d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            // Rank
                            Text {
                                text: index === 0 ? "🥇 #1" : (index === 1 ? "🥈 #2" : (index === 2 ? "🥉 #3" : "#" + (index + 1)))
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: index < 3 ? Font.Bold : Font.Normal
                                color: index === 0 ? "#ffd700" : (index === 1 ? "#c9d1d9" : (index === 2 ? "#f0883e" : "#8b949e"))
                                Layout.preferredWidth: 40
                            }

                            // Contributor Name & Avatar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: "#21262d"
                                    border.color: index === 0 ? "#ffd700" : "#30363d"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.initials || "??"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#f0f6fc"
                                    }
                                }

                                Text {
                                    text: modelData.name
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            // Score
                            Text {
                                text: String(modelData.score || 0)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#58a6ff"
                                Layout.preferredWidth: 55
                                horizontalAlignment: Text.AlignRight
                            }

                            // Work Rhythm Persona
                            Rectangle {
                                Layout.preferredWidth: 100
                                implicitHeight: 22
                                radius: 4
                                color: "#161b22"
                                border.color: "#30363d"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: (modelData.time_stats && modelData.time_stats.persona) ? modelData.time_stats.persona : "☀️ Daytime"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    color: "#f0f6fc"
                                }
                            }

                            // Streak
                            RowLayout {
                                Layout.preferredWidth: 60
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 3
                                Text {
                                    text: modelData.current_streak_weeks > 0 ? ("🔥 " + modelData.current_streak_weeks + "w") : "—"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: modelData.current_streak_weeks >= 2 ? Font.Bold : Font.Normal
                                    color: modelData.current_streak_weeks >= 3 ? "#ff7b72" : (modelData.current_streak_weeks > 0 ? "#e3b341" : "#6e7681")
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }

                            // Commits
                            Text {
                                text: String(modelData.commits_count || 0)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: modelData.commits_count > 0 ? "#7ee787" : "#6e7681"
                                Layout.preferredWidth: 55
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Branches (Closed / Started)
                            Text {
                                text: (modelData.branches_closed || 0) + " / " + (modelData.branches_started || 0)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#79c0ff"
                                Layout.preferredWidth: 60
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // PRs Merged / Created
                            Text {
                                text: (modelData.prs_closed || 0) + " / " + (modelData.prs_created || 0)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#c9d1d9"
                                Layout.preferredWidth: 60
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Tasks Completed
                            Text {
                                text: String(modelData.tasks_completed || 0)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#a371f7"
                                Layout.preferredWidth: 45
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // CI Builds (Pass / Fail)
                            Text {
                                text: modelData.builds_total > 0 ? ((modelData.builds_succeeded || 0) + "✓") : "—"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: modelData.builds_succeeded > 0 ? "#56d364" : "#6e7681"
                                Layout.preferredWidth: 50
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Badges
                            RowLayout {
                                Layout.preferredWidth: 140
                                spacing: 4

                                Repeater {
                                    model: (modelData.badges || []).slice(0, 5)

                                    Rectangle {
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: modelData.bg_color || "#161b22"
                                        border.color: modelData.color || "#30363d"
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.icon || "🎖️"
                                            font.pixelSize: 11
                                        }

                                        ToolTip.visible: bMa.containsMouse
                                        ToolTip.text: modelData.name + "\n" + modelData.description
                                        ToolTip.delay: 150

                                        MouseArea {
                                            id: bMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }
                                    }
                                }

                                Text {
                                    visible: (modelData.badges || []).length > 6
                                    text: "+" + ((modelData.badges || []).length - 6)
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                }
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openMemberProfile(modelData)
                        }
                    }
                }
            }

            // ==========================================
            // Badge Legend / Unlockable Badges Gallery
            // ==========================================
            Text {
                visible: root.activeTab === "badges"
                text: "🎖️ Unlockable Sprint & Team Badges"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: "#f0f6fc"
                Layout.topMargin: 12
            }

            GridLayout {
                visible: root.activeTab === "badges"
                Layout.fillWidth: true
                columns: width > 1100 ? 3 : (width > 700 ? 2 : 1)
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: allBadgesList

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 74
                        radius: 8
                        color: "#161b22"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Rectangle {
                                width: 38
                                height: 38
                                radius: 19
                                color: modelData.bg_color || "#21262d"
                                border.color: modelData.color || "#30363d"
                                border.width: 1.5

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon || "🎖️"
                                    font.pixelSize: 18
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    spacing: 6
                                    Text {
                                        text: modelData.name
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: modelData.color || "#f0f6fc"
                                    }
                                    Rectangle {
                                        implicitHeight: 16
                                        implicitWidth: tierTxt.implicitWidth + 8
                                        radius: 3
                                        color: modelData.tier === "legendary" ? "#3b2d00" : (modelData.tier === "gold" ? "#2d2300" : "#21262d")
                                        border.color: modelData.color || "#30363d"
                                        border.width: 1

                                        Text {
                                            id: tierTxt
                                            anchors.centerIn: parent
                                            text: (modelData.tier || "badge").toUpperCase()
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                            color: modelData.color || "#8b949e"
                                        }
                                    }
                                }

                                Text {
                                    text: modelData.description
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: "#8b949e"
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }

            Item { height: 24 } // Bottom margin
        }
    }

    // ==========================================
    // Member Profile Inspection Drawer
    // ==========================================
    Rectangle {
        id: profileDrawer
        visible: root.isProfileDrawerOpen && root.selectedMember !== null
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.min(440, parent.width * 0.9)
        color: "#161b22"
        border.color: "#30363d"
        border.width: 1
        z: 100

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // Header Row: Close Button & Member Name
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Contributor Profile"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 28
                    height: 28
                    radius: 4
                    color: closeDrawerMa.containsMouse ? "#30363d" : "#21262d"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 13
                        color: "#c9d1d9"
                    }

                    MouseArea {
                        id: closeDrawerMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.isProfileDrawerOpen = false
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Member Header Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 90
                radius: 8
                color: "#0d1117"
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        width: 52
                        height: 52
                        radius: 26
                        color: "#1f6feb"

                        Text {
                            anchors.centerIn: parent
                            text: root.selectedMember ? (root.selectedMember.initials || "??") : "??"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }
                    }

                    ColumnLayout {
                        spacing: 3
                        Text {
                            text: root.selectedMember ? root.selectedMember.name : ""
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "Sprint Motivation Score: " + (root.selectedMember ? (root.selectedMember.score || 0) : 0) + " pts"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: "#58a6ff"
                        }
                    }
                }
            }

            // Streak Pill
            Rectangle {
                visible: root.selectedMember && root.selectedMember.current_streak_weeks > 0
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 6
                color: "#3f1a18"
                border.color: "#ff7b72"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "🔥 Active Weekly Streak:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#ff7b72"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.selectedMember ? (root.selectedMember.current_streak_weeks + " consecutive weeks") : ""
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                }
            }

            // Work Rhythm & Persona Card
            Rectangle {
                visible: root.selectedMember && root.selectedMember.time_stats !== undefined
                Layout.fillWidth: true
                implicitHeight: 68
                radius: 6
                color: "#0d1117"
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "⏰ Work Rhythm Persona:"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: pTxt.implicitWidth + 12
                            radius: 4
                            color: "#16243b"
                            border.color: "#58a6ff"
                            Text {
                                id: pTxt
                                anchors.centerIn: parent
                                text: root.selectedMember && root.selectedMember.time_stats ? root.selectedMember.time_stats.persona : "☀️ Daytime Core"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#79c0ff"
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "☀️ " + (root.selectedMember && root.selectedMember.time_stats ? root.selectedMember.time_stats.daytime_pct : 0) + "% Day • 🦉 " + (root.selectedMember && root.selectedMember.time_stats ? root.selectedMember.time_stats.night_pct : 0) + "% Night • ⚡ " + (root.selectedMember && root.selectedMember.time_stats ? root.selectedMember.time_stats.weekend_pct : 0) + "% Wknd"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            color: "#c9d1d9"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Peak: " + (root.selectedMember && root.selectedMember.time_stats ? (root.selectedMember.time_stats.peak_day + " @" + root.selectedMember.time_stats.peak_hour_label) : "")
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            color: "#ffd700"
                        }
                    }
                }
            }

            // Metric Breakdown Grid
            Text {
                text: "Contribution Metrics Breakdown"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 13
                font.weight: Font.Bold
                color: "#8b949e"
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: root.selectedMember ? [
                        { label: "Commits Pushed", val: root.selectedMember.commits_count || 0, icon: "💻" },
                        { label: "PRs Merged (The Closer)", val: root.selectedMember.prs_closed || 0, icon: "🏁" },
                        { label: "PRs Approved / Accepted", val: root.selectedMember.prs_approved || 0, icon: "✅" },
                        { label: "Code Reviews Conducted", val: root.selectedMember.prs_reviewed || 0, icon: "🔍" },
                        { label: "Branches Started", val: root.selectedMember.branches_started || 0, icon: "🌳" },
                        { label: "Branches Merged", val: root.selectedMember.branches_closed || 0, icon: "🌿" },
                        { label: "Tasks Completed", val: root.selectedMember.tasks_completed || 0, icon: "🔨" },
                        { label: "Bugs Fixed", val: root.selectedMember.bugs_resolved || 0, icon: "🛡️" },
                        { label: "Syntax Standard Tasks", val: root.selectedMember.structured_syntax_completed || 0, icon: "🏷️" },
                        { label: "Tasks Fast Closed (<24h)", val: root.selectedMember.tasks_fast_closed || 0, icon: "⚡" },
                        { label: "Avg Task Turnaround", val: root.selectedMember.avg_task_turnaround_hours ? (root.selectedMember.avg_task_turnaround_hours + " hrs") : "—", icon: "⏱️" },
                        { label: "Oldest Open Task", val: root.selectedMember.oldest_open_task_days ? (root.selectedMember.oldest_open_task_days + " days") : "0 days", icon: "⏳" },
                        { label: "Task Evidences & Links", val: root.selectedMember.task_evidences_count || 0, icon: "🧾" },
                        { label: "State Transitions", val: root.selectedMember.state_changes_count || 0, icon: "🚀" },
                        { label: "Tasks Cleaned / Groomed", val: root.selectedMember.tasks_cleaned || 0, icon: "🧹" },
                        { label: "Tasks Pushed Back", val: root.selectedMember.pushbacks_count || 0, icon: "🛡️" },
                        { label: "Stale Items (>14d)", val: root.selectedMember.stale_tasks_count || 0, icon: "⚠️" },
                        { label: "CI Builds Passed", val: (root.selectedMember.builds_succeeded || 0) + "/" + (root.selectedMember.builds_total || 0), icon: "🏗️" },
                        { label: "Night Acts (9PM-5AM)", val: root.selectedMember.night_activities || 0, icon: "🦉" },
                        { label: "Weekend Acts", val: root.selectedMember.weekend_activities || 0, icon: "⚡" },
                        { label: "Early Bird (5-9AM)", val: root.selectedMember.early_bird_activities || 0, icon: "🌅" },
                        { label: "Fast Merges (<24h)", val: root.selectedMember.prs_fast_merged || 0, icon: "⚡" },
                    ] : []

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: 6
                        color: "#0d1117"
                        border.color: "#21262d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Text { text: modelData.icon; font.pixelSize: 12 }
                            Text {
                                text: modelData.label
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: String(modelData.val)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }
                        }
                    }
                }
            }

            // Earned Badges Section
            Text {
                text: "Earned Badges (" + (root.selectedMember ? (root.selectedMember.badges_count || 0) : 0) + ")"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 13
                font.weight: Font.Bold
                color: "#8b949e"
                Layout.topMargin: 4
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.selectedMember ? (root.selectedMember.badges || []) : []

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: 6
                            color: "#0d1117"
                            border.color: modelData.color || "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: modelData.bg_color || "#21262d"
                                    border.color: modelData.color || "#30363d"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon || "🎖️"
                                        font.pixelSize: 15
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: modelData.name
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: modelData.color || "#f0f6fc"
                                    }
                                    Text {
                                        text: modelData.description
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        visible: !root.selectedMember || !root.selectedMember.badges || root.selectedMember.badges.length === 0
                        Layout.fillWidth: true
                        height: 40
                        Text {
                            anchors.centerIn: parent
                            text: "No badges earned yet in this timeframe."
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#6e7681"
                        }
                    }
                }
            }
        }
    }
}
