import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: "Search..."
    property int debounceMs: 150
    signal searchUpdated(string query)

    implicitHeight: 36
    implicitWidth: 260
    color: "#0d1117"
    radius: 6
    border.color: input.activeFocus ? "#58a6ff" : "#30363d"
    border.width: 1

    Timer {
        id: debounceTimer
        interval: root.debounceMs
        repeat: false
        onTriggered: root.searchUpdated(input.text)
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8
        anchors.verticalCenter: parent.verticalCenter

        Text {
            text: "🔍"
            font.pixelSize: 12
            color: "#8b949e"
            anchors.verticalCenter: parent.verticalCenter
        }

        TextInput {
            id: input
            width: parent.width - 32
            anchors.verticalCenter: parent.verticalCenter
            font.family: "Segoe UI, sans-serif"
            font.pixelSize: 13
            color: "#f0f6fc"
            selectByMouse: true
            clip: true

            Text {
                text: root.placeholder
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 13
                color: "#6e7681"
                visible: !input.text && !input.activeFocus
                anchors.verticalCenter: parent.verticalCenter
            }

            onTextChanged: {
                if (input.text === "") {
                    debounceTimer.stop()
                    root.searchUpdated("")
                } else {
                    debounceTimer.restart()
                }
            }

            onAccepted: {
                debounceTimer.stop()
                root.searchUpdated(input.text)
            }
        }
    }
}
