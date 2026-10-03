import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

ColumnLayout {
    id: tabRoot
    Layout.fillWidth: true
    spacing: 16

    // ==========================================
    // Reports Target & Baseline Directory Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: reportsDirCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: reportsDirCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text { text: "📊"; font.pixelSize: 20 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Reports Target & Baseline Directory"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Configure the target folder for reading baseline reports to extend (such as REVISION.md) and saving generated release reports (TAGDAY.md, REVISION.md/docx, SPRINT_REPORT, BUILD_ARTIFACTS)."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Item { Layout.fillWidth: true }

                // Status Pill
                Rectangle {
                    implicitHeight: 22
                    implicitWidth: reportsDirPillText.implicitWidth + 14
                    radius: 11
                    color: (backend && backend.reportsDir) ? "#16243b" : "#162b20"
                    border.color: (backend && backend.reportsDir) ? "#388bfd" : "#238636"
                    border.width: 1

                    Text {
                        id: reportsDirPillText
                        anchors.centerIn: parent
                        text: (backend && backend.reportsDir) ? "📁 Custom Directory" : "🏠 Default (Current Directory)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: (backend && backend.reportsDir) ? "#58a6ff" : "#3fb950"
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Path Input & Browse Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                TextField {
                    id: reportsDirInput
                    Layout.fillWidth: true
                    implicitHeight: 34
                    font.family: "Consolas, monospace"
                    font.pixelSize: 12
                    text: backend ? (backend.reportsDir || backend.effectiveReportsDir) : ""
                    placeholderText: "e.g. C:/Projects/Reports or relative path (empty for current directory)"
                    placeholderTextColor: "#484f58"
                    color: "#f0f6fc"
                    background: Rectangle {
                        color: "#0d1117"
                        radius: 6
                        border.color: reportsDirInput.activeFocus ? "#58a6ff" : "#30363d"
                        border.width: 1
                    }
                }

                Button {
                    text: "📁 Browse..."
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#f0f6fc"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 105; radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: parent.hovered ? "#58a6ff" : "#30363d"
                        border.width: 1
                    }
                    onClicked: {
                        if (backend) {
                            var chosen = backend.browse_reports_dir();
                            if (chosen) {
                                reportsDirInput.text = chosen;
                                root.bannerMsg = "Reports target directory set to: " + chosen;
                                root.bannerType = "success";
                            }
                        }
                    }
                }

                Button {
                    text: "📂 Open Folder"
                    font.pixelSize: 12
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 110; radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: "#30363d"
                        border.width: 1
                    }
                    onClicked: {
                        if (backend) backend.open_reports_folder();
                    }
                }

                Button {
                    text: "💾 Save"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 80; radius: 6
                        color: parent.hovered ? "#2ea043" : "#238636"
                        border.color: "#3fb950"
                    }
                    onClicked: {
                        if (backend) {
                            backend.setReportsDir(reportsDirInput.text.trim());
                            root.bannerMsg = reportsDirInput.text.trim()
                                ? ("Reports directory saved: " + reportsDirInput.text.trim())
                                : "Reports directory reset to current working directory.";
                            root.bannerType = "success";
                        }
                    }
                }

                Button {
                    text: "↺ Reset"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#8b949e"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 70; radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: "#30363d"
                    }
                    onClicked: {
                        if (backend) {
                            backend.setReportsDir("");
                            reportsDirInput.text = backend.effectiveReportsDir;
                            root.bannerMsg = "Reports target directory reset to default (current directory).";
                            root.bannerType = "info";
                        }
                    }
                }
            }

            // Informational notes row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { text: "ℹ️"; font.pixelSize: 12 }
                Text {
                    text: "Effective path: " + (backend ? backend.effectiveReportsDir : "N/A") + "  •  Applies to TAGDAY.md, REVISION.md, REVISION.docx, SPRINT_REPORT_*.md, RESCHEDULING_REPORT.*, and BUILD_ARTIFACTS.*"
                    font.family: "Consolas, Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }
        }
    }

    // ==========================================
    // Change Notification & Tag Day Filters Card
    // ==========================================
    Rectangle {
        id: changeFilterCard
        Layout.fillWidth: true
        implicitHeight: changeFilterCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        property var repoCatFilters: []
        property var branchFilters: []
        property string newRepoCatPattern: ""
        property string newBranchPattern: ""

        // Sandbox test state
        property string testSampleText: ""
        property string testSampleType: "branch" // "category" or "branch"

        function loadFilters() {
            if (backend) {
                var c = backend.repoCategoryFilterPatterns || [];
                var b = backend.branchFilterPatterns || [];
                repoCatFilters = c.slice();
                branchFilters = b.slice();
            }
        }

        function saveFilters() {
            if (!backend) return;
            var ok = backend.save_change_filters(
                JSON.stringify(repoCatFilters),
                JSON.stringify(branchFilters)
            );
            if (ok) {
                root.bannerMsg = "Change notification filters saved successfully (" + repoCatFilters.length + " category rules, " + branchFilters.length + " branch rules).";
                root.bannerType = "success";
            } else {
                root.bannerMsg = "Failed to save change notification filters.";
                root.bannerType = "error";
            }
        }

        function resetFilters() {
            if (!backend) return;
            var ok = backend.reset_change_filters_to_defaults();
            if (ok) {
                loadFilters();
                root.bannerMsg = "Change notification filters reset to defaults.";
                root.bannerType = "info";
            }
        }

        Component.onCompleted: loadFilters()

        Connections {
            target: backend
            function onChangeFiltersChanged() {
                changeFilterCard.loadFilters();
            }
        }

        ColumnLayout {
            id: changeFilterCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { text: "🔔"; font.pixelSize: 18 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Change Notification & Tag Day Filters"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Define wildcard filters (* and ?) to exclude non-relevant repository categories (e.g. *deprecated*) and branches (e.g. *archive*, *demo*, *test*) from change notifications and Tag Day tracking."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "↺ Reset to Defaults"
                    font.pixelSize: 11
                    ToolTip.visible: hovered
                    ToolTip.text: "Restore default category (*deprecated*) and branch filters"
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#8b949e"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 28; implicitWidth: 130; radius: 5
                        color: parent.hovered ? "#30363d" : "transparent"
                        border.color: "#30363d"
                    }
                    onClicked: changeFilterCard.resetFilters()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // SECTION 1: Repository Category Filters
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: "📁"; font.pixelSize: 14 }
                    Text {
                        text: "Repository Category Filters (Ignore for Change Notifications)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: "#e6edf3"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: changeFilterCard.repoCatFilters.length + " pattern(s)"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }

                Text {
                    text: "Repositories whose category matches these patterns will be excluded from Tag Day change alerts, pending change badges, and the changes timeline."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                // Presets Row for Categories
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: "Suggested Presets (click to add):"; font.pixelSize: 10; color: "#6e7681" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: ["*deprecated*", "*archive*", "*legacy*", "*sandbox*", "*temp*"]
                            Rectangle {
                                implicitHeight: 20
                                implicitWidth: catChipTxt.implicitWidth + 12
                                radius: 10
                                color: "#0d1117"
                                border.color: "#30363d"
                                Text {
                                    id: catChipTxt
                                    anchors.centerIn: parent
                                    text: "+ " + modelData
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 10
                                    color: "#58a6ff"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (changeFilterCard.repoCatFilters.indexOf(modelData) === -1) {
                                            var list = changeFilterCard.repoCatFilters.slice();
                                            list.push(modelData);
                                            changeFilterCard.repoCatFilters = list;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Category Patterns Table
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: changeFilterCard.repoCatFilters

                        delegate: Rectangle {
                            id: catFilterRow
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: 4
                            color: catRowMa.containsMouse ? "#1c2128" : "#0d1117"
                            border.color: "#21262d"
                            property int rowIndex: index

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Text {
                                    text: (catFilterRow.rowIndex + 1) + "."
                                    font.pixelSize: 11
                                    color: "#484f58"
                                    Layout.preferredWidth: 20
                                }

                                TextField {
                                    id: catPatField
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    text: modelData
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 11
                                    color: "#e3b341"
                                    background: Rectangle {
                                        color: catPatField.activeFocus ? "#2d2305" : "transparent"
                                        radius: 4
                                        border.color: catPatField.activeFocus ? "#d29922" : "transparent"
                                    }
                                    onEditingFinished: {
                                        var list = changeFilterCard.repoCatFilters.slice();
                                        list[catFilterRow.rowIndex] = text.trim();
                                        changeFilterCard.repoCatFilters = list;
                                    }
                                }

                                // Move up / down / remove
                                RowLayout {
                                    spacing: 4
                                    Layout.preferredWidth: 54

                                    Text {
                                        text: "↑"
                                        font.pixelSize: 13
                                        color: upCatMa.containsMouse ? "#79c0ff" : "#484f58"
                                        visible: catFilterRow.rowIndex > 0
                                        MouseArea {
                                            id: upCatMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var list = changeFilterCard.repoCatFilters.slice();
                                                var tmp = list[catFilterRow.rowIndex - 1];
                                                list[catFilterRow.rowIndex - 1] = list[catFilterRow.rowIndex];
                                                list[catFilterRow.rowIndex] = tmp;
                                                changeFilterCard.repoCatFilters = list;
                                            }
                                        }
                                    }

                                    Text {
                                        text: "↓"
                                        font.pixelSize: 13
                                        color: downCatMa.containsMouse ? "#79c0ff" : "#484f58"
                                        visible: catFilterRow.rowIndex < changeFilterCard.repoCatFilters.length - 1
                                        MouseArea {
                                            id: downCatMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var list = changeFilterCard.repoCatFilters.slice();
                                                var tmp = list[catFilterRow.rowIndex + 1];
                                                list[catFilterRow.rowIndex + 1] = list[catFilterRow.rowIndex];
                                                list[catFilterRow.rowIndex] = tmp;
                                                changeFilterCard.repoCatFilters = list;
                                            }
                                        }
                                    }

                                    Text {
                                        text: "✕"
                                        font.pixelSize: 12
                                        color: remCatMa.containsMouse ? "#f85149" : "#484f58"
                                        MouseArea {
                                            id: remCatMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var list = changeFilterCard.repoCatFilters.slice();
                                                list.splice(catFilterRow.rowIndex, 1);
                                                changeFilterCard.repoCatFilters = list;
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: catRowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: true
                                cursorShape: Qt.ArrowCursor
                            }
                        }
                    }

                    Text {
                        visible: changeFilterCard.repoCatFilters.length === 0
                        text: "No category filters configured. All repository categories will be tracked for changes."
                        font.pixelSize: 11
                        color: "#484f58"
                    }
                }

                // Add Category Pattern Row
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 4
                    color: "#0d1117"
                    border.color: "#30363d"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 8

                        Text { text: "+"; font.pixelSize: 15; font.weight: Font.Bold; color: "#e3b341" }

                        TextField {
                            id: addCatPatInput
                            Layout.fillWidth: true
                            implicitHeight: 26
                            text: changeFilterCard.newRepoCatPattern
                            font.family: "Consolas, monospace"
                            font.pixelSize: 11
                            color: "#e3b341"
                            placeholderText: "New category pattern (e.g. *deprecated* or ARCHIVE*)"
                            placeholderTextColor: "#484f58"
                            background: Rectangle { color: "transparent" }
                            onTextChanged: changeFilterCard.newRepoCatPattern = text
                            Keys.onReturnPressed: addCatBtn.clicked()
                        }

                        Button {
                            id: addCatBtn
                            text: "Add Pattern"
                            enabled: changeFilterCard.newRepoCatPattern.trim() !== ""
                            font.pixelSize: 11
                            contentItem: Text {
                                text: parent.text; font: parent.font; color: parent.enabled ? "#ffffff" : "#484f58"
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 24; implicitWidth: 85; radius: 4
                                color: parent.enabled ? (parent.hovered ? "#d29922" : "#9e6a03") : "#21262d"
                            }
                            onClicked: {
                                var p = changeFilterCard.newRepoCatPattern.trim();
                                if (p && changeFilterCard.repoCatFilters.indexOf(p) === -1) {
                                    var list = changeFilterCard.repoCatFilters.slice();
                                    list.push(p);
                                    changeFilterCard.repoCatFilters = list;
                                    changeFilterCard.newRepoCatPattern = "";
                                    addCatPatInput.text = "";
                                    addCatPatInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // SECTION 2: Branch Change Filters
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: "🌿"; font.pixelSize: 14 }
                    Text {
                        text: "Git Branch Filters (Ignore for Ahead & Change Tracking)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: "#e6edf3"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: changeFilterCard.branchFilters.length + " pattern(s)"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }

                Text {
                    text: "Branches matching these patterns will NOT be considered as changes (ignored in unmerged branches tables and timeline)."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                // Presets Row for Branches
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: "Suggested Presets (click to add):"; font.pixelSize: 10; color: "#6e7681" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: ["*archive*", "archive/*", "*demo*", "demo/*", "*deprecated*", "*test*", "test/*", "*backup*", "*poc*", "*temp*"]
                            Rectangle {
                                implicitHeight: 20
                                implicitWidth: brChipTxt.implicitWidth + 12
                                radius: 10
                                color: "#0d1117"
                                border.color: "#30363d"
                                Text {
                                    id: brChipTxt
                                    anchors.centerIn: parent
                                    text: "+ " + modelData
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 10
                                    color: "#58a6ff"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (changeFilterCard.branchFilters.indexOf(modelData) === -1) {
                                            var list = changeFilterCard.branchFilters.slice();
                                            list.push(modelData);
                                            changeFilterCard.branchFilters = list;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Branch Patterns Table
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: changeFilterCard.branchFilters

                        delegate: Rectangle {
                            id: brFilterRow
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: 4
                            color: brRowMa.containsMouse ? "#1c2128" : "#0d1117"
                            border.color: "#21262d"
                            property int rowIndex: index

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Text {
                                    text: (brFilterRow.rowIndex + 1) + "."
                                    font.pixelSize: 11
                                    color: "#484f58"
                                    Layout.preferredWidth: 20
                                }

                                TextField {
                                    id: brPatField
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    text: modelData
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 11
                                    color: "#58a6ff"
                                    background: Rectangle {
                                        color: brPatField.activeFocus ? "#0d2344" : "transparent"
                                        radius: 4
                                        border.color: brPatField.activeFocus ? "#388bfd" : "transparent"
                                    }
                                    onEditingFinished: {
                                        var list = changeFilterCard.branchFilters.slice();
                                        list[brFilterRow.rowIndex] = text.trim();
                                        changeFilterCard.branchFilters = list;
                                    }
                                }

                                // Move up / down / remove
                                RowLayout {
                                    spacing: 4
                                    Layout.preferredWidth: 54

                                    Text {
                                        text: "↑"
                                        font.pixelSize: 13
                                        color: upBrMa.containsMouse ? "#79c0ff" : "#484f58"
                                        visible: brFilterRow.rowIndex > 0
                                        MouseArea {
                                            id: upBrMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var list = changeFilterCard.branchFilters.slice();
                                                var tmp = list[brFilterRow.rowIndex - 1];
                                                list[brFilterRow.rowIndex - 1] = list[brFilterRow.rowIndex];
                                                list[brFilterRow.rowIndex] = tmp;
                                                changeFilterCard.branchFilters = list;
                                            }
                                        }
                                    }

                                    Text {
                                        text: "↓"
                                        font.pixelSize: 13
                                        color: downBrMa.containsMouse ? "#79c0ff" : "#484f58"
                                        visible: brFilterRow.rowIndex < changeFilterCard.branchFilters.length - 1
                                        MouseArea {
                                            id: downBrMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var list = changeFilterCard.branchFilters.slice();
                                                var tmp = list[brFilterRow.rowIndex + 1];
                                                list[brFilterRow.rowIndex + 1] = list[brFilterRow.rowIndex];
                                                list[brFilterRow.rowIndex] = tmp;
                                                changeFilterCard.branchFilters = list;
                                            }
                                        }
                                    }

                                    Text {
                                        text: "✕"
                                        font.pixelSize: 12
                                        color: remBrMa.containsMouse ? "#f85149" : "#484f58"
                                        MouseArea {
                                            id: remBrMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var list = changeFilterCard.branchFilters.slice();
                                                list.splice(brFilterRow.rowIndex, 1);
                                                changeFilterCard.branchFilters = list;
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: brRowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: true
                                cursorShape: Qt.ArrowCursor
                            }
                        }
                    }

                    Text {
                        visible: changeFilterCard.branchFilters.length === 0
                        text: "No branch filters configured. All branches with ahead commits will be shown as unmerged."
                        font.pixelSize: 11
                        color: "#484f58"
                    }
                }

                // Add Branch Pattern Row
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 4
                    color: "#0d1117"
                    border.color: "#30363d"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 8

                        Text { text: "+"; font.pixelSize: 15; font.weight: Font.Bold; color: "#58a6ff" }

                        TextField {
                            id: addBrPatInput
                            Layout.fillWidth: true
                            implicitHeight: 26
                            text: changeFilterCard.newBranchPattern
                            font.family: "Consolas, monospace"
                            font.pixelSize: 11
                            color: "#58a6ff"
                            placeholderText: "New branch pattern (e.g. *archive*, archive/*, or *demo*)"
                            placeholderTextColor: "#484f58"
                            background: Rectangle { color: "transparent" }
                            onTextChanged: changeFilterCard.newBranchPattern = text
                            Keys.onReturnPressed: addBrBtn.clicked()
                        }

                        Button {
                            id: addBrBtn
                            text: "Add Pattern"
                            enabled: changeFilterCard.newBranchPattern.trim() !== ""
                            font.pixelSize: 11
                            contentItem: Text {
                                text: parent.text; font: parent.font; color: parent.enabled ? "#ffffff" : "#484f58"
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 24; implicitWidth: 85; radius: 4
                                color: parent.enabled ? (parent.hovered ? "#1f6feb" : "#238636") : "#21262d"
                            }
                            onClicked: {
                                var p = changeFilterCard.newBranchPattern.trim();
                                if (p && changeFilterCard.branchFilters.indexOf(p) === -1) {
                                    var list = changeFilterCard.branchFilters.slice();
                                    list.push(p);
                                    changeFilterCard.branchFilters = list;
                                    changeFilterCard.newBranchPattern = "";
                                    addBrPatInput.text = "";
                                    addBrPatInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // SECTION 3: Interactive Pattern Matcher Sandbox
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sandboxCol.implicitHeight + 20
                radius: 6
                color: "#0d1117"
                border.color: "#21262d"
                border.width: 1

                ColumnLayout {
                    id: sandboxCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        spacing: 6
                        Text { text: "🧪"; font.pixelSize: 14 }
                        Text {
                            text: "Filter Rule Test Sandbox"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        TextField {
                            id: testInput
                            Layout.fillWidth: true
                            implicitHeight: 30
                            font.family: "Consolas, monospace"
                            font.pixelSize: 11
                            placeholderText: "Type sample branch or category name (e.g. archive/feature-1 or Deprecated)"
                            placeholderTextColor: "#484f58"
                            color: "#f0f6fc"
                            background: Rectangle { color: "#161b22"; radius: 4; border.color: "#30363d" }
                            onTextChanged: changeFilterCard.testSampleText = text
                        }

                        // Match status badge
                        Rectangle {
                            property bool isMatched: {
                                var val = testInput.text.trim();
                                if (!val) return false;
                                if (backend) {
                                    for (var i = 0; i < changeFilterCard.repoCatFilters.length; i++) {
                                        if (backend.test_pattern_match(changeFilterCard.repoCatFilters[i], val)) return true;
                                    }
                                    for (var j = 0; j < changeFilterCard.branchFilters.length; j++) {
                                        if (backend.test_pattern_match(changeFilterCard.branchFilters[j], val)) return true;
                                    }
                                }
                                return false;
                            }

                            implicitHeight: 30
                            implicitWidth: 140
                            radius: 4
                            color: testInput.text.trim() === "" ? "#21262d" : (isMatched ? "#3c1e1e" : "#162b20")
                            border.color: testInput.text.trim() === "" ? "#30363d" : (isMatched ? "#f85149" : "#238636")
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: testInput.text.trim() === "" ? "Enter test text" : (parent.isMatched ? "🚫 Excluded (Ignored)" : "✓ Included (Active)")
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: testInput.text.trim() === "" ? "#8b949e" : (parent.isMatched ? "#f85149" : "#3fb950")
                            }
                        }
                    }
                }
            }

            // Bottom Save Row
            RowLayout {
                Layout.topMargin: 4
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: (changeFilterCard.repoCatFilters.length + changeFilterCard.branchFilters.length) + " total rule(s) configured"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                Button {
                    text: "💾 Save Filter Rules"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 160; radius: 6
                        color: parent.hovered ? "#1f6feb" : "#238636"
                        border.color: "#3fb950"
                    }
                    onClicked: changeFilterCard.saveFilters()
                }
            }
        }
    }
}
