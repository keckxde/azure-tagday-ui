import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

            ColumnLayout {
    property var root: null

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
