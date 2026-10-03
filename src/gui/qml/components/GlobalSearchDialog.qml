import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root

    title: ""
    modal: true
    dim: true
    anchors.centerIn: parent
    width: Math.min(780, parent ? (parent.width - 40) : 780)
    height: Math.min(680, parent ? (parent.height - 40) : 680)
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string searchQuery: ""
    property string activeCategory: "ALL"
    property var searchResults: []
    property var categoryCounts: ({
        "all": 0,
        "work_items": 0,
        "commits": 0,
        "pull_requests": 0,
        "open_items": 0,
        "merkpunkte": 0,
        "scenarios": 0,
        "repositories": 0,
        "milestones": 0
    })
    property int selectedIndex: 0
    property bool isSearching: false

    signal workItemActionRequested(int workItemId)
    signal sprintActionRequested(string sprintName)

    background: Rectangle {
        color: "#161b22"
        radius: 12
        border.color: "#30363d"
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 3
            radius: 2
            color: "#1f6feb"
        }
    }

    function openSearch(initialText) {
        root.open();
        if (initialText !== undefined && initialText !== null) {
            searchInput.text = initialText;
        }
        root.activeCategory = "ALL";
        root.selectedIndex = 0;
        Qt.callLater(function() {
            searchInput.forceActiveFocus();
            searchInput.selectAll();
            triggerSearch(searchInput.text);
        });
    }

    function triggerSearch(query) {
        root.searchQuery = query || "";
        if (!backend) {
            root.searchResults = [];
            return;
        }
        root.isSearching = true;
        var res = backend.global_search(root.searchQuery, root.activeCategory, 100);
        if (res) {
            root.searchResults = res.results || [];
            if (res.counts_by_category) {
                root.categoryCounts = res.counts_by_category;
            }
        } else {
            root.searchResults = [];
        }
        root.selectedIndex = 0;
        root.isSearching = false;
    }

    function executeResultAction(item) {
        if (!item) return;
        var act = item.action_type || "";
        if (act === "open_work_item" || item.category === "work_items") {
            var wId = parseInt(item.target_id || item.id || 0);
            if (wId > 0 && backend) {
                backend.open_work_item_in_browser(wId);
            }
        } else if (act === "open_url" || item.url) {
            if (item.url) {
                Qt.openUrlExternally(item.url);
            }
        } else if (act === "open_repo") {
            if (item.url) {
                Qt.openUrlExternally(item.url);
            } else if (typeof window !== "undefined") {
                window.currentTabIndex = 1; // Repositories view
            }
        } else if (act === "open_milestones") {
            if (typeof window !== "undefined" && typeof window.openMilestonesManager === "function") {
                window.openMilestonesManager();
            }
        }
        root.close();
    }

    Timer {
        id: searchDebounce
        interval: 120
        repeat: false
        onTriggered: {
            root.triggerSearch(searchInput.text);
        }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================
        // 1. Search Header Bar & Input
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 64
            color: "#0d1117"
            radius: 12

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#30363d"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: "🔍"
                    font.pixelSize: 18
                    color: "#58a6ff"
                    Layout.alignment: Qt.AlignVCenter
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    font.family: "Segoe UI, -apple-system, sans-serif"
                    font.pixelSize: 15
                    color: "#ffffff"
                    selectByMouse: true
                    clip: true
                    focus: true

                    Text {
                        text: "Search Work Items (#123), Commits (SHA), PRs (!42), [OI_...], [MP_...], Scenarios, Repos..."
                        font.family: "Segoe UI, -apple-system, sans-serif"
                        font.pixelSize: 13
                        color: "#6e7681"
                        visible: !searchInput.text && !searchInput.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    onTextChanged: {
                        searchDebounce.restart();
                    }

                    Keys.onEscapePressed: root.close()
                    Keys.onDownPressed: {
                        if (resultsList.count > 0) {
                            root.selectedIndex = Math.min(resultsList.count - 1, root.selectedIndex + 1);
                            resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                        }
                    }
                    Keys.onUpPressed: {
                        if (resultsList.count > 0) {
                            root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                            resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                        }
                    }
                    Keys.onReturnPressed: {
                        if (resultsList.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < resultsList.count) {
                            root.executeResultAction(root.searchResults[root.selectedIndex]);
                        }
                    }
                }

                // Clear button
                Rectangle {
                    visible: searchInput.text.length > 0
                    width: 24
                    height: 24
                    radius: 12
                    color: clearBtnMa.containsMouse ? "#30363d" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }

                    MouseArea {
                        id: clearBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = "";
                            searchInput.forceActiveFocus();
                        }
                    }
                }

                // Shortcut Hint Badge (Esc)
                Rectangle {
                    implicitHeight: 22
                    implicitWidth: escHintText.implicitWidth + 12
                    radius: 4
                    color: "#21262d"
                    border.color: "#30363d"
                    border.width: 1

                    Text {
                        id: escHintText
                        anchors.centerIn: parent
                        text: "ESC"
                        font.family: "Consolas, monospace"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: "#8b949e"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }
        }

        // ==========================================
        // 2. Category Filter Tabs Row
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            color: "#161b22"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#21262d"
            }

            ScrollView {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: [
                            { key: "ALL", label: "All", count: root.categoryCounts.all || 0, icon: "🔍" },
                            { key: "WORK_ITEMS", label: "Work Items", count: root.categoryCounts.work_items || 0, icon: "📘" },
                            { key: "PULL_REQUESTS", label: "Pull Requests", count: root.categoryCounts.pull_requests || 0, icon: "🔀" },
                            { key: "COMMITS", label: "Commits", count: root.categoryCounts.commits || 0, icon: "📜" },
                            { key: "OPEN_ITEMS", label: "Open Items (OI)", count: root.categoryCounts.open_items || 0, icon: "📌" },
                            { key: "MERKPUNKTE", label: "Merkpunkte (MP)", count: root.categoryCounts.merkpunkte || 0, icon: "💡" },
                            { key: "SCENARIOS", label: "Scenarios", count: root.categoryCounts.scenarios || 0, icon: "🎬" },
                            { key: "REPOSITORIES", label: "Repositories", count: root.categoryCounts.repositories || 0, icon: "📦" },
                            { key: "MILESTONES", label: "Milestones", count: root.categoryCounts.milestones || 0, icon: "🚩" }
                        ]

                        delegate: Rectangle {
                            id: tabChip
                            height: 28
                            implicitWidth: tabRow.implicitWidth + 16
                            radius: 14
                            color: root.activeCategory === modelData.key ? "#1f6feb" : (tabChipMa.containsMouse ? "#21262d" : "#0d1117")
                            border.color: root.activeCategory === modelData.key ? "#58a6ff" : "#30363d"
                            border.width: 1

                            RowLayout {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: modelData.icon
                                    font.pixelSize: 11
                                }

                                Text {
                                    text: modelData.label
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: root.activeCategory === modelData.key ? Font.Bold : Font.Normal
                                    color: root.activeCategory === modelData.key ? "#ffffff" : "#c9d1d9"
                                }

                                Rectangle {
                                    implicitHeight: 16
                                    implicitWidth: Math.max(16, countText.implicitWidth + 6)
                                    radius: 8
                                    color: root.activeCategory === modelData.key ? "#0d3a78" : "#21262d"
                                    Text {
                                        id: countText
                                        anchors.centerIn: parent
                                        text: modelData.count.toString()
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: root.activeCategory === modelData.key ? "#79c0ff" : "#8b949e"
                                    }
                                }
                            }

                            MouseArea {
                                id: tabChipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeCategory = modelData.key;
                                    root.triggerSearch(searchInput.text);
                                }
                            }
                        }
                    }
                }
            }
        }

        // ==========================================
        // 3. Results List / Zero-State Container
        // ==========================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Zero-State: When Search Query is Empty
            ColumnLayout {
                visible: searchInput.text.trim() === ""
                anchors.centerIn: parent
                spacing: 14
                width: Math.min(540, parent.width - 40)

                Text {
                    text: "🔍 Universal Search & Quick Navigation"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Type any term, code, ID, or schematic tag to search instantly across your Azure DevOps workspace:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }

                GridLayout {
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 12
                    Layout.fillWidth: true

                    // Hint 1: Work Item ID
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Text { text: "📘"; font.pixelSize: 14 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "#12345 or login error"; font.pixelSize: 11; font.weight: Font.Bold; color: "#58a6ff" }
                                Text { text: "Work item ID, title, or assignee"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchInput.text = "123"
                        }
                    }

                    // Hint 2: Open Item Code
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Text { text: "📌"; font.pixelSize: 14 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "OI-171 or [OI_171]"; font.pixelSize: 11; font.weight: Font.Bold; color: "#d29922" }
                                Text { text: "Open item code or list"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchInput.text = "OI"
                        }
                    }

                    // Hint 3: Merkpunkt Code
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Text { text: "💡"; font.pixelSize: 14 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "MP_01 or MP-2"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" }
                                Text { text: "Merkpunkt notes & decisions"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchInput.text = "MP"
                        }
                    }

                    // Hint 4: Scenario Code
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Text { text: "🎬"; font.pixelSize: 14 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "SCENARIO-12 or Demo"; font.pixelSize: 11; font.weight: Font.Bold; color: "#f0883e" }
                                Text { text: "Scenario milestones & test tags"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchInput.text = "Scenario"
                        }
                    }

                    // Hint 5: Pull Request
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Text { text: "🔀"; font.pixelSize: 14 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "PR 42 or !42"; font.pixelSize: 11; font.weight: Font.Bold; color: "#a371f7" }
                                Text { text: "Pull request number or branch"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchInput.text = "PR"
                        }
                    }

                    // Hint 6: Commit Code
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Text { text: "📜"; font.pixelSize: 14 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "a1b2c3d (Git SHA)"; font.pixelSize: 11; font.weight: Font.Bold; color: "#d29922" }
                                Text { text: "Commit hash or commit message"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                    }
                }
            }

            // No Results State
            ColumnLayout {
                visible: searchInput.text.trim() !== "" && root.searchResults.length === 0 && !root.isSearching
                anchors.centerIn: parent
                spacing: 10

                Text {
                    text: "🔍"
                    font.pixelSize: 32
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "No matches found for \"" + searchInput.text + "\""
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Try checking the spelling, using a shorter keyword, or selecting the 'All' tab."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // Results ListView
            ListView {
                id: resultsList
                visible: root.searchResults.length > 0
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 6
                model: root.searchResults
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: resultCard
                    width: resultsList.width
                    implicitHeight: resultRow.implicitHeight + 16
                    radius: 8
                    color: (root.selectedIndex === index || resultCardMa.containsMouse) ? "#1c2128" : "#0d1117"
                    border.color: (root.selectedIndex === index || resultCardMa.containsMouse) ? "#58a6ff" : "#30363d"
                    border.width: (root.selectedIndex === index) ? 1.5 : 1

                    RowLayout {
                        id: resultRow
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 12

                        // Category Icon
                        Text {
                            text: modelData.icon || "🔍"
                            font.pixelSize: 18
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Info Column
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            // Top Line: Badge, Title, Schematics
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Category / ID Badge
                                Rectangle {
                                    implicitHeight: 20
                                    implicitWidth: resBadgeText.implicitWidth + 10
                                    radius: 4
                                    color: "#21262d"
                                    border.color: modelData.badge_color || "#58a6ff"
                                    border.width: 1

                                    Text {
                                        id: resBadgeText
                                        anchors.centerIn: parent
                                        text: modelData.badge || (modelData.id ? ("#" + modelData.id) : modelData.category_label)
                                        font.family: "Consolas, Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: modelData.badge_color || "#58a6ff"
                                    }
                                }

                                // Title
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title || ""
                                    font.family: "Segoe UI, -apple-system, sans-serif"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: (root.selectedIndex === index || resultCardMa.containsMouse) ? "#58a6ff" : "#f0f6fc"
                                    elide: Text.ElideRight
                                }

                                // Schematics Badges (e.g. [OI_171], [MP_01])
                                Repeater {
                                    model: modelData.schematics || []
                                    delegate: Rectangle {
                                        implicitHeight: 18
                                        implicitWidth: schemBadgeText.implicitWidth + 8
                                        radius: 3
                                        color: "#271704"
                                        border.color: "#d29922"
                                        border.width: 1
                                        Text {
                                            id: schemBadgeText
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: "#f0883e"
                                        }
                                    }
                                }
                            }

                            // Subtitle Line: Metadata & context
                            Text {
                                Layout.fillWidth: true
                                text: modelData.subtitle || ""
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                                elide: Text.ElideRight
                            }
                        }

                        // Right Action Button
                        Rectangle {
                            implicitHeight: 28
                            implicitWidth: actionBtnText.implicitWidth + 16
                            radius: 6
                            color: actionBtnMa.containsMouse ? "#1f6feb" : "#21262d"
                            border.color: actionBtnMa.containsMouse ? "#58a6ff" : "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: {
                                        if (modelData.action_type === "open_work_item") return "🌐 TFS Edit";
                                        if (modelData.action_type === "open_url") return "🌐 Open Browser";
                                        if (modelData.action_type === "open_repo") return "📦 Open Repo";
                                        if (modelData.action_type === "open_milestones") return "🚩 View";
                                        return "↵ Open";
                                    }
                                    id: actionBtnText
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: actionBtnMa.containsMouse ? "#ffffff" : "#c9d1d9"
                                }
                            }

                            MouseArea {
                                id: actionBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.executeResultAction(modelData)
                            }
                        }
                    }

                    MouseArea {
                        id: resultCardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedIndex = index;
                            root.executeResultAction(modelData);
                        }
                    }
                }
            }
        }

        // ==========================================
        // 4. Footer Status & Navigation Bar
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            color: "#0d1117"
            radius: 12

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#30363d"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: root.searchResults.length > 0 ? (root.searchResults.length + " match(es) found") : "Ready"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 12

                    Row {
                        spacing: 4
                        Rectangle {
                            width: 18; height: 16; radius: 3; color: "#21262d"; border.color: "#30363d"
                            Text { anchors.centerIn: parent; text: "↑↓"; font.pixelSize: 9; color: "#8b949e" }
                        }
                        Text { text: "Navigate"; font.pixelSize: 10; color: "#8b949e"; anchors.verticalCenter: parent.verticalCenter }
                    }

                    Row {
                        spacing: 4
                        Rectangle {
                            width: 22; height: 16; radius: 3; color: "#21262d"; border.color: "#30363d"
                            Text { anchors.centerIn: parent; text: "↵"; font.pixelSize: 10; color: "#8b949e" }
                        }
                        Text { text: "Open"; font.pixelSize: 10; color: "#8b949e"; anchors.verticalCenter: parent.verticalCenter }
                    }

                    Row {
                        spacing: 4
                        Rectangle {
                            width: 28; height: 16; radius: 3; color: "#21262d"; border.color: "#30363d"
                            Text { anchors.centerIn: parent; text: "ESC"; font.pixelSize: 9; color: "#8b949e" }
                        }
                        Text { text: "Close"; font.pixelSize: 10; color: "#8b949e"; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
    }
}
