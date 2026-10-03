import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

            ColumnLayout {
    property var root: null

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

                // Interactive Artifacts Table - Grouped by Repository
                Rectangle {
                    id: artifactsExplorerCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1

                    property string filterText: ""
                    property bool allExpanded: false
                    property int expandCollapseTrigger: 0

                    function expandAll() {
                        allExpanded = true;
                        expandCollapseTrigger++;
                    }

                    function collapseAll() {
                        allExpanded = false;
                        expandCollapseTrigger++;
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // Header with Title, Stats, Search Filter & Expand/Collapse All
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "Published Build Artifacts Explorer"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Rectangle {
                                    color: "#21262d"
                                    radius: 10
                                    border.color: "#30363d"
                                    implicitHeight: 22
                                    implicitWidth: repoCountText.implicitWidth + 14

                                    Text {
                                        id: repoCountText
                                        anchors.centerIn: parent
                                        text: {
                                            var count = (backend && backend.storageData && backend.storageData.artifacts_by_repo) ? backend.storageData.artifacts_by_repo.length : 0;
                                            return count + " Repositories";
                                        }
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#58a6ff"
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            // Filter Field
                            Rectangle {
                                implicitWidth: 220
                                implicitHeight: 28
                                color: "#0d1117"
                                radius: 6
                                border.color: searchInput.activeFocus ? "#58a6ff" : "#30363d"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        text: "🔍"
                                        font.pixelSize: 11
                                        opacity: 0.6
                                    }

                                    TextInput {
                                        id: searchInput
                                        Layout.fillWidth: true
                                        color: "#f0f6fc"
                                        font.pixelSize: 11
                                        clip: true
                                        selectByMouse: true
                                        onTextChanged: artifactsExplorerCard.filterText = text.trim().toLowerCase()

                                        Text {
                                            text: "Filter repositories or artifacts..."
                                            color: "#8b949e"
                                            font.pixelSize: 11
                                            visible: !searchInput.text && !searchInput.activeFocus
                                        }
                                    }

                                    Text {
                                        text: "✕"
                                        color: "#8b949e"
                                        font.pixelSize: 10
                                        visible: searchInput.text.length > 0
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: searchInput.text = ""
                                        }
                                    }
                                }
                            }

                            // Expand All Button
                            Button {
                                text: "📂  Expand All"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#c9d1d9"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    implicitWidth: 95
                                    radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                }
                                onClicked: {
                                    artifactsExplorerCard.expandAll();
                                }
                            }

                            // Collapse All Button
                            Button {
                                text: "📁  Collapse All"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#c9d1d9"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 28
                                    implicitWidth: 95
                                    radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                }
                                onClicked: {
                                    artifactsExplorerCard.collapseAll();
                                }
                            }
                        }

                        // Grouped Repositories ListView
                        ListView {
                            id: repoGroupList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 8

                            ScrollBar.vertical: ScrollBar {
                                active: true
                                policy: ScrollBar.AsNeeded
                            }

                            model: {
                                var allRepos = (backend && backend.storageData && backend.storageData.artifacts_by_repo) ? backend.storageData.artifacts_by_repo : [];
                                var filter = artifactsExplorerCard.filterText;
                                if (!filter) return allRepos;
                                return allRepos.filter(function(r) {
                                    if (r.repo_name.toLowerCase().indexOf(filter) !== -1) return true;
                                    for (var i = 0; i < r.artifacts.length; i++) {
                                        var a = r.artifacts[i];
                                        if ((a.artifact_name || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.source_branch || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.pipeline_name || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.owner || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.requested_by || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.build_date || "").toLowerCase().indexOf(filter) !== -1 ||
                                            (a.build_id + "").indexOf(filter) !== -1) {
                                            return true;
                                        }
                                    }
                                    return false;
                                });
                            }

                            // Empty state
                            Item {
                                anchors.centerIn: parent
                                width: 300
                                height: 100
                                visible: repoGroupList.count === 0

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        text: "📦"
                                        font.pixelSize: 28
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: artifactsExplorerCard.filterText ? "No matching repositories or artifacts found" : "No build artifacts recorded in cache"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }

                            delegate: Rectangle {
                                id: repoCard
                                width: repoGroupList.width - 8
                                implicitHeight: repoCol.implicitHeight + 16
                                color: "#0d1117"
                                radius: 6
                                border.color: isHovered ? "#58a6ff44" : "#30363d"
                                border.width: 1

                                property bool isHovered: false
                                property bool isExpanded: artifactsExplorerCard.allExpanded

                                Connections {
                                    target: artifactsExplorerCard
                                    function onExpandCollapseTriggerChanged() {
                                        repoCard.isExpanded = artifactsExplorerCard.allExpanded;
                                    }
                                }

                                ColumnLayout {
                                    id: repoCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    // Repository Group Header
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 38
                                        color: repoCard.isHovered ? "#21262d" : "#161b22"
                                        radius: 4
                                        border.color: "#30363d"
                                        border.width: 1

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: repoCard.isHovered = true
                                            onExited: repoCard.isHovered = false
                                            onClicked: repoCard.isExpanded = !repoCard.isExpanded
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10

                                            Text {
                                                text: repoCard.isExpanded ? "▼" : "▶"
                                                font.pixelSize: 10
                                                color: "#58a6ff"
                                                Layout.preferredWidth: 12
                                            }

                                            Text {
                                                text: "📁"
                                                font.pixelSize: 13
                                            }

                                            Text {
                                                text: modelData.repo_name || "Unknown Repository"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                                Layout.preferredWidth: 200
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                color: "#21262d"
                                                radius: 10
                                                border.color: "#30363d"
                                                implicitHeight: 20
                                                implicitWidth: repoCountLabel.implicitWidth + 12

                                                Text {
                                                    id: repoCountLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.artifacts_count + " artifact" + (modelData.artifacts_count === 1 ? "" : "s") + " (" + modelData.builds_count + " build" + (modelData.builds_count === 1 ? "" : "s") + ")"
                                                    font.pixelSize: 10
                                                    color: "#8b949e"
                                                }
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }

                                            // Count Size Per Group Pill
                                            Rectangle {
                                                color: "#272115"
                                                radius: 12
                                                border.color: "#d2992255"
                                                implicitHeight: 24
                                                implicitWidth: repoSizeLabel.implicitWidth + 16

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    Text {
                                                        text: "Total:"
                                                        font.pixelSize: 10
                                                        color: "#8b949e"
                                                    }

                                                    Text {
                                                        id: repoSizeLabel
                                                        text: modelData.total_size_str || "0.00 MB"
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: "#d29922"
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Sub-Table of Artifacts (when expanded)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: repoCard.isExpanded
                                        spacing: 4

                                        // Sub-table Header
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 26
                                            color: "#161b22"
                                            radius: 3

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                Text {
                                                    text: "BUILD"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 60
                                                }
                                                Text {
                                                    text: "PIPELINE"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 130
                                                }
                                                Text {
                                                    text: "BRANCH"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 100
                                                }
                                                Text {
                                                    text: "ARTIFACT NAME"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: "BUILD DATE"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 110
                                                }
                                                Text {
                                                    text: "OWNER"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 110
                                                }
                                                Text {
                                                    text: "SIZE"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 75
                                                }
                                                Text {
                                                    text: "STATUS"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    color: "#8b949e"
                                                    Layout.preferredWidth: 65
                                                }
                                            }
                                        }

                                        // Artifact Rows
                                        Repeater {
                                            model: modelData.artifacts || []

                                            delegate: Rectangle {
                                                Layout.fillWidth: true
                                                height: 32
                                                color: artMouse.containsMouse ? "#21262d" : "#161b2288"
                                                radius: 3
                                                border.color: artMouse.containsMouse ? "#30363d" : "transparent"

                                                MouseArea {
                                                    id: artMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: 350
                                                    ToolTip.text: "Build #" + modelData.build_id + (modelData.build_number ? " (" + modelData.build_number + ")" : "") +
                                                                  "\n• Pipeline: " + (modelData.pipeline_name || "Unknown") +
                                                                  "\n• Repository: " + (modelData.repo_name || "Unknown") +
                                                                  "\n• Branch: " + (modelData.source_branch || "-") +
                                                                  "\n• Build Date: " + (modelData.build_date || "-") +
                                                                  "\n• Owner: " + (modelData.owner || "System") +
                                                                  "\n• Artifact: " + (modelData.artifact_name || "drop") +
                                                                  "\n• Size: " + (modelData.size_mb_str || (modelData.size_mb + " MB")) +
                                                                  "\n• Status: " + (modelData.is_deleted ? "Deleted" : "Active")
                                                }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: 8

                                                    Text {
                                                        text: "#" + modelData.build_id
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: "#58a6ff"
                                                        Layout.preferredWidth: 60
                                                    }

                                                    Text {
                                                        text: modelData.pipeline_name || "Unknown Pipeline"
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: "#c9d1d9"
                                                        Layout.preferredWidth: 130
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: (modelData.branch_clean || (modelData.source_branch || "").replace("refs/heads/", ""))
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        color: "#8b949e"
                                                        Layout.preferredWidth: 100
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
                                                        text: modelData.build_date || "-"
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 10
                                                        color: "#8b949e"
                                                        Layout.preferredWidth: 110
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: modelData.owner || "System"
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: "#c9d1d9"
                                                        Layout.preferredWidth: 110
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: modelData.size_mb_str || ((modelData.size_mb || 0) + " MB")
                                                        font.family: "Consolas, monospace"
                                                        font.pixelSize: 11
                                                        color: "#d29922"
                                                        Layout.preferredWidth: 75
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
                        }
                    }
                }
            }
