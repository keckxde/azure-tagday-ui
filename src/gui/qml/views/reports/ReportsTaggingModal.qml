import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

    Rectangle {
    property var root: null

        id: tagModalOverlay
        anchors.fill: parent
        color: "#99000000"
        visible: root.tagModalOpen
        z: 9999

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (backend && !backend.isBusy)
                    root.tagModalOpen = false;
            }
        }

        Rectangle {
            id: tagModalBox
            width: Math.min(560, parent.width - 32)
            implicitHeight: modalCol.implicitHeight + 40
            anchors.centerIn: parent
            color: "#161b22"
            radius: 10
            border.color: "#388bfd"
            border.width: 1

            MouseArea {
                anchors.fill: parent
                // absorb clicks to prevent closing modal
            }

            ColumnLayout {
                id: modalCol
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                // Modal Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "🏷️ Tag Repository Release"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "✕"
                        font.pixelSize: 13
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#8b949e"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 24
                            implicitWidth: 24
                            radius: 12
                            color: parent.hovered ? "#30363d" : "transparent"
                        }
                        onClicked: {
                            if (backend && !backend.isBusy)
                                root.tagModalOpen = false;
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#30363d"
                }

                // Target Repository Selection
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Target Repository:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: "#c9d1d9"
                    }

                    ComboBox {
                        id: modalRepoCombo
                        Layout.fillWidth: true
                        model: {
                            var list = [];
                            if (backend && backend.tagDayData && backend.tagDayData.repos_summary) {
                                for (var i = 0; i < backend.tagDayData.repos_summary.length; i++) {
                                    list.push(backend.tagDayData.repos_summary[i].name);
                                }
                            }
                            if (list.length === 0 && root.selectedRepoName)
                                list.push(root.selectedRepoName);
                            return list;
                        }
                        currentIndex: {
                            var idx = model.indexOf(root.tagModalRepo);
                            return idx >= 0 ? idx : 0;
                        }
                        onActivated: {
                            root.tagModalRepo = currentText;
                            root.tagModalBranches = backend ? backend.get_repo_branches(root.tagModalRepo) : ["dev", "main", "develop"];
                            root.setTagModalBump("patch");
                        }
                    }
                }

                // Target Branch (default: dev)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Target Branch (Dev Branch):"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: "#c9d1d9"
                        }
                        Text {
                            text: "• Tag is attached to latest commit on this branch"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            color: "#8b949e"
                        }
                    }

                    ComboBox {
                        id: modalBranchCombo
                        Layout.fillWidth: true
                        editable: true
                        model: root.tagModalBranches && root.tagModalBranches.length > 0 ? root.tagModalBranches : ["dev", "main", "master", "develop"]
                        currentIndex: {
                            var idx = model.indexOf(root.tagModalBranch);
                            return idx >= 0 ? idx : 0;
                        }
                        onEditTextChanged: {
                            root.tagModalBranch = editText.trim();
                            root.tagModalComment = "Tag Day release " + root.tagModalTagName + " from branch '" + root.tagModalBranch + "'";
                        }
                        onActivated: {
                            root.tagModalBranch = currentText;
                            root.tagModalComment = "Tag Day release " + root.tagModalTagName + " from branch '" + root.tagModalBranch + "'";
                        }
                    }
                }

                // Proposed Tag Name Field
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Tag Name:"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: "#c9d1d9"
                        }

                        Rectangle {
                            implicitHeight: 18
                            implicitWidth: 90
                            radius: 9
                            color: "#1f293d"
                            border.color: "#388bfd"
                            Text {
                                anchors.centerIn: parent
                                text: "Weekly <YYWW>"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                color: "#58a6ff"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Bump quick buttons in modal
                        Button {
                            text: "Patch"
                            font.pixelSize: 10
                            background: Rectangle {
                                implicitHeight: 20
                                implicitWidth: 50
                                radius: 3
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: root.setTagModalBump("patch")
                        }

                        Button {
                            text: "+Minor"
                            font.pixelSize: 10
                            background: Rectangle {
                                implicitHeight: 20
                                implicitWidth: 55
                                radius: 3
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: root.setTagModalBump("minor")
                        }

                        Button {
                            text: "+Major"
                            font.pixelSize: 10
                            background: Rectangle {
                                implicitHeight: 20
                                implicitWidth: 55
                                radius: 3
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: root.setTagModalBump("major")
                        }
                    }

                    TextField {
                        id: modalTagField
                        Layout.fillWidth: true
                        text: root.tagModalTagName
                        font.family: "Consolas, monospace"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: "#58a6ff"
                        background: Rectangle {
                            implicitHeight: 34
                            radius: 6
                            color: "#0d1117"
                            border.color: modalTagField.activeFocus ? "#388bfd" : "#30363d"
                            border.width: modalTagField.activeFocus ? 2 : 1
                        }
                        onTextChanged: {
                            root.tagModalTagName = text.trim();
                        }
                    }
                }

                // Tag Annotation / Comment
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Tag Message / Annotation:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: "#c9d1d9"
                    }

                    TextField {
                        id: modalCommentField
                        Layout.fillWidth: true
                        text: root.tagModalComment
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#f0f6fc"
                        background: Rectangle {
                            implicitHeight: 34
                            radius: 6
                            color: "#0d1117"
                            border.color: modalCommentField.activeFocus ? "#388bfd" : "#30363d"
                            border.width: modalCommentField.activeFocus ? 2 : 1
                        }
                        onTextChanged: {
                            root.tagModalComment = text;
                        }
                    }
                }

                // Status Banner / Feedback
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: statusText.implicitHeight + 16
                    radius: 6
                    visible: root.tagModalStatus !== ""
                    color: root.tagModalIsError ? "#3d1414" : (root.tagModalIsSuccess ? "#12261a" : "#1f293d")
                    border.color: root.tagModalIsError ? "#f85149" : (root.tagModalIsSuccess ? "#3fb950" : "#388bfd")

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8
                        Text {
                            text: root.tagModalIsError ? "❌" : (root.tagModalIsSuccess ? "✅" : "⏳")
                            font.pixelSize: 13
                        }
                        Text {
                            id: statusText
                            text: root.tagModalStatus
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: root.tagModalIsError ? "#f85149" : (root.tagModalIsSuccess ? "#3fb950" : "#58a6ff")
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Modal Actions Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Button {
                        text: root.tagModalIsSuccess ? "Done" : "Cancel"
                        enabled: backend ? !backend.isBusy : true
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#c9d1d9"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 90
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: root.tagModalOpen = false
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: (backend && backend.isBusy) ? "Tagging..." : ("🏷️ Create Tag '" + root.tagModalTagName + "'")
                        enabled: backend ? !backend.isBusy && root.tagModalRepo !== "" && root.tagModalTagName !== "" : false
                        font.weight: Font.Bold
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 34
                            implicitWidth: 210
                            radius: 6
                            color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#30363d"
                            border.color: parent.enabled ? "#3fb950" : "#30363d"
                        }
                        onClicked: {
                            root.tagModalStatus = "Tagging branch '" + root.tagModalBranch + "' in " + root.tagModalRepo + "...";
                            root.tagModalIsError = false;
                            root.tagModalIsSuccess = false;
                            if (backend) {
                                backend.create_tag_async(
                                    root.tagModalRepo,
                                    root.tagModalTagName,
                                    root.tagModalBranch,
                                    root.tagModalComment
                                );
                            }
                        }
                    }
                }
            }
        }
    }
