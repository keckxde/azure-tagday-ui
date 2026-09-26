import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property string label: ""
    property string iconText: ""
    property bool active: false
    property bool isCollapsed: false
    property string badgeText: ""
    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: 34
    implicitHeight: 34
    implicitWidth: root.isCollapsed ? 48 : 200

    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.leftMargin: root.isCollapsed ? 6 : 8
        anchors.rightMargin: root.isCollapsed ? 6 : 8
        radius: 6
        color: root.active ? "#21262d" : (mouseArea.containsMouse ? "#1c2128" : "transparent")
        border.color: root.active ? "#30363d" : "transparent"
        border.width: root.active ? 1 : 0

        // Active indicator on left
        Rectangle {
            width: 3
            height: 18
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            radius: 1.5
            color: "#58a6ff"
            visible: root.active
        }

        // Expanded view: Icon + Label Row
        RowLayout {
            visible: !root.isCollapsed
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 10

            Text {
                text: root.iconText
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
                color: root.active ? "#58a6ff" : (mouseArea.containsMouse ? "#f0f6fc" : "#8b949e")
            }

            Text {
                text: root.label
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                font.weight: root.active ? Font.DemiBold : Font.Normal
                color: root.active ? "#f0f6fc" : (mouseArea.containsMouse ? "#f0f6fc" : "#c9d1d9")
                elide: Text.ElideRight
            }

            Rectangle {
                visible: root.badgeText !== ""
                implicitWidth: badgeLabel.implicitWidth + 8
                implicitHeight: 16
                radius: 8
                color: root.active ? "#388bfd" : "#30363d"
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: root.badgeText
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: "#ffffff"
                }
            }
        }

        // Collapsed view: Centered Icon
        Text {
            visible: root.isCollapsed
            anchors.centerIn: parent
            text: root.iconText
            font.pixelSize: 16
            color: root.active ? "#58a6ff" : (mouseArea.containsMouse ? "#f0f6fc" : "#8b949e")
        }
    }

    ToolTip.visible: root.isCollapsed && mouseArea.containsMouse
    ToolTip.text: root.label + (root.badgeText !== "" ? " (" + root.badgeText + ")" : "")
    ToolTip.delay: 150

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
