import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property string label: ""
    property string iconText: ""
    property bool active: false
    property bool isCollapsed: false
    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: 42
    implicitHeight: 42
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
            height: 20
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            radius: 1.5
            color: "#58a6ff"
            visible: root.active
        }

        // Expanded view: Icon + Label Row
        Row {
            visible: !root.isCollapsed
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Text {
                text: root.iconText
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
                color: root.active ? "#58a6ff" : (mouseArea.containsMouse ? "#f0f6fc" : "#8b949e")
            }

            Text {
                text: root.label
                anchors.verticalCenter: parent.verticalCenter
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 13
                font.weight: root.active ? Font.DemiBold : Font.Normal
                color: root.active ? "#f0f6fc" : (mouseArea.containsMouse ? "#f0f6fc" : "#8b949e")
            }
        }

        // Collapsed view: Centered Icon
        Text {
            visible: root.isCollapsed
            anchors.centerIn: parent
            text: root.iconText
            font.pixelSize: 18
            color: root.active ? "#58a6ff" : (mouseArea.containsMouse ? "#f0f6fc" : "#8b949e")
        }
    }

    ToolTip.visible: root.isCollapsed && mouseArea.containsMouse
    ToolTip.text: root.label
    ToolTip.delay: 150

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
