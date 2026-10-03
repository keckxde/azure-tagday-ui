import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: generalTabRoot
    spacing: 20
    Layout.fillWidth: true

    // ==========================================
    // Display & Typography Sizing Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: fontSettingCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: fontSettingCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { text: "🔤"; font.pixelSize: 20 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Display & Typography Scaling"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Adjust font size and interface scaling for high-DPI (2K/4K) monitors or compact viewing"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 10
                columnSpacing: 10

                Repeater {
                    model: [
                        {
                            mode: "small",
                            title: "Small (90%)",
                            desc: "Compact view for dense data tables and smaller screens",
                            badge: "Compact"
                        },
                        {
                            mode: "medium",
                            title: "Medium (100% - Default)",
                            desc: "Standard balanced scale for regular 1080p monitors",
                            badge: "Standard"
                        },
                        {
                            mode: "large",
                            title: "Large (115%)",
                            desc: "Enhanced readability for larger displays and text clarity",
                            badge: "Enhanced"
                        },
                        {
                            mode: "xlarge",
                            title: "Extra Large (130%)",
                            desc: "High-DPI / 4K monitors and high-accessibility viewing",
                            badge: "4K / HiDPI"
                        }
                    ]

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 68
                        radius: 6
                        property bool isSelected: backend && backend.fontSizeMode === modelData.mode
                        color: isSelected ? "#0d2344" : (optMa.containsMouse ? "#21262d" : "#0d1117")
                        border.color: isSelected ? "#1f6feb" : (optMa.containsMouse ? "#388bfd" : "#30363d")
                        border.width: isSelected ? 2 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            // Radio Indicator
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: parent.parent.isSelected ? "#1f6feb" : "#161b22"
                                border.color: parent.parent.isSelected ? "#58a6ff" : "#30363d"
                                border.width: 1

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: "#ffffff"
                                    visible: parent.parent.parent.isSelected
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    spacing: 8
                                    Text {
                                        text: modelData.title
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: parent.parent.parent.parent.isSelected ? "#f0f6fc" : "#e6edf3"
                                    }

                                    Rectangle {
                                        implicitHeight: 16
                                        implicitWidth: bLabel.implicitWidth + 8
                                        radius: 8
                                        color: parent.parent.parent.parent.isSelected ? "#1f6feb" : "#21262d"
                                        Text {
                                            id: bLabel
                                            anchors.centerIn: parent
                                            text: modelData.badge
                                            font.pixelSize: 9
                                            font.weight: Font.DemiBold
                                            color: parent.parent.parent.parent.parent.isSelected ? "#ffffff" : "#8b949e"
                                        }
                                    }
                                }

                                Text {
                                    text: modelData.desc
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: optMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (backend) {
                                    backend.setFontSizeMode(modelData.mode);
                                    root.bannerMsg = "Font size updated to " + modelData.title;
                                    root.bannerType = "success";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // Export & Import Specific User Settings Card
    // ==========================================
    Rectangle {
        id: exportImportCard
        Layout.fillWidth: true
        implicitHeight: exportImportCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        function getSelectedSections() {
            var secs = [];
            if (chkRepoCats.checked) secs.push("repo_categories");
            if (chkBranchFilters.checked) secs.push("git_branch_filters");
            if (chkMilestones.checked) secs.push("milestones");
            if (chkWorkItemCats.checked) secs.push("work_item_categories");
            if (chkTeamSprint.checked) secs.push("team_and_sprint_url");
            if (chkAreaPathSettings.checked) secs.push("area_path_settings");
            return secs;
        }

        function selectAllSections(enable) {
            chkRepoCats.checked = enable;
            chkBranchFilters.checked = enable;
            chkMilestones.checked = enable;
            chkWorkItemCats.checked = enable;
            chkTeamSprint.checked = enable;
            chkAreaPathSettings.checked = enable;
        }

        ColumnLayout {
            id: exportImportCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Card Title & Icon
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text { text: "📦"; font.pixelSize: 20 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Export & Import Specific User Settings"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Backup, share, or restore specific user configuration sections in YAML or JSON format."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: formatPillText.implicitWidth + 14
                    radius: 11
                    color: "#1f6feb22"
                    border.color: "#58a6ff"
                    border.width: 1

                    Text {
                        id: formatPillText
                        anchors.centerIn: parent
                        text: "YAML / JSON Supported"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: "#58a6ff"
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Section Selection Controls
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "Select Sections to Include:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#c9d1d9"
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Select All"
                    font.pixelSize: 11
                    background: Rectangle {
                        color: parent.hovered ? "#21262d" : "transparent"
                        radius: 4
                        border.color: "#30363d"
                        border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#79c0ff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: exportImportCard.selectAllSections(true)
                }

                Button {
                    text: "Deselect All"
                    font.pixelSize: 11
                    background: Rectangle {
                        color: parent.hovered ? "#21262d" : "transparent"
                        radius: 4
                        border.color: "#30363d"
                        border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#8b949e"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: exportImportCard.selectAllSections(false)
                }
            }

            // Checkbox Pills Grid
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 10
                columnSpacing: 16

                CheckBox {
                    id: chkRepoCats
                    text: "Repository Categories (rules, colors, overrides, default category)"
                    checked: true
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                }

                CheckBox {
                    id: chkBranchFilters
                    text: "Git Branch & Category Filters (branch_filter_patterns, notifications)"
                    checked: true
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                }

                CheckBox {
                    id: chkMilestones
                    text: "Milestones (categories, target dates, end dates, team assignment, descriptions)"
                    checked: true
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                }

                CheckBox {
                    id: chkWorkItemCats
                    text: "Work Item Categories & Deadlines (tag pattern mapping, custom deadline field, reports directory)"
                    checked: true
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                }

                CheckBox {
                    id: chkTeamSprint
                    text: "Team Assignment & Sprint URL (tfs_team_name, sprint_url_template, default_tfs_team)"
                    checked: true
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                }

                CheckBox {
                    id: chkAreaPathSettings
                    text: "Project Area Path Settings & Filters (area_path_settings)"
                    checked: true
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Options & Action Buttons Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                CheckBox {
                    id: chkClearExisting
                    text: "Clear existing records on import (Full replace instead of merge)"
                    checked: false
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: parent.checked ? "#f85149" : "#8b949e"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                }

                Item { Layout.fillWidth: true }

                // Export Button
                Button {
                    text: "📤 Export Settings..."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34
                        implicitWidth: 155
                        radius: 6
                        color: parent.hovered ? "#1f6feb" : "#238636"
                        border.color: parent.hovered ? "#58a6ff" : "#2ea043"
                        border.width: 1
                    }
                    onClicked: {
                        if (backend) {
                            var secs = exportImportCard.getSelectedSections();
                            if (secs.length === 0) {
                                root.bannerMsg = "Please select at least one settings section to export.";
                                root.bannerType = "error";
                                return;
                            }
                            var res = backend.exportAllUserSettings("", JSON.stringify(secs));
                            if (res && res.success) {
                                root.bannerMsg = res.message || ("Settings exported to: " + res.file_path);
                                root.bannerType = "success";
                            } else if (res && res.error) {
                                root.bannerMsg = "Export failed: " + res.error;
                                root.bannerType = "error";
                            }
                        }
                    }
                }

                // Import Button
                Button {
                    text: "📥 Import Settings..."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34
                        implicitWidth: 155
                        radius: 6
                        color: parent.hovered ? "#388bfd" : "#1f6feb"
                        border.color: "#58a6ff"
                        border.width: 1
                    }
                    onClicked: {
                        if (backend) {
                            var secs = exportImportCard.getSelectedSections();
                            if (secs.length === 0) {
                                root.bannerMsg = "Please select at least one settings section to import.";
                                root.bannerType = "error";
                                return;
                            }
                            var res = backend.importAllUserSettings("", chkClearExisting.checked, JSON.stringify(secs));
                            if (res && res.success) {
                                root.bannerMsg = res.message || "User settings imported successfully.";
                                root.bannerType = "success";
                            } else if (res && res.error) {
                                root.bannerMsg = "Import failed: " + res.error;
                                root.bannerType = "error";
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // About Application & Version Information Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: aboutAppCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: aboutAppCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text { text: "ℹ️"; font.pixelSize: 20 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "About DevOps Manager"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Desktop interface for managing multi-repository Azure DevOps (TFS) pipelines, Work Item WIQL sync, Tag Day releases, and Workload Planning."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Version & Git Describe Information Grid
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 10
                columnSpacing: 16

                // Application Display Version
                ColumnLayout {
                    spacing: 3
                    Text { text: "Display Version:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                    RowLayout {
                        spacing: 8
                        Text {
                            text: backend ? backend.appVersion : "v0.01.2637"
                            font.family: "Consolas, Segoe UI, monospace"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: statusPillText.implicitWidth + 12
                            radius: 10
                            color: (backend && backend.isExactTagVersion) ? "#23863622" : (backend && backend.appVersionInfo && backend.appVersionInfo.is_dirty ? "#d2992222" : "#1f6feb22")
                            border.color: (backend && backend.isExactTagVersion) ? "#3fb950" : (backend && backend.appVersionInfo && backend.appVersionInfo.is_dirty ? "#d29922" : "#58a6ff")
                            border.width: 1
                            Text {
                                id: statusPillText
                                anchors.centerIn: parent
                                text: backend && backend.appVersionInfo ? backend.appVersionInfo.status_label : "Release"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: (backend && backend.isExactTagVersion) ? "#3fb950" : (backend && backend.appVersionInfo && backend.appVersionInfo.is_dirty ? "#d29922" : "#58a6ff")
                            }
                        }
                    }
                }

                // Pip / PyPI Package Version
                ColumnLayout {
                    spacing: 3
                    Text { text: "Pip / Wheel Version (PEP 440):"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                    Text {
                        text: backend && backend.appVersionInfo ? backend.appVersionInfo.pep440_version : "0.1.2637"
                        font.family: "Consolas, monospace"
                        font.pixelSize: 12
                        color: "#79c0ff"
                    }
                }

                // Git Describe Raw
                ColumnLayout {
                    spacing: 3
                    Text { text: "Git Describe:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                    Text {
                        text: backend && backend.appVersionInfo ? backend.appVersionInfo.raw_describe : "v0.01.2637-0-gb95f88e"
                        font.family: "Consolas, monospace"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }

                // Metadata Source
                ColumnLayout {
                    spacing: 3
                    Text { text: "Version Resolution Source:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                    Text {
                        text: backend && backend.appVersionInfo ? (backend.appVersionInfo.source === "git" ? "Live Git Worktree" : (backend.appVersionInfo.source === "scm_cache" ? "Build SCM Cache" : "Installed Package Metadata")) : "Git"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }
            }
        }
    }
}
