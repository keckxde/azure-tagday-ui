import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root

    property int workItemId: 0
    property string workItemTitle: ""
    property string currentDeadline: ""
    property string sprintEndDate: ""

    signal deadlineUpdated(int id, string newDate, var result)
    signal openMilestonesManagerRequested()

    title: ""
    modal: true
    dim: true
    anchors.centerIn: parent
    width: 580
    height: Math.min(680, contentCol.implicitHeight + 40)
    padding: 20

    background: Rectangle {
        color: "#161b22"
        radius: 10
        border.color: "#30363d"
        border.width: 1
    }

    function formatDate(d) {
        var y = d.getFullYear();
        var m = (d.getMonth() + 1).toString().padStart(2, '0');
        var day = d.getDate().toString().padStart(2, '0');
        return y + "-" + m + "-" + day;
    }

    function getTodayStr() {
        return formatDate(new Date());
    }

    function getOffsetDateStr(days) {
        var d = new Date();
        d.setDate(d.getDate() + days);
        return formatDate(d);
    }

    function openForWorkItem(id, titleText, deadlineStr, sprintFriday) {
        workItemId = id;
        workItemTitle = titleText || ("Work Item #" + id);
        currentDeadline = (deadlineStr || "").split("T")[0].split(" ")[0];
        sprintEndDate = sprintFriday || "";
        dateInput.text = currentDeadline;
        statusFeedback.text = "";
        isSaving = false;
        open();
    }

    property bool isSaving: false
    property string selectedMilestoneCatFilter: "ALL"

    contentItem: ScrollView {
        id: scrollArea
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            id: contentCol
            width: scrollArea.width - 10
            spacing: 14

            // Title & Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "🎯"
                    font.pixelSize: 22
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Edit Milestone Deadline"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }

                    Text {
                        text: "#" + root.workItemId + " — " + root.workItemTitle
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Button {
                    text: "⚙️ Milestones"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#58a6ff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitWidth: 105
                        implicitHeight: 26
                        radius: 4
                        color: parent.hovered ? "#21262d" : "#0d1117"
                        border.color: "#30363d"
                    }
                    onClicked: {
                        root.openMilestonesManagerRequested();
                        if (typeof window !== "undefined" && window.openMilestonesManager) {
                            window.openMilestonesManager();
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#30363d"
            }

            // ==========================================
            // Major Milestones Selector Section
            // ==========================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "MAJOR MILESTONES (SELECT TO APPLY)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: "#e6edf3"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: (backend && backend.milestones ? backend.milestones.length : 0) + " configured"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 10
                        color: "#8b949e"
                    }
                }

                // Category Filter Pills for Milestones
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: (backend && backend.milestoneCategories && backend.milestoneCategories.length > 0)

                    Rectangle {
                        property bool isCur: root.selectedMilestoneCatFilter === "ALL"
                        implicitWidth: allTxt.implicitWidth + 14
                        implicitHeight: 22
                        radius: 11
                        color: isCur ? "#1f6feb" : (allMa.containsMouse ? "#21262d" : "#0d1117")
                        border.color: isCur ? "#388bfd" : "#30363d"

                        Text {
                            id: allTxt
                            anchors.centerIn: parent
                            text: "All Categories"
                            font.pixelSize: 10
                            font.weight: parent.isCur ? Font.Bold : Font.Normal
                            color: parent.isCur ? "#ffffff" : "#8b949e"
                        }
                        MouseArea {
                            id: allMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedMilestoneCatFilter = "ALL"
                        }
                    }

                    Repeater {
                        model: (backend && backend.milestoneCategories) ? backend.milestoneCategories : []
                        Rectangle {
                            property bool isCur: root.selectedMilestoneCatFilter === modelData.id
                            implicitWidth: catChipRow.implicitWidth + 14
                            implicitHeight: 22
                            radius: 11
                            color: isCur ? (modelData.bg_color || "#1f6feb") : (catMa.containsMouse ? "#21262d" : "#0d1117")
                            border.color: isCur ? (modelData.color || "#388bfd") : "#30363d"
                            border.width: isCur ? 1.5 : 1

                            Row {
                                id: catChipRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: modelData.icon || "🚩"
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: modelData.name
                                    font.pixelSize: 10
                                    font.weight: parent.parent.isCur ? Font.Bold : Font.Normal
                                    color: parent.parent.isCur ? (modelData.color || "#ffffff") : "#8b949e"
                                }
                            }
                            MouseArea {
                                id: catMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedMilestoneCatFilter = modelData.id
                            }
                        }
                    }
                }

                // Milestones Grid/Flow
                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: {
                            if (!backend || !backend.milestones) return [];
                            if (root.selectedMilestoneCatFilter === "ALL") return backend.milestones;
                            var res = [];
                            for (var i = 0; i < backend.milestones.length; i++) {
                                var m = backend.milestones[i];
                                if (m.category_id === root.selectedMilestoneCatFilter) {
                                    res.push(m);
                                }
                            }
                            return res;
                        }

                        Rectangle {
                            id: mChip
                            property bool isSelected: (dateInput.text.trim() === modelData.target_date)
                            implicitHeight: 30
                            implicitWidth: mChipRow.implicitWidth + 18
                            radius: 6
                            color: isSelected ? (modelData.category_bg_color || "#0d2344") : (mChipMa.containsMouse ? "#21262d" : "#0d1117")
                            border.color: isSelected ? (modelData.category_color || "#1f6feb") : "#30363d"
                            border.width: isSelected ? 2 : 1

                            Row {
                                id: mChipRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: modelData.category_icon || "🚩"
                                    font.pixelSize: 12
                                }

                                Text {
                                    text: modelData.name
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: mChip.isSelected ? Font.Bold : Font.DemiBold
                                    color: mChip.isSelected ? (modelData.category_color || "#58a6ff") : "#e6edf3"
                                }

                                Rectangle {
                                    implicitHeight: 18
                                    implicitWidth: dateBadgeText.implicitWidth + 8
                                    radius: 9
                                    color: mChip.isSelected ? Qt.darker(modelData.category_color || "#1f6feb", 2.0) : "#161b22"
                                    border.color: "#30363d"

                                    Text {
                                        id: dateBadgeText
                                        anchors.centerIn: parent
                                        text: modelData.target_date
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 10
                                        color: mChip.isSelected ? "#ffffff" : "#8b949e"
                                    }
                                }
                            }

                            MouseArea {
                                id: mChipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dateInput.text = modelData.target_date;
                                }
                            }

                            ToolTip.visible: mChipMa.containsMouse
                            ToolTip.text: modelData.name + " (" + (modelData.category_name || "Milestone") + ")\nDate: " + modelData.target_date + (modelData.description ? ("\n" + modelData.description) : "")
                        }
                    }
                }
            }

            // Quick Preset Chips
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "QUICK PRESETS"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: "#8b949e"
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    // Sprint Friday (if available)
                    Button {
                        visible: root.sprintEndDate !== ""
                        text: "📅 Sprint End (" + root.sprintEndDate + ")"
                        font.pixelSize: 11
                        contentItem: Text { text: parent.text; font: parent.font; color: "#58a6ff" }
                        background: Rectangle {
                            implicitHeight: 26; implicitWidth: 155; radius: 13
                            color: parent.hovered ? "#0d2344" : "#16243b"
                            border.color: "#1f6feb"
                        }
                        onClicked: { dateInput.text = root.sprintEndDate }
                    }

                    // Today
                    Button {
                        text: "⚡ Today (" + root.getTodayStr() + ")"
                        font.pixelSize: 11
                        contentItem: Text { text: parent.text; font: parent.font; color: "#d29922" }
                        background: Rectangle {
                            implicitHeight: 26; implicitWidth: 130; radius: 13
                            color: parent.hovered ? "#2e210a" : "#1f1708"
                            border.color: "#9e6a03"
                        }
                        onClicked: { dateInput.text = root.getTodayStr() }
                    }

                    // +1 Week
                    Button {
                        text: "⏳ +1 Week"
                        font.pixelSize: 11
                        contentItem: Text { text: parent.text; font: parent.font; color: "#79c0ff" }
                        background: Rectangle {
                            implicitHeight: 26; implicitWidth: 85; radius: 13
                            color: parent.hovered ? "#21262d" : "#0d1117"
                            border.color: "#30363d"
                        }
                        onClicked: { dateInput.text = root.getOffsetDateStr(7) }
                    }

                    // +2 Weeks
                    Button {
                        text: "🔮 +2 Weeks"
                        font.pixelSize: 11
                        contentItem: Text { text: parent.text; font: parent.font; color: "#79c0ff" }
                        background: Rectangle {
                            implicitHeight: 26; implicitWidth: 90; radius: 13
                            color: parent.hovered ? "#21262d" : "#0d1117"
                            border.color: "#30363d"
                        }
                        onClicked: { dateInput.text = root.getOffsetDateStr(14) }
                    }

                    // Clear
                    Button {
                        text: "❌ Clear Deadline"
                        font.pixelSize: 11
                        contentItem: Text { text: parent.text; font: parent.font; color: "#f85149" }
                        background: Rectangle {
                            implicitHeight: 26; implicitWidth: 115; radius: 13
                            color: parent.hovered ? "#3c1e1e" : "#211515"
                            border.color: "#da3633"
                        }
                        onClicked: { dateInput.text = "" }
                    }
                }
            }

            // Custom Date Field Input
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "TARGET DEADLINE DATE (YYYY-MM-DD)"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: "#8b949e"
                }

                TextField {
                    id: dateInput
                    Layout.fillWidth: true
                    implicitHeight: 34
                    font.family: "Consolas, monospace"
                    font.pixelSize: 13
                    color: "#f0f6fc"
                    placeholderText: "YYYY-MM-DD (e.g. 2026-08-14) or leave empty to clear"
                    placeholderTextColor: "#484f58"
                    background: Rectangle {
                        color: "#0d1117"
                        radius: 6
                        border.color: dateInput.activeFocus ? "#58a6ff" : "#30363d"
                        border.width: 1
                    }
                }

                Text {
                    text: "💡 Synced to TFS attribute (" + (backend && backend.customDeadlineField ? backend.customDeadlineField : "Microsoft.VSTS.Scheduling.TargetDate") + ") and cached locally."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }
            }

            // Status / Feedback message
            Text {
                id: statusFeedback
                Layout.fillWidth: true
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 11
                color: "#3fb950"
                visible: text !== ""
                wrapMode: Text.WordWrap
            }

            // Dialog Action Buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    font.pixelSize: 12
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle {
                        implicitWidth: 80; implicitHeight: 32; radius: 6
                        color: parent.hovered ? "#30363d" : "transparent"
                    }
                    onClicked: root.close()
                }

                Button {
                    id: saveBtn
                    text: root.isSaving ? "Saving..." : "💾 Save & Sync to TFS"
                    enabled: !root.isSaving
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitWidth: 160; implicitHeight: 32; radius: 6
                        color: parent.hovered ? "#1f6feb" : "#238636"
                        border.color: "#3fb950"
                        opacity: parent.enabled ? 1.0 : 0.6
                    }
                    onClicked: {
                        root.isSaving = true;
                        var dateVal = dateInput.text.trim();
                        if (backend) {
                            var res = backend.update_work_item_deadline(root.workItemId, dateVal);
                            root.deadlineUpdated(root.workItemId, dateVal, res);
                            root.close();
                        } else {
                            root.isSaving = false;
                            root.close();
                        }
                    }
                }
            }
        }
    }
}

