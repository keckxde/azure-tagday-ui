import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root

    property string targetDeadline: ""
    property string startFromSprint: ""
    property bool syncToTfs: true
    property var projectedIterations: []
    property var availableMilestones: backend ? (backend.workItemMilestones || []) : []

    signal iterationsPrepared(var result)

    title: ""
    modal: true
    dim: true
    anchors.centerIn: parent
    width: 540
    height: Math.min(680, contentCol.implicitHeight + 40)
    padding: 20

    background: Rectangle {
        color: "#161b22"
        radius: 10
        border.color: "#30363d"
        border.width: 1
    }

    function openForPreparation(defaultDeadline, defaultStart) {
        targetDeadline = defaultDeadline || "";
        deadlineInput.text = targetDeadline;
        startFromSprint = defaultStart || "";
        startInput.text = startFromSprint;
        updatePreview();
        open();
    }

    function updatePreview() {
        if (!backend) return;
        var dl = deadlineInput.text.trim();
        var st = startInput.text.trim();
        projectedIterations = backend.getProjectedWeeklyIterations(dl, st) || [];
    }

    contentItem: ColumnLayout {
        id: contentCol
        spacing: 14

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text { text: "🗓️"; font.pixelSize: 24 }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Prepare Weekly Iterations in Advance"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }

                Text {
                    text: "Continue weekly sprint schematics (week-YYWW) in advance up to a target deadline"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#30363d" }

        // Deadline / Milestone Selection Section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "TARGET DEADLINE OR MILESTONE"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 10
                font.weight: Font.Bold
                color: "#8b949e"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: deadlineInput
                    Layout.fillWidth: true
                    implicitHeight: 32
                    placeholderText: "YYYY-MM-DD or sprint (e.g. 2026-11-30 or week-2648)"
                    placeholderTextColor: "#484f58"
                    font.pixelSize: 11
                    color: "#f0f6fc"
                    background: Rectangle {
                        color: "#0d1117"
                        radius: 4
                        border.color: deadlineInput.activeFocus ? "#58a6ff" : "#30363d"
                    }
                    onTextChanged: root.updatePreview()
                }

                // Milestone quick selector
                ComboBox {
                    id: milestoneCombo
                    implicitHeight: 32
                    implicitWidth: 160
                    model: ["Select Milestone..."].concat(root.availableMilestones.filter(function(m) { return m !== "ALL" && m !== "PLANNED" && m !== "UNPLANNED"; }))
                    font.pixelSize: 11
                    background: Rectangle {
                        color: "#21262d"
                        radius: 4
                        border.color: "#30363d"
                    }
                    contentItem: Text {
                        text: milestoneCombo.displayText
                        font: milestoneCombo.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 8
                        elide: Text.ElideRight
                    }
                    onActivated: function(index) {
                        if (index > 0) {
                            var mName = milestoneCombo.model[index];
                            if (backend) {
                                var allM = backend.get_milestones ? backend.get_milestones() : [];
                                for (var i = 0; i < allM.length; i++) {
                                    if (allM[i].name === mName && allM[i].target_date) {
                                        deadlineInput.text = allM[i].target_date;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Optional Start Sprint
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "START ITERATION (OPTIONAL)"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 10
                font.weight: Font.Bold
                color: "#8b949e"
            }

            TextField {
                id: startInput
                Layout.fillWidth: true
                implicitHeight: 32
                placeholderText: "Start sprint or date (leave empty for current week / latest sprint)"
                placeholderTextColor: "#484f58"
                font.pixelSize: 11
                color: "#f0f6fc"
                background: Rectangle {
                    color: "#0d1117"
                    radius: 4
                    border.color: startInput.activeFocus ? "#58a6ff" : "#30363d"
                }
                onTextChanged: root.updatePreview()
            }
        }

        // TFS Sync Option
        CheckBox {
            id: syncTfsCheck
            text: "Sync & create iteration classification nodes in Azure DevOps / TFS"
            checked: root.syncToTfs
            font.pixelSize: 11
            contentItem: Text {
                text: syncTfsCheck.text
                font: syncTfsCheck.font
                color: "#c9d1d9"
                leftPadding: syncTfsCheck.indicator.width + 8
                verticalAlignment: Text.AlignVCenter
            }
            onCheckedChanged: { root.syncToTfs = checked; }
        }

        // Schematics Preview Box
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "PREPARED ITERATIONS PREVIEW (" + root.projectedIterations.length + " WEEKS)"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: "#58a6ff"
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 140
                color: "#0d1117"
                radius: 6
                border.color: "#30363d"
                border.width: 1
                clip: true

                ListView {
                    id: previewLv
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 2
                    model: root.projectedIterations
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        width: previewLv.width - 8
                        height: 28
                        radius: 4
                        color: index % 2 === 0 ? "#131920" : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "🏷️"
                                font.pixelSize: 11
                            }

                            Text {
                                text: modelData.sprint_name || ""
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#58a6ff"
                                implicitWidth: 80
                            }

                            Text {
                                text: modelData.label || ""
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: (modelData.start_date || "") + " → " + (modelData.end_date || "")
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                color: "#6e7681"
                            }
                        }
                    }
                }
            }
        }

        // Actions
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
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
                text: "🚀 Prepare Iterations"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                contentItem: Text { text: parent.text; font: parent.font; color: "#ffffff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle {
                    implicitWidth: 170; implicitHeight: 32; radius: 6
                    color: parent.hovered ? "#1f6feb" : "#238636"
                    border.color: "#3fb950"
                }
                onClicked: {
                    if (backend) {
                        var res = backend.prepareWeeklyIterations(deadlineInput.text.trim(), startInput.text.trim(), root.syncToTfs);
                        root.iterationsPrepared(res);
                    }
                    root.close();
                }
            }
        }
    }
}
