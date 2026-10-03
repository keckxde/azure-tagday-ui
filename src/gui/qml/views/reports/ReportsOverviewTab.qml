import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

            ScrollView {
    property var root: null

                contentWidth: parent.width
                clip: true

                ColumnLayout {
                    width: parent.width - 20
                    spacing: 20

                    // Report 1: Tag Day
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: tagDayCardCol.implicitHeight + 36
                        height: implicitHeight
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: tagDayCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 12

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "🏷️"
                                    font.pixelSize: 22
                                }

                                Text {
                                    text: "Tag Day Release Report"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    height: 22
                                    width: tagBadgeText.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(88 / 255, 166 / 255, 255 / 255, 0.15)
                                    border.color: "#388bfd"
                                    border.width: 1
                                    Text {
                                        id: tagBadgeText
                                        anchors.centerIn: parent
                                        text: "SEMANTIC RELEASES"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                }
                            }

                            // Description
                            Text {
                                text: "Evaluates per-repository changes, unmerged branches, and closed PRs against latest semantic tags. Generates Markdown release notes."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Actions inside the card
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

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
                                        implicitHeight: 34
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
                                        implicitHeight: 34
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

                                Button {
                                    text: "👁️ Preview in Sidebar"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 160
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "#161b22"
                                        border.color: "#388bfd"
                                    }
                                    onClicked: {
                                        root.activeReportTab = 0;
                                        root.isTdSidebarOpen = true;
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: "Explore Tag Day ➔"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 150
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: root.activeReportTab = 1
                                }
                            }
                        }
                    }

                    // Report 2: Storage & Artifacts
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: storageCardCol.implicitHeight + 36
                        height: implicitHeight
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: storageCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 12

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "📦"
                                    font.pixelSize: 22
                                }

                                Text {
                                    text: "Build Artifact & Storage Analysis"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    height: 22
                                    width: storageBadgeText.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(163 / 255, 113 / 255, 247 / 255, 0.15)
                                    border.color: "#a371f7"
                                    border.width: 1
                                    Text {
                                        id: storageBadgeText
                                        anchors.centerIn: parent
                                        text: "BUILD STORAGE FOOTPRINT"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#a371f7"
                                    }
                                }
                            }

                            // Description
                            Text {
                                text: "Analyzes all builds in Azure DevOps, detects active vs deleted drop folders, tracks GB storage footprint, and exports Wiki Markdown & CSV."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Actions inside the card
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

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
                                        implicitHeight: 34
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
                                        implicitHeight: 34
                                        implicitWidth: 130
                                        radius: 6
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.open_storage_report_file();
                                    }
                                }

                                Button {
                                    text: "👁️ Preview in Sidebar"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#a371f7"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 160
                                        radius: 6
                                        color: parent.hovered ? "#281b3d" : "#161b22"
                                        border.color: "#a371f7"
                                    }
                                    onClicked: {
                                        root.activeReportTab = 2;
                                        root.isTdSidebarOpen = true;
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: "Explore Storage ➔"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#a371f7"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 145
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: root.activeReportTab = 2
                                }
                            }
                        }
                    }

                    // Report 3: Release Notes & Version History (REVISION.md)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: revCardCol.implicitHeight + 36
                        height: implicitHeight
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: revCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 12

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "📝"
                                    font.pixelSize: 22
                                }

                                Text {
                                    text: "Release Notes & Version Revision"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    height: 22
                                    width: revBadgeText.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(63 / 255, 185 / 255, 80 / 255, 0.15)
                                    border.color: "#3fb950"
                                    border.width: 1
                                    Text {
                                        id: revBadgeText
                                        anchors.centerIn: parent
                                        text: "MULTI-PACKAGE REVISION"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#3fb950"
                                    }
                                }
                            }

                            // Description
                            Text {
                                text: "Evaluates package release status, semantic tags, and merged PR change logs. Generates multi-package REVISION.md release tracking document."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Actions inside the card
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    text: "⚡ Generate Release Notes"
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
                                        implicitHeight: 34
                                        implicitWidth: 195
                                        radius: 6
                                        color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.generate_revision_report_async();
                                    }
                                }

                                Button {
                                    text: "📑 Open REVISION.md"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#f0f6fc"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 165
                                        radius: 6
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend)
                                            backend.open_revision_file();
                                    }
                                }

                                Button {
                                    text: "👁️ Preview in Sidebar"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#3fb950"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 160
                                        radius: 6
                                        color: parent.hovered ? "#1b3823" : "#161b22"
                                        border.color: "#3fb950"
                                    }
                                    onClicked: {
                                        root.activeReportTab = 3;
                                        root.isTdSidebarOpen = true;
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: "Explore Release Notes ➔"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#3fb950"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 170
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: root.activeReportTab = 3
                                }
                            }
                        }
                    }

                    // Report 4: Agile Sprint & Timeframe Report
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: sprintCardCol.implicitHeight + 36
                        height: implicitHeight
                        color: "#161b22"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: sprintCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 12

                            // Top Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "🚀"
                                    font.pixelSize: 22
                                }

                                Text {
                                    text: "Agile Weekly Sprint & Timeframe Report"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    height: 22
                                    width: sprintBadgeText.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(31 / 255, 111 / 255, 235 / 255, 0.15)
                                    border.color: "#388bfd"
                                    border.width: 1
                                    Text {
                                        id: sprintBadgeText
                                        anchors.centerIn: parent
                                        text: "AGILE VELOCITY & DEADLINES"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#58a6ff"
                                    }
                                }
                            }

                            // Description
                            Text {
                                text: "Audits User Stories, Requirements, Bugs, and Tasks scheduled for weekly sprint timeframes (week-YYWW). Tracks milestone deadlines, urgency status, team contribution, and exports Wiki Markdown & flat CSV."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Sprint Selector & Actions
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ComboBox {
                                    id: sprintSelectCombo
                                    implicitWidth: 180
                                    implicitHeight: 34
                                    font.pixelSize: 12
                                    model: (backend && backend.availableSprintList) ? backend.availableSprintList : []
                                    currentIndex: {
                                        if (!backend || !backend.availableSprintList || backend.availableSprintList.length === 0) return 0;
                                        var target = root.selectedSprintReport || root.getDefaultSprint();
                                        var idx = backend.availableSprintList.indexOf(target);
                                        return idx >= 0 ? idx : 0;
                                    }
                                    background: Rectangle {
                                        color: "#0d1117"
                                        radius: 6
                                        border.color: "#30363d"
                                    }
                                    contentItem: Text {
                                        leftPadding: 10
                                        text: sprintSelectCombo.currentText ? ("🎯 " + sprintSelectCombo.currentText) : "Select Sprint..."
                                        font: sprintSelectCombo.font
                                        color: "#58a6ff"
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onActivated: function(index) {
                                        if (backend && backend.availableSprintList && backend.availableSprintList[index]) {
                                            root.selectedSprintReport = backend.availableSprintList[index];
                                        }
                                    }
                                }

                                Button {
                                    text: "⚡ Generate Sprint Report"
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
                                        implicitHeight: 34
                                        implicitWidth: 195
                                        radius: 6
                                        color: parent.enabled ? (parent.hovered ? "#388bfd" : "#1f6feb") : "#30363d"
                                    }
                                    onClicked: {
                                        if (backend) {
                                            var targetSprint = sprintSelectCombo.currentText;
                                            backend.generate_sprint_report_async(targetSprint);
                                        }
                                    }
                                }

                                Button {
                                    text: "📑 Open Markdown"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#f0f6fc"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 145
                                        radius: 6
                                        color: parent.hovered ? "#30363d" : "#21262d"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (backend) {
                                            var targetSprint = sprintSelectCombo.currentText;
                                            backend.open_sprint_report_file(targetSprint);
                                        }
                                    }
                                }

                                Button {
                                    text: "👁️ Preview in Sidebar"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 160
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "#161b22"
                                        border.color: "#388bfd"
                                    }
                                    onClicked: {
                                        var targetSprint = sprintSelectCombo.currentText;
                                        root.openSprintReport(targetSprint);
                                        root.isTdSidebarOpen = true;
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: "Explore Sprint ➔"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 145
                                        radius: 6
                                        color: parent.hovered ? "#212836" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        root.openSprintReport(sprintSelectCombo.currentText);
                                    }
                                }
                            }
                        }
                    }

                    // Direct Shortcut Banner to Standalone Pull Requests Page
                    Rectangle {
                        Layout.fillWidth: true
                        height: 72
                        color: "#0d1117"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 16

                            Text {
                                text: "🔀"
                                font.pixelSize: 24
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "Looking for Pull Requests?"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Text {
                                    text: "The PR browser has been moved to its own standalone page with full pagination, repository filtering, and chronological sorting."
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    color: "#8b949e"
                                }
                            }

                            Button {
                                text: "Go to Pull Requests ➔"
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
                                    implicitWidth: 175
                                    radius: 6
                                    color: parent.hovered ? "#388bfd" : "#1f6feb"
                                }
                                onClicked: {
                                    if (typeof window !== "undefined" && window.navigateToPullRequests) {
                                        window.navigateToPullRequests();
                                    } else if (typeof window !== "undefined") {
                                        window.currentTabIndex = 2;
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        height: 10
                    }
                }
            }
