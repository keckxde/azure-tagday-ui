import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    property string title: ""
    property string value: "0"
    property string subtitle: ""
    property color accentColor: "#58a6ff"

    // Color code: "clean" (green = Nothing pending), "pending" (orange = pending changes), "neutral"
    property string status: "neutral" // "clean", "pending", "neutral"
    readonly property color effectiveStatusColor: {
        if (status === "pending") return "#d29922"; // Orange: pending changes
        if (status === "clean") return "#3fb950";   // Green: Nothing pending
        return accentColor;
    }

    property bool showStatusBar: true
    property string icon: ""
    property string badgeText: ""
    property color badgeColor: "transparent"
    readonly property color effectiveBadgeColor: (badgeColor === "#00000000" || badgeColor.toString() === "#00000000" || badgeColor === "transparent") ? effectiveStatusColor : badgeColor

    property bool clickable: false
    property int valuePixelSize: 28

    // Special PR breakdown mode
    property bool showPrBreakdown: false
    property int openCount: 0
    property int closedCount: 0
    property int abandonedCount: 0

    signal clicked()
    signal openPillClicked()
    signal closedPillClicked()
    signal abandonedPillClicked()

    implicitHeight: 136
    implicitWidth: 260
    clip: true
    color: cardMa.containsMouse && root.clickable ? "#212836" : "#161b22"
    radius: 8
    border.color: cardMa.containsMouse && root.clickable ? root.effectiveStatusColor : (root.status !== "neutral" ? Qt.rgba(root.effectiveStatusColor.r, root.effectiveStatusColor.g, root.effectiveStatusColor.b, 0.28) : "#30363d")
    border.width: 1

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    // Left Status Bar (Green = Nothing pending, Orange = Pending changes)
    Rectangle {
        id: statusBar
        width: 5
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: root.effectiveStatusColor
        visible: root.status !== "neutral" || root.showStatusBar
    }

    MouseArea {
        id: cardMa
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: true
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    Column {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 18
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        spacing: 8

        // Top Title Row
        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: root.icon
                font.pixelSize: 15
                visible: root.icon !== ""
            }

            Text {
                text: root.title.toUpperCase()
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "#8b949e"
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                id: badgeRect
                height: 20
                Layout.preferredWidth: badgeTextItem.implicitWidth + 12
                radius: 4
                color: Qt.rgba(root.effectiveBadgeColor.r, root.effectiveBadgeColor.g, root.effectiveBadgeColor.b, 0.18)
                border.color: root.effectiveBadgeColor
                border.width: 1
                visible: root.badgeText !== ""

                Text {
                    id: badgeTextItem
                    anchors.centerIn: parent
                    text: root.badgeText
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: root.effectiveBadgeColor
                }
            }

            Text {
                id: arrowText
                text: "➔"
                font.pixelSize: 13
                color: root.effectiveStatusColor
                visible: root.clickable
                opacity: cardMa.containsMouse ? 1.0 : 0.4
            }
        }

        // Standard Main Value (when not in PR breakdown mode)
        Text {
            text: root.value
            font.family: root.value.indexOf("v") === 0 ? "Consolas, 'Segoe UI', monospace" : "Segoe UI, sans-serif"
            font.pixelSize: root.valuePixelSize
            font.weight: Font.Bold
            color: root.effectiveStatusColor
            elide: Text.ElideRight
            width: parent.width
            visible: !root.showPrBreakdown
        }

        // PR Breakdown Mode (Open / Closed / Abandoned Pills)
        Row {
            width: parent.width
            spacing: 10
            visible: root.showPrBreakdown
            height: 30

            // Open PRs Pill (Orange if > 0 pending, Green if 0)
            Rectangle {
                height: 28
                width: openTextItem.implicitWidth + 18
                radius: 14
                color: root.openCount > 0 ? Qt.rgba(210/255, 153/255, 34/255, 0.22) : Qt.rgba(63/255, 185/255, 80/255, 0.16)
                border.color: root.openCount > 0 ? "#d29922" : "#3fb950"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: root.openCount > 0 ? "⚠️" : "✓"
                        font.pixelSize: 11
                    }
                    Text {
                        id: openTextItem
                        text: root.openCount + " Open"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: root.openCount > 0 ? "#d29922" : "#3fb950"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPillClicked()
                }
            }

            // Closed PRs Pill
            Rectangle {
                height: 28
                width: closedTextItem.implicitWidth + 18
                radius: 14
                color: Qt.rgba(56/255, 139/255, 253/255, 0.15)
                border.color: "#388bfd"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: "✔"
                        font.pixelSize: 10
                        color: "#79c0ff"
                    }
                    Text {
                        id: closedTextItem
                        text: root.closedCount + " Closed"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: "#79c0ff"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closedPillClicked()
                }
            }

            // Abandoned PRs Pill
            Rectangle {
                height: 28
                width: abTextItem.implicitWidth + 18
                radius: 14
                color: Qt.rgba(110/255, 118/255, 129/255, 0.12)
                border.color: "#30363d"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: "✕"
                        font.pixelSize: 10
                        color: "#8b949e"
                    }
                    Text {
                        id: abTextItem
                        text: root.abandonedCount + " Abandoned"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#8b949e"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.abandonedPillClicked()
                }
            }
        }

        // Subtitle / Details
        Text {
            text: root.subtitle
            font.family: "Segoe UI, sans-serif"
            font.pixelSize: 12
            color: cardMa.containsMouse && root.clickable ? "#e6edf3" : "#8b949e"
            visible: root.subtitle !== ""
            elide: Text.ElideRight
            width: parent.width
        }
    }
}
