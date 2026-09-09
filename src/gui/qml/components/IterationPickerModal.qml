import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root

    property int workItemId: 0
    property string workItemTitle: ""
    property string currentIteration: ""
    property string selectedIteration: ""
    property var availableSprints: backend ? backend.availableSprintList : []

    signal iterationUpdated(int id, string newIteration, var result)

    title: ""
    modal: true
    dim: true
    anchors.centerIn: parent
    width: 500
    height: Math.min(620, contentCol.implicitHeight + 40)
    padding: 20

    background: Rectangle {
        color: "#161b22"
        radius: 10
        border.color: "#30363d"
        border.width: 1
    }

    function openForWorkItem(id, titleText, currentIter) {
        workItemId = id;
        workItemTitle = titleText || ("Work Item #" + id);
        currentIteration = currentIter || "";
        selectedIteration = currentIter || "";
        searchFilter.text = "";
        open();
    }

    function getNextSprint(offset) {
        if (!availableSprints || availableSprints.length === 0) return "";
        var curIdx = availableSprints.indexOf(currentIteration);
        if (curIdx >= 0 && (curIdx + offset) < availableSprints.length) {
            return availableSprints[curIdx + offset];
        } else if (availableSprints.length > 0) {
            return availableSprints[0];
        }
        return "";
    }

    contentItem: ColumnLayout {
        id: contentCol
        spacing: 14

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text { text: "🔄"; font.pixelSize: 22 }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Reschedule Iteration / Sprint"
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

        // Current Iteration banner
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 6
            color: "#0d2344"
            border.color: "#1f6feb"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text { text: "📍 Current Iteration:"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#8b949e" }
                Text {
                    text: root.currentIteration ? ("🎯 " + root.currentIteration) : "📋 Unplanned (Backlog)"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#58a6ff"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }

        // Quick Move Presets
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "QUICK RESCHEDULE PRESETS"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 10
                font.weight: Font.Bold
                color: "#8b949e"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: "⏩ +1 Sprint"
                    font.pixelSize: 11
                    contentItem: Text { text: parent.text; font: parent.font; color: "#58a6ff"; horizontalAlignment: Text.AlignHCenter }
                    background: Rectangle {
                        implicitHeight: 28; implicitWidth: 100; radius: 14
                        color: parent.hovered ? "#0d2344" : "#161b22"
                        border.color: "#1f6feb"
                    }
                    onClicked: {
                        var target = root.getNextSprint(1);
                        if (target) root.selectedIteration = target;
                    }
                }

                Button {
                    text: "⏩ +2 Sprints"
                    font.pixelSize: 11
                    contentItem: Text { text: parent.text; font: parent.font; color: "#79c0ff"; horizontalAlignment: Text.AlignHCenter }
                    background: Rectangle {
                        implicitHeight: 28; implicitWidth: 105; radius: 14
                        color: parent.hovered ? "#21262d" : "#161b22"
                        border.color: "#30363d"
                    }
                    onClicked: {
                        var target = root.getNextSprint(2);
                        if (target) root.selectedIteration = target;
                    }
                }

                Button {
                    text: "📋 Move to Backlog"
                    font.pixelSize: 11
                    contentItem: Text { text: parent.text; font: parent.font; color: "#d29922"; horizontalAlignment: Text.AlignHCenter }
                    background: Rectangle {
                        implicitHeight: 28; implicitWidth: 130; radius: 14
                        color: parent.hovered ? "#2e210a" : "#161b22"
                        border.color: "#9e6a03"
                    }
                    onClicked: {
                        root.selectedIteration = "";
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#30363d" }

        // Sprints List
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "SELECT TARGET SPRINT ITERATION"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 10
                font.weight: Font.Bold
                color: "#8b949e"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: searchFilter
                    Layout.fillWidth: true
                    implicitHeight: 30
                    placeholderText: "Filter sprint iterations (e.g. 2633)..."
                    placeholderTextColor: "#484f58"
                    font.pixelSize: 11
                    color: "#f0f6fc"
                    background: Rectangle {
                        color: "#0d1117"
                        radius: 4
                        border.color: searchFilter.activeFocus ? "#58a6ff" : "#30363d"
                    }
                }

                Button {
                    text: "➕ Advance..."
                    font.pixelSize: 11
                    ToolTip.visible: hovered
                    ToolTip.text: "Prepare weekly iterations in advance up to a deadline"
                    contentItem: Text { text: parent.text; font: parent.font; color: "#58a6ff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 90
                        radius: 4
                        color: parent.hovered ? "#0d2344" : "#161b22"
                        border.color: "#1f6feb"
                    }
                    onClicked: prepareModal.openForPreparation("", "")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 160
                color: "#0d1117"
                radius: 6
                border.color: "#30363d"
                border.width: 1
                clip: true

                ListView {
                    id: sprintsLv
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 2
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    model: {
                        var list = root.availableSprints || [];
                        var filter = searchFilter.text.trim().toLowerCase();
                        if (!filter) return list;
                        return list.filter(function(s) { return s.toLowerCase().indexOf(filter) >= 0; });
                    }

                    delegate: Rectangle {
                        width: sprintsLv.width - 8
                        height: 30
                        radius: 4
                        property bool isSelected: root.selectedIteration === modelData
                        color: isSelected ? "#0d2344" : (sprintMa.containsMouse ? "#21262d" : "transparent")
                        border.color: isSelected ? "#1f6feb" : "transparent"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: parent.parent.isSelected ? "🎯" : "📅"
                                font.pixelSize: 11
                            }

                            Text {
                                text: modelData
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: parent.parent.isSelected ? Font.Bold : Font.Normal
                                color: parent.parent.isSelected ? "#58a6ff" : "#f0f6fc"
                                Layout.fillWidth: true
                            }

                            Text {
                                visible: root.currentIteration === modelData
                                text: "Current"
                                font.pixelSize: 10
                                color: "#8b949e"
                            }
                        }

                        MouseArea {
                            id: sprintMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedIteration = modelData;
                            }
                        }
                    }
                }
            }
        }

        // Selected summary
        Rectangle {
            Layout.fillWidth: true
            height: 32
            radius: 4
            color: "#131920"
            border.color: "#30363d"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                Text { text: "Target Iteration:"; font.pixelSize: 11; color: "#8b949e" }
                Text {
                    text: root.selectedIteration ? ("🎯 " + root.selectedIteration) : "📋 Backlog (Unplanned)"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: root.selectedIteration !== root.currentIteration ? "#3fb950" : "#8b949e"
                }
            }
        }

        // Dialog Actions
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
                text: "💾 Move & Sync to TFS"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                contentItem: Text { text: parent.text; font: parent.font; color: "#ffffff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle {
                    implicitWidth: 160; implicitHeight: 32; radius: 6
                    color: parent.hovered ? "#1f6feb" : "#238636"
                    border.color: "#3fb950"
                }
                onClicked: {
                    if (backend) {
                        var res = backend.update_work_item_iteration(root.workItemId, root.selectedIteration);
                        root.iterationUpdated(root.workItemId, root.selectedIteration, res);
                    }
                    root.close();
                }
            }
        }
    }

    PrepareIterationsModal {
        id: prepareModal
        onIterationsPrepared: function(res) {
            // Re-bind or refresh
        }
    }
}
