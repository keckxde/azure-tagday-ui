import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "settings"

Item {
    id: root

    property var discoveredDatabases: []
    property string bannerMsg: ""
    property string bannerType: "info" // "info", "success", "error"
    property string activeTab: "connection" // "connection", "workitems", "reports", "categories", "aliases", "motivation", "general"

    // Team Motivation Score System Form Model
    property int scorePrsClosed: 15
    property int scorePrsCreated: 10
    property int scorePrsApproved: 8
    property int scorePrsReviewed: 6
    property int scoreCommitsCount: 3
    property int scoreBranchesClosed: 5
    property int scoreTagsPushed: 12
    property int scoreTasksCompleted: 8
    property int scoreTasksCreated: 3
    property int scoreBugsResolved: 10
    property int scoreStoriesCompleted: 10
    property int scoreTasksCleaned: 3
    property int scorePushbacksCount: 4
    property int scoreTasksFastClosed: 4
    property int scoreTaskEvidencesCount: 2
    property int scoreStructuredSyntaxCompleted: 7
    property int scoreBuildsSucceeded: 4
    property int scoreBadgeBonus: 5
    property int scoreStreakWeekBonus: 4
    property int scoreDelayWeekPenalty: 3
    property int scoreBuildFailedPenalty: 2
    property int scoreStaleTaskPenalty: 2

    function loadScoreConfigFromBackend() {
        if (!backend) return;
        var cfg = backend.teamMotivationScoreConfig;
        if (!cfg) return;
        if (typeof cfg.prs_closed !== "undefined") root.scorePrsClosed = cfg.prs_closed;
        if (typeof cfg.prs_created !== "undefined") root.scorePrsCreated = cfg.prs_created;
        if (typeof cfg.prs_approved !== "undefined") root.scorePrsApproved = cfg.prs_approved;
        if (typeof cfg.prs_reviewed !== "undefined") root.scorePrsReviewed = cfg.prs_reviewed;
        if (typeof cfg.commits_count !== "undefined") root.scoreCommitsCount = cfg.commits_count;
        if (typeof cfg.branches_closed !== "undefined") root.scoreBranchesClosed = cfg.branches_closed;
        if (typeof cfg.tags_pushed !== "undefined") root.scoreTagsPushed = cfg.tags_pushed;
        if (typeof cfg.tasks_completed !== "undefined") root.scoreTasksCompleted = cfg.tasks_completed;
        if (typeof cfg.tasks_created !== "undefined") root.scoreTasksCreated = cfg.tasks_created;
        if (typeof cfg.bugs_resolved !== "undefined") root.scoreBugsResolved = cfg.bugs_resolved;
        if (typeof cfg.stories_completed !== "undefined") root.scoreStoriesCompleted = cfg.stories_completed;
        if (typeof cfg.tasks_cleaned !== "undefined") root.scoreTasksCleaned = cfg.tasks_cleaned;
        if (typeof cfg.pushbacks_count !== "undefined") root.scorePushbacksCount = cfg.pushbacks_count;
        if (typeof cfg.tasks_fast_closed !== "undefined") root.scoreTasksFastClosed = cfg.tasks_fast_closed;
        if (typeof cfg.task_evidences_count !== "undefined") root.scoreTaskEvidencesCount = cfg.task_evidences_count;
        if (typeof cfg.structured_syntax_completed !== "undefined") root.scoreStructuredSyntaxCompleted = cfg.structured_syntax_completed;
        if (typeof cfg.builds_succeeded !== "undefined") root.scoreBuildsSucceeded = cfg.builds_succeeded;
        if (typeof cfg.badge_bonus !== "undefined") root.scoreBadgeBonus = cfg.badge_bonus;
        if (typeof cfg.streak_week_bonus !== "undefined") root.scoreStreakWeekBonus = cfg.streak_week_bonus;
        if (typeof cfg.delay_week_penalty !== "undefined") root.scoreDelayWeekPenalty = cfg.delay_week_penalty;
        if (typeof cfg.build_failed_penalty !== "undefined") root.scoreBuildFailedPenalty = cfg.build_failed_penalty;
        if (typeof cfg.stale_task_penalty !== "undefined") root.scoreStaleTaskPenalty = cfg.stale_task_penalty;
    }

    function saveScoreConfig() {
        if (!backend) return;
        var cfg = {
            "prs_closed": root.scorePrsClosed,
            "prs_created": root.scorePrsCreated,
            "prs_approved": root.scorePrsApproved,
            "prs_reviewed": root.scorePrsReviewed,
            "commits_count": root.scoreCommitsCount,
            "branches_closed": root.scoreBranchesClosed,
            "tags_pushed": root.scoreTagsPushed,
            "tasks_completed": root.scoreTasksCompleted,
            "tasks_created": root.scoreTasksCreated,
            "bugs_resolved": root.scoreBugsResolved,
            "stories_completed": root.scoreStoriesCompleted,
            "tasks_cleaned": root.scoreTasksCleaned,
            "pushbacks_count": root.scorePushbacksCount,
            "tasks_fast_closed": root.scoreTasksFastClosed,
            "task_evidences_count": root.scoreTaskEvidencesCount,
            "structured_syntax_completed": root.scoreStructuredSyntaxCompleted,
            "builds_succeeded": root.scoreBuildsSucceeded,
            "badge_bonus": root.scoreBadgeBonus,
            "streak_week_bonus": root.scoreStreakWeekBonus,
            "delay_week_penalty": root.scoreDelayWeekPenalty,
            "build_failed_penalty": root.scoreBuildFailedPenalty,
            "stale_task_penalty": root.scoreStaleTaskPenalty
        };
        var ok = backend.save_team_motivation_score_config(cfg);
        if (ok) {
            root.bannerMsg = "✅ Team Motivation score weights saved and applied across all leaderboards & podiums!";
            root.bannerType = "success";
        } else {
            root.bannerMsg = "❌ Failed to save score weights.";
            root.bannerType = "error";
        }
    }

    function applyScorePreset(presetId) {
        if (!backend) return;
        var ok = backend.apply_team_motivation_preset(presetId);
        if (ok) {
            loadScoreConfigFromBackend();
            root.bannerMsg = "✅ Applied preset profile: " + presetId;
            root.bannerType = "success";
        }
    }

    function resetScoreDefaults() {
        if (!backend) return;
        var ok = backend.reset_team_motivation_score_config();
        if (ok) {
            loadScoreConfigFromBackend();
            root.bannerMsg = "🔄 Reset score weights to built-in default values.";
            root.bannerType = "info";
        }
    }

    function loadDatabasesList() {
        if (backend) {
            discoveredDatabases = backend.get_available_databases() || [];
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            loadDatabasesList();
            loadScoreConfigFromBackend();
        });
    }

    // Connect to backend settings signals
    Connections {
        target: backend

        function onSettingsChanged() {
            root.loadDatabasesList();
        }

        function onStatsChanged() {
            root.loadDatabasesList();
        }

        function onTeamMotivationScoreConfigChanged() {
            root.loadScoreConfigFromBackend();
        }
    }

    // Full screen / full space Master-Detail Layout
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ============================================================
        // LEFT SIDEBAR: Navigation Rail & Project Status
        // ============================================================
        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 260
            Layout.minimumWidth: 240
            Layout.maximumWidth: 280
            color: "#0d1117"
            border.color: "#30363d"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // Sidebar Header Area
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "⚙️ Settings"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }

                    Item { Layout.fillWidth: true }

                    // Project Connection Status Indicator
                    Rectangle {
                        implicitHeight: 18
                        implicitWidth: connBadgeTxt.implicitWidth + 10
                        radius: 9
                        color: (backend && backend.dbPath) ? "#162b20" : "#3c1e1e"
                        border.color: (backend && backend.dbPath) ? "#238636" : "#f85149"
                        border.width: 1

                        Text {
                            id: connBadgeTxt
                            anchors.centerIn: parent
                            text: (backend && backend.dbPath) ? "● Connected" : "● Offline"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: (backend && backend.dbPath) ? "#3fb950" : "#f85149"
                        }
                    }
                }

                Text {
                    text: "Configuration, rules & workspace"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#21262d"
                }

                // Vertical Tab Navigation List
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: [
                                {
                                    id: "connection",
                                    icon: "🌐",
                                    label: "Connection & Sync",
                                    desc: "TFS, Database & Auto-Sync",
                                    badge: (backend && backend.dbPath) ? "Active" : "Offline",
                                    badgeColor: (backend && backend.dbPath) ? "#3fb950" : "#f85149"
                                },
                                {
                                    id: "workitems",
                                    icon: "📋",
                                    label: "Agile & Work Items",
                                    desc: "Area Paths, Tags & Sprints",
                                    badge: (backend && backend.areaPathFilterEnabled && backend.areaPathRules && backend.areaPathRules.length > 0) ? (backend.areaPathRules.length + " Rules") : "",
                                    badgeColor: "#58a6ff"
                                },
                                {
                                    id: "reports",
                                    icon: "📊",
                                    label: "Reports & Git Filters",
                                    desc: "Reports Path & Branches",
                                    badge: (backend && backend.branchFilterPatterns && backend.branchFilterPatterns.length > 0) ? (backend.branchFilterPatterns.length + " Filters") : "",
                                    badgeColor: "#d29922"
                                },
                                {
                                    id: "categories",
                                    icon: "🏷️",
                                    label: "Repo Categories",
                                    desc: "Classification & Overrides",
                                    badge: (backend && backend.repoCategories && backend.repoCategories.length > 0) ? (backend.repoCategories.length + " Categories") : "",
                                    badgeColor: "#bc8cff"
                                },
                                {
                                    id: "aliases",
                                    icon: "👤",
                                    label: "Users & Aliases",
                                    desc: "Git & TFS User Identities",
                                    badge: (function() {
                                        var aCount = (backend && backend.userAliases) ? backend.userAliases.length : 0;
                                        var sCount = (backend && backend.systemUsersCount) ? backend.systemUsersCount : 0;
                                        if (aCount > 0 && sCount > 0) return aCount + " Mapped";
                                        if (aCount > 0) return aCount + " Mapped";
                                        if (sCount > 0) return sCount + " Bots";
                                        return "";
                                    })(),
                                    badgeColor: "#a371f7"
                                },
                                {
                                    id: "motivation",
                                    icon: "🏆",
                                    label: "Team Motivation",
                                    desc: "Score Weights & Badges",
                                    badge: "Gamification",
                                    badgeColor: "#f0883e"
                                },
                                {
                                    id: "general",
                                    icon: "⚙️",
                                    label: "General & Tools",
                                    desc: "Display, Backup & About",
                                    badge: backend ? backend.appVersion : "",
                                    badgeColor: "#8b949e"
                                }
                            ]

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 52
                                radius: 6
                                property bool isSelected: root.activeTab === modelData.id
                                color: isSelected 
                                    ? Qt.rgba(31/255, 111/255, 235/255, 0.20) 
                                    : (tabMa.containsMouse ? "#161b22" : "transparent")
                                border.color: isSelected 
                                    ? "#388bfd" 
                                    : (tabMa.containsMouse ? "#30363d" : "transparent")
                                border.width: 1

                                // Left accent marker bar for active tab
                                Rectangle {
                                    width: 3
                                    height: parent.height - 12
                                    anchors.left: parent.left
                                    anchors.leftMargin: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 1.5
                                    color: "#58a6ff"
                                    visible: parent.isSelected
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: parent.isSelected ? 12 : 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: modelData.icon
                                        font.pixelSize: 16
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Text {
                                                text: modelData.label
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: parent.parent.parent.parent.isSelected ? Font.Bold : Font.DemiBold
                                                color: parent.parent.parent.parent.isSelected ? "#ffffff" : "#c9d1d9"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Rectangle {
                                                visible: modelData.badge !== ""
                                                implicitHeight: 15
                                                implicitWidth: tabBadgeTxt.implicitWidth + 8
                                                radius: 7
                                                color: "#161b22"
                                                border.color: modelData.badgeColor
                                                border.width: 1

                                                Text {
                                                    id: tabBadgeTxt
                                                    anchors.centerIn: parent
                                                    text: modelData.badge
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 8
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

                // Sidebar Footer: Active Database Pill & Connect New Project Button
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#21262d"
                }

                Button {
                    Layout.fillWidth: true
                    text: "➕ Connect New Project..."
                    font.family: "Segoe UI, sans-serif"
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
                        implicitHeight: 32
                        radius: 6
                        color: parent.hovered ? "#2ea043" : "#238636"
                        border.color: "#3fb950"
                        border.width: 1
                    }
                    onClicked: newProjectDialog.open()
                }
            }
        }

        // ============================================================
        // RIGHT MAIN CONTENT AREA: Uses ALL Available Width and Height
        // ============================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0d1117"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Top Header of Active Settings Tab
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: {
                                if (root.activeTab === "connection") return "🌐 Connection & Project Sync";
                                if (root.activeTab === "workitems") return "📋 Agile Sprints & Work Item Filters";
                                if (root.activeTab === "reports") return "📊 Reports Export & Git Branch Filters";
                                if (root.activeTab === "categories") return "🏷️ Repository Categories & Classification Rules";
                                if (root.activeTab === "aliases") return "👤 User Aliases & Identity Mapping";
                                if (root.activeTab === "motivation") return "🏆 Team Motivation Point System & Gamification";
                                if (root.activeTab === "general") return "⚙️ General Preferences & Application Tools";
                                return "Project Settings";
                            }
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }

                        Text {
                            text: {
                                if (root.activeTab === "connection") return "Manage TFS server URLs, personal access tokens (PAT), SQLite cache databases, and background sync.";
                                if (root.activeTab === "workitems") return "Configure Area Path filters, TFS Team names, custom deadline field names, and Sprint URL syntax templates.";
                                if (root.activeTab === "reports") return "Configure reports output directory, auto-generation options, and Git change notification branch/category filters.";
                                if (root.activeTab === "categories") return "Define custom repository categories, color branding, prefix-matching classification rules, and explicit overrides.";
                                if (root.activeTab === "aliases") return "Map Git committer identities to Azure DevOps TFS accounts and exclude automated system bots from leaderboards.";
                                if (root.activeTab === "motivation") return "Customize gamification point weights, activity rewards, penalties, and preset scoring profiles for team members.";
                                if (root.activeTab === "general") return "UI display scaling, database backup & export, diagnostic logs, and application metadata.";
                                return "Configure your project environment and preferences.";
                            }
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

                // Notification / Feedback Banner (Full Width)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 6
                    visible: root.bannerMsg !== ""
                    color: root.bannerType === "success" ? "#162b20" : (root.bannerType === "error" ? "#3c1e1e" : "#16243b")
                    border.color: root.bannerType === "success" ? "#238636" : (root.bannerType === "error" ? "#f85149" : "#388bfd")
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            text: root.bannerType === "success" ? "✓" : (root.bannerType === "error" ? "⚠️" : "ℹ️")
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: root.bannerType === "success" ? "#3fb950" : (root.bannerType === "error" ? "#f85149" : "#58a6ff")
                        }

                        Text {
                            text: root.bannerMsg
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: root.bannerType === "success" ? "#3fb950" : (root.bannerType === "error" ? "#f85149" : "#79c0ff")
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "✕"
                            font.pixelSize: 11
                            color: "#8b949e"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.bannerMsg = ""
                            }
                        }
                    }
                }

                // Scrollable Full-Width / Full-Height Tab Content Area
                ScrollView {
                    id: rightContentScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: rightContentScroll.width
                    clip: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Item {
                        width: rightContentScroll.width - 12
                        implicitHeight: activeTabStack.implicitHeight + 20

                        StackLayout {
                            id: activeTabStack
                            width: parent.width
                            currentIndex: {
                                if (root.activeTab === "connection") return 0;
                                if (root.activeTab === "workitems") return 1;
                                if (root.activeTab === "reports") return 2;
                                if (root.activeTab === "categories") return 3;
                                if (root.activeTab === "aliases") return 4;
                                if (root.activeTab === "motivation") return 5;
                                if (root.activeTab === "general") return 6;
                                return 0;
                            }

                            // Tab 0: Connection & Sync
                            Loader {
                                Layout.fillWidth: true
                                active: root.activeTab === "connection" || _loaded
                                property bool _loaded: false
                                asynchronous: true
                                source: "settings/SettingsConnectionTab.qml"
                                onLoaded: _loaded = true
                            }

                            // Tab 1: Agile & Work Items
                            Loader {
                                Layout.fillWidth: true
                                active: root.activeTab === "workitems" || _loaded
                                property bool _loaded: false
                                asynchronous: true
                                source: "settings/SettingsWorkItemsTab.qml"
                                onLoaded: _loaded = true
                            }

                            // Tab 2: Reports & Git Filters
                            Loader {
                                Layout.fillWidth: true
                                active: root.activeTab === "reports" || _loaded
                                property bool _loaded: false
                                asynchronous: true
                                source: "settings/SettingsReportsTab.qml"
                                onLoaded: _loaded = true
                            }

                            // Tab 3: Repository Categories
                            Loader {
                                Layout.fillWidth: true
                                active: root.activeTab === "categories" || _loaded
                                property bool _loaded: false
                                asynchronous: true
                                source: "settings/SettingsCategoriesTab.qml"
                                onLoaded: _loaded = true
                            }

                            // Tab 4: Users & Aliases
                            Loader {
                                Layout.fillWidth: true
                                active: root.activeTab === "aliases" || _loaded
                                property bool _loaded: false
                                asynchronous: true
                                source: "settings/SettingsAliasesTab.qml"
                                onLoaded: _loaded = true
                            }

                            // Tab 5: Team Motivation
                            Loader {
                                Layout.fillWidth: true
                                active: root.activeTab === "motivation" || _loaded
                                property bool _loaded: false
                                asynchronous: true
                                source: "settings/SettingsMotivationTab.qml"
                                onLoaded: _loaded = true
                            }

                            // Tab 6: General & Tools
                            Loader {
                                Layout.fillWidth: true
                                active: root.activeTab === "general" || _loaded
                                property bool _loaded: false
                                asynchronous: true
                                source: "settings/SettingsGeneralTab.qml"
                                onLoaded: _loaded = true
                            }
                        }
                    }
                }
            }
        }
    }

    // Modal New Project Dialog
    NewProjectDialog {
        id: newProjectDialog
        onProjectCreated: function(pName, dPath) {
            root.bannerMsg = "Project '" + pName + "' connected and database created successfully!";
            root.bannerType = "success";
            root.loadDatabasesList();
        }
    }
}
