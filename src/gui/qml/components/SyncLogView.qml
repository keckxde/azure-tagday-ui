import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."

Item {
    id: root

    // Customization properties
    property string activeSeverityFilter: "ALL" // "ALL", "INFO", "WARNING", "ERROR"
    property string searchKeyword: ""
    property bool autoScroll: true
    property bool showHeaderTitle: true
    property string headerTitleText: "Activity & Sync Log"

    // Signal when close is requested (for drawer mode)
    signal closeRequested()
    property bool canClose: false

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ==========================================
        // Toolbar / Controls Header
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 46
            color: "#161b22"
            radius: 6
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                // Header Title
                Row {
                    spacing: 8
                    visible: root.showHeaderTitle
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: "💻"
                        font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.headerTitleText
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: "#f0f6fc"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Live pulse indicator
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: backend && backend.isBusy ? "#d29922" : "#3fb950"
                        anchors.verticalCenter: parent.verticalCenter
                        
                        SequentialAnimation on opacity {
                            running: backend && backend.isBusy
                            loops: Animation.Infinite
                            PropertyAnimation { to: 0.3; duration: 600 }
                            PropertyAnimation { to: 1.0; duration: 600 }
                        }
                    }
                }

                // Divider
                Rectangle {
                    width: 1
                    height: 20
                    color: "#30363d"
                    visible: root.showHeaderTitle
                }

                // ==========================================
                // Severity Filter Buttons
                // ==========================================
                RowLayout {
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter

                    // ALL Filter
                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: allFilterText.implicitWidth + 16
                        radius: 4
                        color: root.activeSeverityFilter === "ALL" ? "#30363d" : (allMa.containsMouse ? "#21262d" : "transparent")
                        border.color: root.activeSeverityFilter === "ALL" ? "#58a6ff" : "#30363d"
                        border.width: 1

                        Text {
                            id: allFilterText
                            anchors.centerIn: parent
                            text: "All (" + (backend && backend.logCounts ? backend.logCounts.all : logModel.count) + ")"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: root.activeSeverityFilter === "ALL" ? Font.DemiBold : Font.Normal
                            color: root.activeSeverityFilter === "ALL" ? "#ffffff" : "#8b949e"
                        }

                        MouseArea {
                            id: allMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeSeverityFilter = "ALL"
                        }
                    }

                    // INFO Filter
                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: infoFilterText.implicitWidth + 16
                        radius: 4
                        color: root.activeSeverityFilter === "INFO" ? "#16243b" : (infoMa.containsMouse ? "#21262d" : "transparent")
                        border.color: root.activeSeverityFilter === "INFO" ? "#388bfd" : "#30363d"
                        border.width: 1

                        Text {
                            id: infoFilterText
                            anchors.centerIn: parent
                            text: "ℹ️ Info (" + (backend && backend.logCounts ? backend.logCounts.info : 0) + ")"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: root.activeSeverityFilter === "INFO" ? Font.DemiBold : Font.Normal
                            color: root.activeSeverityFilter === "INFO" ? "#58a6ff" : "#8b949e"
                        }

                        MouseArea {
                            id: infoMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeSeverityFilter = "INFO"
                        }
                    }

                    // WARNING Filter
                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: warnFilterText.implicitWidth + 16
                        radius: 4
                        color: root.activeSeverityFilter === "WARNING" ? "#382a0d" : (warnMa.containsMouse ? "#21262d" : "transparent")
                        border.color: root.activeSeverityFilter === "WARNING" ? "#d29922" : "#30363d"
                        border.width: 1

                        Text {
                            id: warnFilterText
                            anchors.centerIn: parent
                            text: "⚠️ Warning (" + (backend && backend.logCounts ? backend.logCounts.warning : 0) + ")"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: root.activeSeverityFilter === "WARNING" ? Font.DemiBold : Font.Normal
                            color: root.activeSeverityFilter === "WARNING" ? "#e3b341" : "#8b949e"
                        }

                        MouseArea {
                            id: warnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeSeverityFilter = "WARNING"
                        }
                    }

                    // ERROR Filter
                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: errFilterText.implicitWidth + 16
                        radius: 4
                        color: root.activeSeverityFilter === "ERROR" ? "#3c1e1e" : (errMa.containsMouse ? "#21262d" : "transparent")
                        border.color: root.activeSeverityFilter === "ERROR" ? "#f85149" : "#30363d"
                        border.width: 1

                        Text {
                            id: errFilterText
                            anchors.centerIn: parent
                            text: "❌ Error (" + (backend && backend.logCounts ? backend.logCounts.error : 0) + ")"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: root.activeSeverityFilter === "ERROR" ? Font.DemiBold : Font.Normal
                            color: root.activeSeverityFilter === "ERROR" ? "#f85149" : "#8b949e"
                        }

                        MouseArea {
                            id: errMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeSeverityFilter = "ERROR"
                        }
                    }
                }

                // ==========================================
                // Keyword Search Box
                // ==========================================
                Rectangle {
                    Layout.preferredWidth: 170
                    Layout.fillWidth: false
                    implicitHeight: 28
                    color: "#0d1117"
                    radius: 4
                    border.color: logSearchInput.activeFocus ? "#58a6ff" : "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 4

                        Text {
                            text: "🔍"
                            font.pixelSize: 10
                            color: "#8b949e"
                        }

                        TextInput {
                            id: logSearchInput
                            Layout.fillWidth: true
                            text: root.searchKeyword
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#f0f6fc"
                            selectByMouse: true
                            onTextChanged: root.searchKeyword = text

                            Text {
                                text: "Filter text..."
                                font: parent.font
                                color: "#484f58"
                                visible: !parent.text && !parent.activeFocus
                            }
                        }

                        Text {
                            text: "✕"
                            font.pixelSize: 10
                            color: "#8b949e"
                            visible: root.searchKeyword !== ""
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    logSearchInput.text = "";
                                    root.searchKeyword = "";
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // ==========================================
                // Actions (Auto-Scroll, Copy, Clear, Close)
                // ==========================================
                RowLayout {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter

                    // Auto-scroll toggle button
                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: autoScrollText.implicitWidth + 14
                        radius: 4
                        color: root.autoScroll ? "#21262d" : "transparent"
                        border.color: root.autoScroll ? "#3fb950" : "#30363d"
                        border.width: 1

                        Text {
                            id: autoScrollText
                            anchors.centerIn: parent
                            text: root.autoScroll ? "📌 Scroll: ON" : "📌 Scroll: OFF"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: root.autoScroll ? "#3fb950" : "#8b949e"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.autoScroll = !root.autoScroll
                        }
                    }

                    // Copy logs button
                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: copyLogText.implicitWidth + 14
                        radius: 4
                        color: copyMa.containsMouse ? "#30363d" : "#21262d"
                        border.color: "#30363d"
                        border.width: 1

                        Text {
                            id: copyLogText
                            anchors.centerIn: parent
                            text: "📋 Copy"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#c9d1d9"
                        }

                        MouseArea {
                            id: copyMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var lines = [];
                                for (var i = 0; i < logModel.count; ++i) {
                                    var item = logModel.get(i);
                                    if (matchesFilter(item.level, item.text)) {
                                        lines.push(item.text);
                                    }
                                }
                                if (backend) {
                                    backend.copy_to_clipboard(lines.join("\n"));
                                }
                            }
                        }
                    }

                    // Clear logs button
                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: clearLogText.implicitWidth + 14
                        radius: 4
                        color: clearMa.containsMouse ? "#3c1e1e" : "transparent"
                        border.color: "#30363d"
                        border.width: 1

                        Text {
                            id: clearLogText
                            anchors.centerIn: parent
                            text: "🗑️ Clear"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: clearMa.containsMouse ? "#f85149" : "#8b949e"
                        }

                        MouseArea {
                            id: clearMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                logModel.clear();
                                if (backend) backend.clear_logs();
                            }
                        }
                    }

                    // Optional Close button (for slide-up drawer)
                    Rectangle {
                        visible: root.canClose
                        implicitHeight: 28
                        implicitWidth: 28
                        radius: 4
                        color: closeMa.containsMouse ? "#30363d" : "transparent"
                        border.color: "#30363d"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#8b949e"
                        }

                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeRequested()
                        }
                    }
                }
            }
        }

        // ==========================================
        // Log Viewport Terminal Area
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#090d13"
            radius: 6
            border.color: "#30363d"
            border.width: 1
            clip: true

            ListView {
                id: logListView
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    id: vScrollBar
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: "#30363d"
                    }
                }

                model: ListModel {
                    id: logModel
                }

                delegate: Item {
                    id: logItemDelegate
                    width: logListView.width - 12
                    visible: root.matchesFilter(model.level, model.text)
                    height: visible ? logContentLayout.implicitHeight + 4 : 0

                    RowLayout {
                        id: logContentLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        // 1. Timestamp
                        Text {
                            text: model.timestamp || "--:--:--"
                            font.family: "Consolas, 'Courier New', monospace"
                            font.pixelSize: 11
                            color: "#6e7681"
                            Layout.preferredWidth: 60
                        }

                        // 2. Severity Badge Pill
                        Rectangle {
                            implicitHeight: 18
                            implicitWidth: severityText.implicitWidth + 8
                            radius: 3
                            color: model.level === "ERROR" ? "#3c1e1e" :
                                   (model.level === "WARNING" ? "#382a0d" : "#16243b")
                            border.color: model.level === "ERROR" ? "#f85149" :
                                          (model.level === "WARNING" ? "#d29922" : "#388bfd")
                            border.width: 1
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                id: severityText
                                anchors.centerIn: parent
                                text: model.level === "WARNING" ? "WARN" : (model.level || "INFO")
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: model.level === "ERROR" ? "#f85149" :
                                       (model.level === "WARNING" ? "#e3b341" : "#58a6ff")
                            }
                        }

                        // 3. Logger Source Tag
                        Text {
                            text: model.logger ? ("[" + model.logger + "]") : ""
                            font.family: "Consolas, 'Courier New', monospace"
                            font.pixelSize: 10
                            color: "#79c0ff"
                            visible: model.logger !== "" && model.logger !== undefined
                            Layout.preferredWidth: Math.min(implicitWidth, 120)
                            elide: Text.ElideRight
                        }

                        // 4. Log Message Text
                        Text {
                            text: model.message || model.text
                            font.family: "Consolas, 'Courier New', monospace"
                            font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere
                            Layout.fillWidth: true
                            color: model.level === "ERROR" ? "#f85149" :
                                   (model.level === "WARNING" ? "#e3b341" :
                                    (model.text && model.text.indexOf("COMPLETED") !== -1 ? "#3fb950" : "#c9d1d9"))
                        }
                    }
                }

                // Empty state overlay
                Item {
                    anchors.fill: parent
                    visible: logModel.count === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "📝"
                            font.pixelSize: 24
                            Layout.alignment: Qt.AlignHCenter
                            opacity: 0.6
                        }

                        Text {
                            text: "No log entries recorded yet"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    // Helper filter function
    function matchesFilter(level, text) {
        var normLevel = (level || "INFO").toUpperCase();
        if (normLevel === "WARN") normLevel = "WARNING";
        if (normLevel === "CRITICAL") normLevel = "ERROR";

        // Check severity filter
        if (root.activeSeverityFilter !== "ALL") {
            if (normLevel !== root.activeSeverityFilter) {
                return false;
            }
        }

        // Check text keyword search
        if (root.searchKeyword && root.searchKeyword.trim() !== "") {
            var kw = root.searchKeyword.toLowerCase();
            var fullText = (text || "").toLowerCase();
            if (fullText.indexOf(kw) === -1) {
                return false;
            }
        }

        return true;
    }

    // Load initial logs from backend if present
    Component.onCompleted: {
        if (backend && backend.syncLogs) {
            var existing = backend.syncLogs;
            for (var i = 0; i < existing.length; ++i) {
                logModel.append(existing[i]);
            }
            if (root.autoScroll) {
                Qt.callLater(function() {
                    logListView.positionViewAtEnd();
                });
            }
        }
    }

    // Reactive Connections to Backend
    Connections {
        target: backend

        function onLogRecord(timestamp, level, loggerName, message) {
            var normLevel = (level || "INFO").toUpperCase();
            if (normLevel === "WARN") normLevel = "WARNING";
            if (normLevel === "CRITICAL") normLevel = "ERROR";

            var fullText = "[" + timestamp + "] [" + normLevel + "] " + (loggerName ? "[" + loggerName + "] " : "") + message;

            logModel.append({
                "timestamp": timestamp,
                "level": normLevel,
                "logger": loggerName,
                "message": message,
                "text": fullText
            });

            // Auto-scroll if enabled and if item matches current filter
            if (root.autoScroll && root.matchesFilter(normLevel, fullText)) {
                Qt.callLater(function () {
                    logListView.positionViewAtEnd();
                });
            }
        }

        function onLogMessage(msg) {
            // Fallback for direct string logMessage emissions if not handled via onLogRecord
            // Check if it already looks like a formatted message
            var ts = "";
            var lvl = "INFO";
            var textOnly = msg;

            if (msg.indexOf("[ERROR]") !== -1 || msg.indexOf("FAILED") !== -1 || msg.indexOf("Error") !== -1) {
                lvl = "ERROR";
            } else if (msg.indexOf("[WARN") !== -1 || msg.indexOf("Warning") !== -1) {
                lvl = "WARNING";
            }

            // Extract timestamp if present [HH:MM:SS]
            var m = msg.match(/^\[(\d{2}:\d{2}:\d{2})\]/);
            if (m) {
                ts = m[1];
            } else {
                var d = new Date();
                ts = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2) + ":" + ("0" + d.getSeconds()).slice(-2);
            }

            // Only append if logRecord wasn't already triggered for this exact formatted line
            // Check last entry to prevent duplication
            if (logModel.count > 0) {
                var last = logModel.get(logModel.count - 1);
                if (last && last.text === msg) {
                    return;
                }
            }

            logModel.append({
                "timestamp": ts,
                "level": lvl,
                "logger": "gui",
                "message": msg,
                "text": msg
            });

            if (root.autoScroll && root.matchesFilter(lvl, msg)) {
                Qt.callLater(function () {
                    logListView.positionViewAtEnd();
                });
            }
        }
    }
}
