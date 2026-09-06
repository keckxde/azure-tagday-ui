import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property string label: ""
    property string iconText: ""
    property bool active: false
    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: 42
    implicitHeight: 42
    implicitWidth: 200

    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        radius: 6
        color: root.active ? "#21262d" : (mouseArea.containsMouse ? "#1c2128" : "transparent")

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

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Text {
                text: root.iconText
                font.pixelSize: 16
                color: root.active ? "#58a6ff" : (mouseArea.containsMouse ? "#f0f6fc" : "#8b949e")
            }

            Text {
                text: root.label
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 13
                font.weight: root.active ? Font.DemiBold : Font.Normal
                color: root.active ? "#f0f6fc" : (mouseArea.containsMouse ? "#f0f6fc" : "#8b949e")
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
