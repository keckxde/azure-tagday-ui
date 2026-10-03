import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

        Rectangle {
    property var root: null

            id: tdSidebarRect
            Layout.preferredWidth: (root && root.isTdSidebarOpen) ? root.tdSidebarWidth : 0
            Layout.minimumWidth: (root && root.isTdSidebarOpen) ? root.minTdSidebarWidth : 0
            Layout.maximumWidth: (root && root.isTdSidebarOpen) ? root.maxTdSidebarWidth : 0
            Layout.fillHeight: true
            visible: (root && root.isTdSidebarOpen) || Layout.preferredWidth > 0
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
                            var maxW = Math.max(root.minTdSidebarWidth, Math.floor(root.width * 0.52));
                            var newW = Math.max(root.minTdSidebarWidth, Math.min(maxW, tdDragHandle._startWidth - delta));
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

            // MODE 1: Tag Day Inspector & Changes Timeline
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 10
                visible: root && root.activeReportTab === 1

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
                                    Layout.maximumWidth: root.tdSidebarWidth - 140
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

        // ============================================================
        // MODE 2: Storage & Build Artifacts Report Preview (Tab 2)
        // ============================================================
        ReportPreviewPane {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            visible: root && root.activeReportTab === 2
            root: root
            reportType: "storage"
            customTitle: "📦 Storage & Build Artifacts Preview"
        }

        // ============================================================
        // MODE 3: Release Notes & Version Tracking Preview (Tab 3)
        // ============================================================
        ReportPreviewPane {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            visible: root && root.activeReportTab === 3
            root: root
            reportType: "revision"
            customTitle: "📝 Release Notes (REVISION.md)"
        }

        // ============================================================
        // MODE 4: Agile Sprint Report Preview (Tab 4)
        // ============================================================
        ReportPreviewPane {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            visible: root && root.activeReportTab === 4
            root: root
            reportType: "sprint"
            reportParam: (root && root.selectedSprintReport) ? root.selectedSprintReport : ""
            customTitle: "🚀 Sprint Report: " + ((root && root.selectedSprintReport) ? root.selectedSprintReport : "Active")
        }

        // ============================================================
        // MODE 5: Sprint Rescheduling & Shifts Preview (Tab 5)
        // ============================================================
        ReportPreviewPane {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            visible: root && root.activeReportTab === 5
            root: root
            reportType: "rescheduling"
            customTitle: "⏱️ Rescheduling & Shifts Preview"
        }

        // ============================================================
        // MODE 0: Reports Overview Live Draft Preview (Tab 0)
        // ============================================================
        ReportPreviewPane {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            visible: root && root.activeReportTab === 0
            root: root
            reportType: "tagday"
            customTitle: "📊 Tag Day Release Preview"
        }
    }
