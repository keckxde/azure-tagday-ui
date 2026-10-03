import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: aliasesTabRoot
    spacing: 20
    Layout.fillWidth: true

    // ==========================================
    // User Profiles & Git Aliases Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: aliasesMainCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        property string aliasSearchQuery: ""
        property var autoDetectSuggestions: []
        property bool isDetecting: false

        function runAutoDetect() {
            if (!backend) return;
            isDetecting = true;
            var res = backend.auto_detect_aliases() || [];
            autoDetectSuggestions = res;
            isDetecting = false;
            if (res.length > 0) {
                root.bannerMsg = "Found " + res.length + " suggested alias mapping(s). Review below to link.";
                root.bannerType = "info";
            } else {
                root.bannerMsg = "Auto-detect complete: No unmapped aliases found.";
                root.bannerType = "info";
            }
        }

        ColumnLayout {
            id: aliasesMainCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // Card Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text { text: "👤"; font.pixelSize: 24 }

                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true

                    Text {
                        text: "User Profiles & Identity Aliases"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }

                    Text {
                        text: "Combine multiple Git author names, emails, and TFS display identities into one unified profile for metrics, work items, and Team Motivation."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Button {
                    text: parent.parent.isDetecting ? "Scanning..." : "⚡ Auto-Detect Aliases"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#58a6ff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 155
                        radius: 6
                        color: parent.hovered ? Qt.rgba(31/255, 111/255, 235/255, 0.2) : Qt.rgba(31/255, 111/255, 235/255, 0.1)
                        border.color: "#388bfd"
                        border.width: 1
                    }
                    onClicked: parent.parent.runAutoDetect()
                }

                Button {
                    text: "👤 View User Profiles"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 145
                        radius: 6
                        color: parent.hovered ? "#8957e5" : "#6e40c9"
                        border.color: "#a371f7"
                        border.width: 1
                    }
                    onClicked: {
                        if (window && typeof window.openUsersPage === "function") {
                            window.openUsersPage();
                        } else {
                            window.currentTabIndex = 8;
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Auto-Detect Suggestions Panel (if any discovered)
            Rectangle {
                visible: aliasesMainCol.parent.autoDetectSuggestions.length > 0
                Layout.fillWidth: true
                implicitHeight: autoDetectSuggestionsCol.implicitHeight + 24
                radius: 6
                color: Qt.rgba(163/255, 113/255, 247/255, 0.08)
                border.color: "#8957e5"
                border.width: 1

                ColumnLayout {
                    id: autoDetectSuggestionsCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "💡"; font.pixelSize: 14 }
                        Text {
                            text: "Detected " + aliasesMainCol.parent.autoDetectSuggestions.length + " Potential Alias Matches"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#d2a8ff"
                            Layout.fillWidth: true
                        }
                        Button {
                            text: "Accept All"
                            font.pixelSize: 10
                            contentItem: Text { text: parent.text; font: parent.font; color: "#3fb950" }
                            background: Rectangle {
                                implicitHeight: 22
                                implicitWidth: 70
                                radius: 4
                                color: parent.hovered ? "#162b20" : "#0d1117"
                                border.color: "#238636"
                            }
                            onClicked: {
                                var list = aliasesMainCol.parent.autoDetectSuggestions;
                                for (var i = 0; i < list.length; i++) {
                                    backend.add_user_alias(list[i].canonical, list[i].alias);
                                }
                                aliasesMainCol.parent.autoDetectSuggestions = [];
                                root.bannerMsg = "All detected aliases linked successfully!";
                                root.bannerType = "success";
                            }
                        }
                        Button {
                            text: "Dismiss"
                            font.pixelSize: 10
                            contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e" }
                            background: Rectangle {
                                implicitHeight: 22
                                implicitWidth: 60
                                radius: 4
                                color: parent.hovered ? "#21262d" : "#0d1117"
                                border.color: "#30363d"
                            }
                            onClicked: aliasesMainCol.parent.autoDetectSuggestions = []
                        }
                    }

                    Repeater {
                        model: aliasesMainCol.parent.autoDetectSuggestions
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 4
                            color: "#0d1117"
                            border.color: "#30363d"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: modelData.alias
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#e3b341"
                                    Layout.preferredWidth: 160
                                    elide: Text.ElideRight
                                }
                                Text { text: "➔"; font.pixelSize: 11; color: "#8b949e" }
                                Text {
                                    text: modelData.canonical
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#58a6ff"
                                    Layout.preferredWidth: 150
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "(" + (modelData.reason || "Pattern match") + ")"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Button {
                                    text: "Link"
                                    font.pixelSize: 10
                                    contentItem: Text { text: parent.text; font: parent.font; color: "#3fb950" }
                                    background: Rectangle {
                                        implicitHeight: 20
                                        implicitWidth: 46
                                        radius: 3
                                        color: parent.hovered ? "#162b20" : "#21262d"
                                        border.color: "#238636"
                                    }
                                    onClicked: {
                                        backend.add_user_alias(modelData.canonical, modelData.alias);
                                        var arr = aliasesMainCol.parent.autoDetectSuggestions.slice();
                                        arr.splice(index, 1);
                                        aliasesMainCol.parent.autoDetectSuggestions = arr;
                                        root.bannerMsg = "Linked alias '" + modelData.alias + "' to '" + modelData.canonical + "'.";
                                        root.bannerType = "success";
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Add New User Alias Input Row
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: addAliasRow.implicitHeight + 16
                radius: 6
                color: "#0d1117"
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    id: addAliasRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Text {
                        text: "➕ Link New Alias:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: "#c9d1d9"
                    }

                    TextField {
                        id: txtCanonical
                        placeholderText: "Canonical User (e.g. Alice Smith)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#f0f6fc"
                        Layout.preferredWidth: 200
                        background: Rectangle {
                            implicitHeight: 28
                            radius: 4
                            color: "#161b22"
                            border.color: txtCanonical.activeFocus ? "#58a6ff" : "#30363d"
                        }
                    }

                    TextField {
                        id: txtAlias
                        placeholderText: "Alias / Git Nick / Email (e.g. asmith)"
                        font.family: "Consolas, Segoe UI, monospace"
                        font.pixelSize: 11
                        color: "#f0f6fc"
                        Layout.fillWidth: true
                        background: Rectangle {
                            implicitHeight: 28
                            radius: 4
                            color: "#161b22"
                            border.color: txtAlias.activeFocus ? "#58a6ff" : "#30363d"
                        }
                        onAccepted: btnAddAlias.clicked()
                    }

                    Button {
                        id: btnAddAlias
                        text: "Add Alias Mapping"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        enabled: txtCanonical.text.trim() !== "" && txtAlias.text.trim() !== ""
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#6e7681"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 28
                            implicitWidth: 140
                            radius: 4
                            color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#21262d"
                            border.color: parent.enabled ? "#3fb950" : "#30363d"
                        }
                        onClicked: {
                            var c = txtCanonical.text.trim();
                            var a = txtAlias.text.trim();
                            if (c && a && backend) {
                                var ok = backend.add_user_alias(c, a);
                                if (ok) {
                                    txtAlias.text = "";
                                    root.bannerMsg = "Added alias '" + a + "' to '" + c + "'.";
                                    root.bannerType = "success";
                                } else {
                                    root.bannerMsg = "Failed to add user alias.";
                                    root.bannerType = "error";
                                }
                            }
                        }
                    }
                }
            }

            // Existing Mappings Header & Search
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Configured User Mappings (" + (backend && backend.userAliases ? backend.userAliases.length : 0) + ")"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: "#c9d1d9"
                }

                Item { Layout.fillWidth: true }

                TextField {
                    id: txtSearchAliases
                    placeholderText: "Search user or alias..."
                    font.pixelSize: 11
                    color: "#f0f6fc"
                    Layout.preferredWidth: 200
                    background: Rectangle {
                        implicitHeight: 26
                        radius: 4
                        color: "#0d1117"
                        border.color: txtSearchAliases.activeFocus ? "#58a6ff" : "#30363d"
                    }
                }
            }

            // Table / List of User Aliases
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: {
                        var all = (backend && backend.userAliases) ? backend.userAliases : [];
                        var q = txtSearchAliases.text.trim().toLowerCase();
                        if (!q) return all;
                        return all.filter(function(item) {
                            if (item.canonical && item.canonical.toLowerCase().indexOf(q) !== -1) return true;
                            if (item.aliases) {
                                for (var i = 0; i < item.aliases.length; i++) {
                                    if (item.aliases[i].toLowerCase().indexOf(q) !== -1) return true;
                                }
                            }
                            return false;
                        });
                    }

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rowContentCol.implicitHeight + 16
                        radius: 6
                        color: "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        property string canonicalName: modelData.canonical || ""
                        property var aliasesList: modelData.aliases || []

                        ColumnLayout {
                            id: rowContentCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // User Avatar Circle
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: "#1f6feb"
                                    Text {
                                        anchors.centerIn: parent
                                        text: canonicalName ? canonicalName.charAt(0).toUpperCase() : "?"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                }

                                Text {
                                    text: canonicalName
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Rectangle {
                                    implicitHeight: 18
                                    implicitWidth: cntTxt.implicitWidth + 10
                                    radius: 9
                                    color: "#21262d"
                                    border.color: "#30363d"
                                    Text {
                                        id: cntTxt
                                        anchors.centerIn: parent
                                        text: aliasesList.length + " alias" + (aliasesList.length === 1 ? "" : "es")
                                        font.pixelSize: 9
                                        color: "#8b949e"
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Profile shortcut button
                                Button {
                                    text: "View Profile ➔"
                                    font.pixelSize: 10
                                    contentItem: Text { text: parent.text; font: parent.font; color: "#58a6ff" }
                                    background: Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: 90
                                        radius: 4
                                        color: parent.hovered ? "#21262d" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        if (window && typeof window.openUsersPage === "function") {
                                            window.openUsersPage(canonicalName);
                                        }
                                    }
                                }
                            }

                            // Aliases Chip Flow
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: aliasesList
                                    delegate: Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: chipRow.implicitWidth + 12
                                        radius: 4
                                        color: "#161b22"
                                        border.color: "#30363d"

                                        RowLayout {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Text {
                                                text: "@" + modelData
                                                font.family: "Consolas, Segoe UI, monospace"
                                                font.pixelSize: 10
                                                color: "#79c0ff"
                                            }

                                            Text {
                                                text: "✕"
                                                font.pixelSize: 9
                                                color: delAliasMa.containsMouse ? "#ff7b72" : "#8b949e"
                                                MouseArea {
                                                    id: delAliasMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        backend.remove_user_alias(canonicalName, modelData);
                                                        root.bannerMsg = "Removed alias '@" + modelData + "'.";
                                                        root.bannerType = "info";
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Quick Inline Add Alias
                                Rectangle {
                                    implicitHeight: 22
                                    implicitWidth: inlineAddRow.implicitWidth + 8
                                    radius: 4
                                    color: "#161b22"
                                    border.color: inFocus ? "#58a6ff" : "#30363d"
                                    property bool inFocus: txtInlineAlias.activeFocus

                                    RowLayout {
                                        id: inlineAddRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        TextInput {
                                            id: txtInlineAlias
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 10
                                            color: "#f0f6fc"
                                            clip: true
                                            Layout.preferredWidth: Math.max(70, Math.min(130, contentWidth + 10))
                                            Text {
                                                anchors.fill: parent
                                                visible: !parent.text && !parent.activeFocus
                                                text: "+ Add alias..."
                                                font.pixelSize: 10
                                                color: "#6e7681"
                                            }
                                            onAccepted: {
                                                if (text.trim() !== "") {
                                                    backend.add_user_alias(canonicalName, text.trim());
                                                    text = "";
                                                    root.bannerMsg = "Alias added to " + canonicalName + ".";
                                                    root.bannerType = "success";
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty State if no aliases configured
                Rectangle {
                    visible: !backend || !backend.userAliases || backend.userAliases.length === 0
                    Layout.fillWidth: true
                    implicitHeight: 120
                    radius: 6
                    color: "#0d1117"
                    border.color: "#30363d"

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "No user aliases configured yet"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: "#8b949e"
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Click 'Auto-Detect Aliases' above or add mappings to unify git commit identities."
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#6e7681"
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // System Users & Bots Card (Hall of Fame Exclusion)
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: systemUsersMainCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        property string sysSearchQuery: ""
        property string sysFilterType: "all" // "all", "custom", "builtin"
        property var autoDetectSysSuggestions: []
        property bool isDetectingSys: false

        function runAutoDetectSys() {
            if (!backend) return;
            isDetectingSys = true;
            var res = backend.get_potential_system_users() || [];
            autoDetectSysSuggestions = res;
            isDetectingSys = false;
            if (res.length > 0) {
                root.bannerMsg = "Found " + res.length + " potential system / automation accounts. Review below to exclude.";
                root.bannerType = "info";
            } else {
                root.bannerMsg = "Auto-detect complete: No new bot or service accounts detected.";
                root.bannerType = "info";
            }
        }

        ColumnLayout {
            id: systemUsersMainCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // Card Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text { text: "🤖"; font.pixelSize: 24 }

                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true

                    RowLayout {
                        spacing: 8
                        Text {
                            text: "System Users & Automation Bots"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }

                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: sysCountBadge.implicitWidth + 12
                            radius: 10
                            color: "#f0883e22"
                            border.color: "#f0883e"
                            border.width: 1
                            Text {
                                id: sysCountBadge
                                anchors.centerIn: parent
                                text: (backend && backend.systemUsersCount ? backend.systemUsersCount : 0) + " Custom Excluded"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: "#f0883e"
                            }
                        }
                    }

                    Text {
                        text: "Exclude automated service accounts, build bots, and CI agents. Any commits, PRs, work items, or builds by these accounts are excluded from the Hall of Fame, leaderboards, streaks, and MVP points."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Button {
                    text: systemUsersMainCol.parent.isDetectingSys ? "Scanning..." : "⚡ Auto-Detect Bots"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0883e"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 145
                        radius: 6
                        color: parent.hovered ? "#2d2218" : "#1f1a14"
                        border.color: "#f0883e"
                        border.width: 1
                    }
                    onClicked: systemUsersMainCol.parent.runAutoDetectSys()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Auto-Detect Suggestions Bar
            Rectangle {
                visible: systemUsersMainCol.parent.autoDetectSysSuggestions && systemUsersMainCol.parent.autoDetectSysSuggestions.length > 0
                Layout.fillWidth: true
                implicitHeight: sysSuggCol.implicitHeight + 20
                radius: 6
                color: "#161f2e"
                border.color: "#388bfd"
                border.width: 1

                ColumnLayout {
                    id: sysSuggCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "💡"; font.pixelSize: 14 }
                        Text {
                            text: "Detected " + systemUsersMainCol.parent.autoDetectSysSuggestions.length + " candidate system/bot account(s):"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#58a6ff"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Dismiss"
                            font.pixelSize: 11
                            color: "#8b949e"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: systemUsersMainCol.parent.autoDetectSysSuggestions = []
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: systemUsersMainCol.parent.autoDetectSysSuggestions
                            delegate: Rectangle {
                                implicitHeight: 28
                                implicitWidth: pillRow.implicitWidth + 16
                                radius: 14
                                color: "#0d1b2e"
                                border.color: "#388bfd"
                                border.width: 1

                                RowLayout {
                                    id: pillRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "🤖 " + modelData.name + " (" + (modelData.reason || (modelData.sources ? modelData.sources.join(", ") : "Detected account")) + ")"
                                        font.pixelSize: 11
                                        font.family: "Segoe UI, sans-serif"
                                        color: "#f0f6fc"
                                    }
                                    Text {
                                        text: "+ Exclude"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#f0883e"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (backend) {
                                            backend.add_system_user(modelData.name, modelData.reason || "Auto-detected bot account");
                                            var cur = systemUsersMainCol.parent.autoDetectSysSuggestions.slice();
                                            cur.splice(index, 1);
                                            systemUsersMainCol.parent.autoDetectSysSuggestions = cur;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Add New System User Row
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: addSysRow.implicitHeight + 16
                radius: 6
                color: "#0d1117"
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    id: addSysRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text { text: "➕"; font.pixelSize: 14 }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 260
                        implicitHeight: 32
                        radius: 4
                        color: "#161b22"
                        border.color: sysNameInput.activeFocus ? "#f0883e" : "#30363d"
                        border.width: 1

                        TextInput {
                            id: sysNameInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#f0f6fc"
                            selectByMouse: true

                            Text {
                                text: "Enter account / bot name or email (e.g. tfs_build_agent, release-pipeline)"
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#6e7681"
                                visible: !sysNameInput.text && !sysNameInput.activeFocus
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 200
                        implicitHeight: 32
                        radius: 4
                        color: "#161b22"
                        border.color: sysNoteInput.activeFocus ? "#f0883e" : "#30363d"
                        border.width: 1

                        TextInput {
                            id: sysNoteInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            color: "#f0f6fc"
                            selectByMouse: true

                            Text {
                                text: "Optional description (e.g. CI Agent)"
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#6e7681"
                                visible: !sysNoteInput.text && !sysNoteInput.activeFocus
                            }
                        }
                    }

                    Button {
                        text: "Exclude from Hall of Fame"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        enabled: sysNameInput.text.trim().length > 0
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: parent.enabled ? "#ffffff" : "#6e7681"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 32
                            implicitWidth: 185
                            radius: 6
                            color: parent.enabled ? (parent.hovered ? "#bd5c00" : "#d96500") : "#21262d"
                            border.color: parent.enabled ? "#f0883e" : "#30363d"
                            border.width: 1
                        }
                        onClicked: {
                            var n = sysNameInput.text.trim();
                            var note = sysNoteInput.text.trim();
                            if (n && backend) {
                                backend.add_system_user(n, note);
                                sysNameInput.text = "";
                                sysNoteInput.text = "";
                                root.bannerMsg = "Excluded '" + n + "' from Hall of Fame rankings.";
                                root.bannerType = "success";
                            }
                        }
                    }
                }
            }

            // Filter / Search Toolbar for System Users List
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 260
                    implicitHeight: 28
                    radius: 4
                    color: "#0d1117"
                    border.color: sysFilterInput.activeFocus ? "#58a6ff" : "#30363d"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4
                        Text { text: "🔍"; font.pixelSize: 10 }
                        TextInput {
                            id: sysFilterInput
                            Layout.fillWidth: true
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#c9d1d9"
                            selectByMouse: true
                            onTextChanged: systemUsersMainCol.parent.sysSearchQuery = text

                            Text {
                                text: "Filter system accounts..."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#6e7681"
                                visible: !sysFilterInput.text && !sysFilterInput.activeFocus
                            }
                        }
                    }
                }

                Row {
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "all", label: "All Accounts" },
                            { id: "custom", label: "Custom Excluded" },
                            { id: "builtin", label: "Built-in Defaults" }
                        ]
                        delegate: Rectangle {
                            property bool isSelected: systemUsersMainCol.parent.sysFilterType === modelData.id
                            implicitHeight: 26
                            implicitWidth: sysPillTxt.implicitWidth + 16
                            radius: 13
                            color: isSelected ? Qt.rgba(240/255, 136/255, 62/255, 0.2) : (pMa.containsMouse ? "#21262d" : "#0d1117")
                            border.color: isSelected ? "#f0883e" : "#30363d"
                            border.width: 1

                            Text {
                                id: sysPillTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 10
                                font.weight: parent.isSelected ? Font.Bold : Font.Normal
                                color: parent.isSelected ? "#f0883e" : "#8b949e"
                            }
                            MouseArea {
                                id: pMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: systemUsersMainCol.parent.sysFilterType = modelData.id
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Configured System Users List
            ColumnLayout {
                id: sysListCol
                Layout.fillWidth: true
                spacing: 6

                property var filteredSysUsers: {
                    var all = (backend && backend.systemUsers) ? backend.systemUsers : [];
                    var q = systemUsersMainCol.parent.sysSearchQuery.trim().toLowerCase();
                    var fType = systemUsersMainCol.parent.sysFilterType;
                    return all.filter(function(item) {
                        if (!item || !item.name) return false;
                        if (fType === "custom" && item.is_builtin) return false;
                        if (fType === "builtin" && !item.is_builtin) return false;
                        if (q !== "") {
                            var nMatch = item.name.toLowerCase().indexOf(q) !== -1;
                            var noteMatch = item.note && item.note.toLowerCase().indexOf(q) !== -1;
                            return nMatch || noteMatch;
                        }
                        return true;
                    });
                }

                Repeater {
                    model: sysListCol.filteredSysUsers
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 6
                        color: "#0d1117"
                        border.color: modelData.is_builtin ? "#21262d" : "#44351a"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Text {
                                text: modelData.is_builtin ? "⚙️" : "🤖"
                                font.pixelSize: 16
                            }

                            Text {
                                text: modelData.name
                                font.family: "Consolas, Segoe UI, monospace"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: modelData.is_builtin ? "#8b949e" : "#f0f6fc"
                            }

                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: badgeT.implicitWidth + 10
                                radius: 9
                                color: modelData.is_builtin ? "#21262d" : "#f0883e22"
                                border.color: modelData.is_builtin ? "#30363d" : "#f0883e"
                                border.width: 1
                                Text {
                                    id: badgeT
                                    anchors.centerIn: parent
                                    text: modelData.is_builtin ? "Built-in" : "Custom Excluded"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    color: modelData.is_builtin ? "#8b949e" : "#f0883e"
                                }
                            }

                            Text {
                                text: modelData.note || ""
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#6e7681"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Button {
                                visible: !modelData.is_builtin
                                text: "🗑️ Remove"
                                font.pixelSize: 11
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: parent.hovered ? "#f85149" : "#8b949e"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 26
                                    implicitWidth: 78
                                    radius: 4
                                    color: parent.hovered ? "#281515" : "transparent"
                                    border.color: parent.hovered ? "#f85149" : "#30363d"
                                    border.width: 1
                                }
                                onClicked: {
                                    if (backend) {
                                        backend.remove_system_user(modelData.name);
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty State if no filtered system users
                Rectangle {
                    visible: sysListCol.filteredSysUsers.length === 0
                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: 6
                    color: "#0d1117"
                    border.color: "#21262d"

                    Text {
                        anchors.centerIn: parent
                        text: "No system accounts matching current filter."
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }
            }
        }
    }
}
