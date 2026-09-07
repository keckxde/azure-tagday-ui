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

    title: ""
    modal: true
    dim: true
    anchors.centerIn: parent
    width: 480
    height: contentCol.implicitHeight + 40
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

    contentItem: ColumnLayout {
        id: contentCol
        spacing: 16

        // Title & Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "🎯"
                font.pixelSize: 20
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
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#30363d"
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
