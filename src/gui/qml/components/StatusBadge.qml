import QtQuick 2.15

Rectangle {
    id: root
    property string text: ""
    property color badgeColor: "#238636"
    property color textColor: "#ffffff"

    implicitHeight: 22
    implicitWidth: label.contentWidth + 16
    radius: 11
    color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.2)
    border.color: badgeColor
    border.width: 1

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.family: "Segoe UI, sans-serif"
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: root.textColor
    }
}
