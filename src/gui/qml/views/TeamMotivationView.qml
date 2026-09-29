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

    readonly property var motivationData: (backend && backend.teamMotivationData) ? backend.teamMotivationData : {}
    readonly property var teamSummary: motivationData && motivationData.team_summary ? motivationData.team_summary : {}
    readonly property var podiumList: motivationData && motivationData.podium ? motivationData.podium : []
    readonly property var leaderboards: motivationData && motivationData.leaderboards ? motivationData.leaderboards : {}
    readonly property var membersList: motivationData && motivationData.members ? motivationData.members : []
    readonly property var allBadgesList: motivationData && motivationData.all_badges ? motivationData.all_badges : []

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
        root.isProfileDrawerOpen = true;
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
            // Team Pulse KPI Statistics Cards
            // ==========================================
            GridLayout {
                Layout.fillWidth: true
                columns: width > 1150 ? 6 : (width > 800 ? 3 : 2)
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: [
                        { label: "Total Points", value: (teamSummary ? (teamSummary.total_points || 0) : 0) + " pts", icon: "🌟", color: "#ffd700", bg: "#2a2200", tip: "Composite motivation and achievement score" },
                        { label: "Code Commits", value: (teamSummary ? (teamSummary.commits_count || 0) : 0) + " commits", icon: "💻", color: "#7ee787", bg: "#122a18", tip: "Total code commits pushed to repositories" },
                        { label: "PRs Merged / Open", value: (teamSummary ? (teamSummary.prs_closed || 0) : 0) + " / " + (teamSummary ? (teamSummary.prs_created || 0) : 0), icon: "🏁", color: "#3fb950", bg: "#162b20", tip: "Pull requests closed / merged vs opened" },
                        { label: "Feature Branches", value: (teamSummary ? (teamSummary.branches_closed || 0) : 0) + " / " + (teamSummary ? (teamSummary.branches_started || 0) : 0), icon: "🌳", color: "#79c0ff", bg: "#16243b", tip: "Feature branches merged vs started" },
                        { label: "Tasks Done", value: (teamSummary ? (teamSummary.tasks_completed || 0) : 0) + " (" + (teamSummary ? (teamSummary.bugs_resolved || 0) : 0) + " bugs)", icon: "🔨", color: "#a371f7", bg: "#271052", tip: "Completed work items & resolved bugs" },
                        { label: "CI Builds", value: (teamSummary ? (teamSummary.builds_succeeded || 0) : 0) + "/" + (teamSummary ? (teamSummary.builds_total || 0) : 0) + " (" + (teamSummary ? (teamSummary.build_success_rate || 100) : 100) + "%)", icon: "🏗️", color: "#56d364", bg: "#142d1b", tip: "Successful CI builds vs total builds executed" },
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
                visible: podiumList.length > 0
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
                                            text: (modelData.member.prs_closed || 0) + " PRs merged • " + (modelData.member.commits_count || 0) + " commits • " + (modelData.member.tasks_completed || 0) + " tasks"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
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
            // Category Competitions & Mini Leaderboards Grid
            // ==========================================
            Text {
                text: "⚔️ Category Champions & Competitions"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: "#f0f6fc"
                Layout.topMargin: 6
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width > 1150 ? 4 : (width > 850 ? 2 : 1)
                columnSpacing: 14
                rowSpacing: 14

                Repeater {
                    model: [
                        { key: "prs_closed", cat: leaderboards ? leaderboards.prs_closed : null },
                        { key: "commits", cat: leaderboards ? leaderboards.commits : null },
                        { key: "branches_closed", cat: leaderboards ? leaderboards.branches_closed : null },
                        { key: "branches_started", cat: leaderboards ? leaderboards.branches_started : null },
                        { key: "tasks_completed", cat: leaderboards ? leaderboards.tasks_completed : null },
                        { key: "bugs_resolved", cat: leaderboards ? leaderboards.bugs_resolved : null },
                        { key: "builds", cat: leaderboards ? leaderboards.builds : null },
                        { key: "prs_reviewed", cat: leaderboards ? leaderboards.prs_reviewed : null },
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
            // Full Team Contributor Table & Badges Showcase
            // ==========================================
            RowLayout {
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
                    Text { text: "STREAK"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "COMMITS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "BRANCHES"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "PRS (M/C)"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "TASKS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "BUILDS"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 55; horizontalAlignment: Text.AlignHCenter }
                    Text { text: "BADGES EARNED"; font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 150 }
                }
            }

            // Members Table Rows
            ColumnLayout {
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

                            // Streak
                            RowLayout {
                                Layout.preferredWidth: 65
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
                                Layout.preferredWidth: 60
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Branches (Closed / Started)
                            Text {
                                text: (modelData.branches_closed || 0) + " / " + (modelData.branches_started || 0)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#79c0ff"
                                Layout.preferredWidth: 65
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // PRs Merged / Created
                            Text {
                                text: (modelData.prs_closed || 0) + " / " + (modelData.prs_created || 0)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#c9d1d9"
                                Layout.preferredWidth: 65
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Tasks Completed
                            Text {
                                text: String(modelData.tasks_completed || 0)
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#a371f7"
                                Layout.preferredWidth: 50
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // CI Builds (Pass / Fail)
                            Text {
                                text: modelData.builds_total > 0 ? ((modelData.builds_succeeded || 0) + "✓") : "—"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: modelData.builds_succeeded > 0 ? "#56d364" : "#6e7681"
                                Layout.preferredWidth: 55
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Badges
                            RowLayout {
                                Layout.preferredWidth: 150
                                spacing: 4

                                Repeater {
                                    model: (modelData.badges || []).slice(0, 6)

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
                text: "🎖️ Unlockable Sprint & Team Badges"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: "#f0f6fc"
                Layout.topMargin: 12
            }

            GridLayout {
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
                        { label: "PRs Merged", val: root.selectedMember.prs_closed || 0, icon: "🏁" },
                        { label: "Branches Started", val: root.selectedMember.branches_started || 0, icon: "🌳" },
                        { label: "Branches Merged", val: root.selectedMember.branches_closed || 0, icon: "🌿" },
                        { label: "Tasks Completed", val: root.selectedMember.tasks_completed || 0, icon: "🔨" },
                        { label: "Bugs Fixed", val: root.selectedMember.bugs_resolved || 0, icon: "🛡️" },
                        { label: "CI Builds Passed", val: (root.selectedMember.builds_succeeded || 0) + "/" + (root.selectedMember.builds_total || 0), icon: "🏗️" },
                        { label: "Code Reviews", val: root.selectedMember.prs_reviewed || 0, icon: "🔍" },
                        { label: "Fast Merges (<24h)", val: root.selectedMember.prs_fast_merged || 0, icon: "⚡" },
                        { label: "Release Tags", val: root.selectedMember.tags_pushed || 0, icon: "🏷️" },
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
