import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

            ColumnLayout {
    property var root: null

                spacing: 16

                // Top Controls & Launchers
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Package Release Milestones & Version Tracking"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                        Text {
                            text: "Tracks stable and unstable semantic version tags across all packages according to REVISION.md."
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#8b949e"
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "Generate Release Notes"
                        enabled: backend ? !backend.isBusy : false
                        font.weight: Font.DemiBold
                        font.pixelSize: 12
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 160
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
                            implicitHeight: 32
                            implicitWidth: 145
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (backend)
                                backend.open_revision_file();
                        }
                    }
                }

                // Table Container
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    border.width: 1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // Header
                        Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            color: "#0d1117"
                            border.color: "#21262d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 14

                                Text {
                                    text: "PACKAGE / REPOSITORY"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 220
                                }

                                Text {
                                    text: "CATEGORY"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 140
                                }

                                Text {
                                    text: "STABLE TAG"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 150
                                }

                                Text {
                                    text: "UNSTABLE TAG"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 150
                                }

                                Text {
                                    text: "PENDING RELEASE STATUS"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: "ACTIONS"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#8b949e"
                                    Layout.preferredWidth: 110
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }

                        // Table List
                        ListView {
                            id: releasePackageList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            spacing: 2
                            model: (backend && backend.repositories) ? backend.repositories : []

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                active: true
                            }

                            delegate: Rectangle {
                                width: releasePackageList.width
                                height: 42
                                color: index % 2 === 0 ? "#161b22" : "#1a1f29"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    spacing: 14

                                    Text {
                                        text: modelData.name
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: "#58a6ff"
                                        Layout.preferredWidth: 220
                                        elide: Text.ElideRight
                                    }

                                    StatusBadge {
                                        Layout.preferredWidth: 140
                                        text: modelData.category || "GENERAL"
                                        badgeColor: backend ? backend.get_category_color(modelData.category || "OTHERS") : "#30363d"
                                    }

                                    Text {
                                        text: modelData.stable_tag !== "-" ? ("🛡️ " + modelData.stable_tag) : "–"
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 12
                                        color: modelData.stable_tag !== "-" ? "#3fb950" : "#8b949e"
                                        Layout.preferredWidth: 150
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData.unstable_tag !== "-" ? ("⚡ " + modelData.unstable_tag) : "–"
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 12
                                        color: modelData.unstable_tag !== "-" ? "#79c0ff" : "#8b949e"
                                        Layout.preferredWidth: 150
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData.has_pending_changes ? ("⚠️ " + modelData.pending_status_text) : "✓ Clean / Up to date"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: modelData.has_pending_changes ? "#d29922" : "#3fb950"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Button {
                                        text: "Details 🏷️"
                                        font.pixelSize: 11
                                        Layout.preferredWidth: 110
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: "#58a6ff"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 26
                                            radius: 4
                                            color: parent.hovered ? "#30363d" : "#0d1117"
                                            border.color: "#30363d"
                                        }
                                        onClicked: {
                                            root.openTagDayRepo(modelData.name);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
