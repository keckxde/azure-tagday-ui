import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

Item {
    id: previewPaneRoot

    property var root: null
    property string reportType: "storage" // "storage", "revision", "sprint", "rescheduling", "tagday"
    property string reportParam: ""
    property string customTitle: ""
    property var reportData: null
    property int viewMode: 0 // 0: Formatted Markdown, 1: Raw Monospace Text, 2: Document Info
    property string searchQuery: ""
    property string copyToast: ""

    function loadContent() {
        if (!backend) return;
        var rType = previewPaneRoot.reportType;
        var param = previewPaneRoot.reportParam;
        var res = backend.get_report_content(rType, param);
        previewPaneRoot.reportData = res;
    }

    onReportTypeChanged: loadContent()
    onReportParamChanged: loadContent()

    Component.onCompleted: loadContent()

    Connections {
        target: backend
        function onStorageDataChanged() {
            if (previewPaneRoot.reportType === "storage") previewPaneRoot.loadContent();
        }
        function onSprintReportGenerated(data, mdText) {
            if (previewPaneRoot.reportType === "sprint") previewPaneRoot.loadContent();
        }
        function onTagDayDataChanged() {
            if (previewPaneRoot.reportType === "tagday") previewPaneRoot.loadContent();
        }
    }

    Timer {
        id: toastTimer
        interval: 2200
        onTriggered: previewPaneRoot.copyToast = ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Header Action Bar
        Rectangle {
            Layout.fillWidth: true
            height: 40
            radius: 6
            color: "#0d1117"
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: previewPaneRoot.customTitle || (previewPaneRoot.reportData ? previewPaneRoot.reportData.title : "Report Preview")
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // View Mode Segmented Switcher
                Row {
                    spacing: 2
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 4
                        color: previewPaneRoot.viewMode === 0 ? "#21262d" : "transparent"
                        border.color: previewPaneRoot.viewMode === 0 ? "#388bfd" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "📄"
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Rendered Markdown"
                            onClicked: previewPaneRoot.viewMode = 0
                        }
                    }
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 4
                        color: previewPaneRoot.viewMode === 1 ? "#21262d" : "transparent"
                        border.color: previewPaneRoot.viewMode === 1 ? "#388bfd" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "⌨️"
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Raw Monospace Source"
                            onClicked: previewPaneRoot.viewMode = 1
                        }
                    }
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 4
                        color: previewPaneRoot.viewMode === 2 ? "#21262d" : "transparent"
                        border.color: previewPaneRoot.viewMode === 2 ? "#388bfd" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "ℹ️"
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            ToolTip.visible: containsMouse
                            ToolTip.text: "File Metadata & Stats"
                            onClicked: previewPaneRoot.viewMode = 2
                        }
                    }
                }

                Rectangle { width: 1; height: 18; color: "#30363d" }

                // Refresh Button
                Button {
                    implicitWidth: 26
                    implicitHeight: 26
                    font.pixelSize: 11
                    background: Rectangle {
                        radius: 4
                        color: parent.hovered ? "#30363d" : "transparent"
                    }
                    contentItem: Text {
                        text: "🔄"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: "Reload from disk / cache"
                    onClicked: previewPaneRoot.loadContent()
                }

                // Copy Markdown Button
                Button {
                    implicitWidth: 26
                    implicitHeight: 26
                    font.pixelSize: 11
                    background: Rectangle {
                        radius: 4
                        color: parent.hovered ? "#30363d" : "transparent"
                    }
                    contentItem: Text {
                        text: "📋"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: "Copy Markdown to clipboard"
                    onClicked: {
                        if (previewPaneRoot.reportData && previewPaneRoot.reportData.content) {
                            if (backend && typeof backend.copy_to_clipboard === "function") {
                                backend.copy_to_clipboard(previewPaneRoot.reportData.content);
                            }
                            previewPaneRoot.copyToast = "✅ Markdown copied to clipboard!";
                            toastTimer.restart();
                        }
                    }
                }

                // Open in External Editor
                Button {
                    implicitWidth: 26
                    implicitHeight: 26
                    font.pixelSize: 11
                    background: Rectangle {
                        radius: 4
                        color: parent.hovered ? "#30363d" : "transparent"
                    }
                    contentItem: Text {
                        text: "↗️"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: "Open file in default editor"
                    onClicked: {
                        if (previewPaneRoot.reportData && previewPaneRoot.reportData.file_path && backend) {
                            backend.open_path_in_explorer(previewPaneRoot.reportData.file_path);
                        }
                    }
                }
            }
        }

        // Toast Message Banner if active
        Rectangle {
            Layout.fillWidth: true
            height: 28
            radius: 4
            color: "#1f382b"
            border.color: "#238636"
            visible: previewPaneRoot.copyToast !== ""
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                Text {
                    text: previewPaneRoot.copyToast
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#3fb950"
                    font.weight: Font.DemiBold
                }
            }
        }

        // Search in Preview Bar (visible in mode 0 & 1)
        Rectangle {
            Layout.fillWidth: true
            height: 30
            radius: 5
            color: "#0d1117"
            border.color: previewSearchInput.activeFocus ? "#58a6ff" : "#30363d"
            visible: previewPaneRoot.viewMode !== 2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: "🔍"
                    font.pixelSize: 10
                    color: "#8b949e"
                }

                TextInput {
                    id: previewSearchInput
                    Layout.fillWidth: true
                    color: "#f0f6fc"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    selectByMouse: true
                    clip: true
                    onTextChanged: previewPaneRoot.searchQuery = text

                    Text {
                        text: "Search within report..."
                        color: "#6e7681"
                        font: parent.font
                        visible: !parent.text && !parent.activeFocus
                    }
                }

                Text {
                    text: "✕"
                    font.pixelSize: 10
                    color: "#8b949e"
                    visible: previewSearchInput.text.length > 0
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: previewSearchInput.text = ""
                    }
                }
            }
        }

        // Content Area
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0d1117"
            radius: 6
            border.color: "#30363d"
            border.width: 1
            clip: true

            // Mode 0: Formatted Markdown Render
            Flickable {
                id: mdFlick
                anchors.fill: parent
                anchors.margins: 12
                visible: previewPaneRoot.viewMode === 0
                contentWidth: width
                contentHeight: mdText.implicitHeight + 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    active: true
                    policy: ScrollBar.AsNeeded
                }

                TextEdit {
                    id: mdText
                    width: parent.width - 10
                    text: (previewPaneRoot.reportData && previewPaneRoot.reportData.content) ? previewPaneRoot.reportData.content : "*No content available for this report. Generate it using the buttons in the main view.*"
                    textFormat: TextEdit.MarkdownText
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#c9d1d9"
                    wrapMode: Text.Wrap
                    readOnly: true
                    selectByMouse: true
                }
            }

            // Mode 1: Raw Monospace Source
            Flickable {
                id: rawFlick
                anchors.fill: parent
                anchors.margins: 10
                visible: previewPaneRoot.viewMode === 1
                contentWidth: width
                contentHeight: rawText.implicitHeight + 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    active: true
                    policy: ScrollBar.AsNeeded
                }

                TextEdit {
                    id: rawText
                    width: parent.width - 10
                    text: (previewPaneRoot.reportData && previewPaneRoot.reportData.content) ? previewPaneRoot.reportData.content : ""
                    textFormat: TextEdit.PlainText
                    font.family: "Consolas, monospace"
                    font.pixelSize: 11
                    color: "#79c0ff"
                    wrapMode: Text.Wrap
                    readOnly: true
                    selectByMouse: true
                }
            }

            // Mode 2: File Metadata & Stats
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12
                visible: previewPaneRoot.viewMode === 2

                Text {
                    text: "📊 Report File Metadata"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#30363d"
                }

                RowLayout {
                    spacing: 10
                    Text { text: "File Name:"; color: "#8b949e"; font.pixelSize: 12; Layout.preferredWidth: 90 }
                    Text { text: (previewPaneRoot.reportData && previewPaneRoot.reportData.file_name) || "-"; color: "#f0f6fc"; font.weight: Font.DemiBold; font.pixelSize: 12 }
                }

                RowLayout {
                    spacing: 10
                    Text { text: "Path:"; color: "#8b949e"; font.pixelSize: 12; Layout.preferredWidth: 90 }
                    Text { text: (previewPaneRoot.reportData && previewPaneRoot.reportData.file_path) || "-"; color: "#58a6ff"; font.family: "Consolas, monospace"; font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
                }

                RowLayout {
                    spacing: 10
                    Text { text: "Format:"; color: "#8b949e"; font.pixelSize: 12; Layout.preferredWidth: 90 }
                    StatusBadge { text: (previewPaneRoot.reportData && previewPaneRoot.reportData.format) || "markdown"; badgeColor: "#238636" }
                }

                RowLayout {
                    spacing: 10
                    Text { text: "Line Count:"; color: "#8b949e"; font.pixelSize: 12; Layout.preferredWidth: 90 }
                    Text { text: "" + ((previewPaneRoot.reportData && previewPaneRoot.reportData.line_count) || 0) + " lines"; color: "#f0f6fc"; font.pixelSize: 12 }
                }

                RowLayout {
                    spacing: 10
                    Text { text: "Word Count:"; color: "#8b949e"; font.pixelSize: 12; Layout.preferredWidth: 90 }
                    Text { text: "" + ((previewPaneRoot.reportData && previewPaneRoot.reportData.word_count) || 0) + " words"; color: "#f0f6fc"; font.pixelSize: 12 }
                }

                RowLayout {
                    spacing: 10
                    Text { text: "File Size:"; color: "#8b949e"; font.pixelSize: 12; Layout.preferredWidth: 90 }
                    Text { text: "" + Math.round(((previewPaneRoot.reportData && previewPaneRoot.reportData.size_bytes) || 0) / 1024) + " KB"; color: "#f0f6fc"; font.pixelSize: 12 }
                }

                RowLayout {
                    spacing: 10
                    Text { text: "Last Modified:"; color: "#8b949e"; font.pixelSize: 12; Layout.preferredWidth: 90 }
                    Text { text: (previewPaneRoot.reportData && previewPaneRoot.reportData.modified_at) || "Recently"; color: "#d29922"; font.pixelSize: 12 }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
