import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root

    property string searchQuery: ""
    property string activeFilter: "all" // "all", "active_24h", "active_sprint", "has_aliases"
    property string sortBy: "last_active" // "last_active", "score", "name", "tasks", "commits"
    property var selectedUser: null
    property bool isInspectorOpen: selectedUser !== null
    property var autoDetectSuggestions: []
    property bool isAutoDetectOpen: false
    property string newAliasInput: ""
    property string manualCanonInput: ""
    property string manualAliasInput: ""
    property bool isAddAliasModalOpen: false
    property bool isAliasesCollapsed: false
    property bool isLastActivityCollapsed: false
    property bool isTimelineCollapsed: false
    property bool isTasksCollapsed: false
    property bool isBadgesCollapsed: false
    property real inspectorWidth: (backend && backend.rightSidebarWidth) ? backend.rightSidebarWidth : 420

    Connections {
        target: backend
        function onRightSidebarWidthChanged(w) {
            root.inspectorWidth = w;
        }
    }

    function toggleAllInspectorGroups() {
        var allCollapsed = isAliasesCollapsed && isLastActivityCollapsed && isTimelineCollapsed && isTasksCollapsed && isBadgesCollapsed;
        var newState = !allCollapsed;
        isAliasesCollapsed = newState;
        isLastActivityCollapsed = newState;
        isTimelineCollapsed = newState;
        isTasksCollapsed = newState;
        isBadgesCollapsed = newState;
    }

    // Raw profiles from backend
    readonly property var rawProfiles: (backend && typeof backend.get_all_user_profiles === "function")
        ? (backend.get_all_user_profiles() || [])
        : []

    // Candidate other profiles eligible to be linked as an alias
    readonly property var candidateProfiles: {
        var list = root.rawProfiles || [];
        var curName = root.selectedUser ? root.selectedUser.name : "";
        var existingAliases = (root.selectedUser && root.selectedUser.aliases) ? root.selectedUser.aliases : [];
        var res = [];
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (!p || !p.name) continue;
            if (p.name === curName) continue;
            if (p.is_aliased) continue;
            if (existingAliases.indexOf(p.name) !== -1) continue;
            res.push(p.name);
        }
        res.sort(function(a, b) { return a.localeCompare(b); });
        return res;
    }

    // Filtered and sorted profiles list
    readonly property var filteredProfiles: {
        var list = root.rawProfiles || [];
        var query = root.searchQuery.trim().toLowerCase();
        var filter = root.activeFilter;

        var result = list.filter(function(m) {
            if (!m || !m.name) return false;

            // Search filter
            if (query !== "") {
                var nameMatch = m.name.toLowerCase().indexOf(query) !== -1;
                var initialsMatch = m.initials && m.initials.toLowerCase().indexOf(query) !== -1;
                var personaMatch = m.time_stats && m.time_stats.persona && m.time_stats.persona.toLowerCase().indexOf(query) !== -1;
                var aliasMatch = false;
                if (m.aliases && m.aliases.length > 0) {
                    for (var i = 0; i < m.aliases.length; i++) {
                        if (m.aliases[i].toLowerCase().indexOf(query) !== -1) {
                            aliasMatch = true;
                            break;
                        }
                    }
                }
                var aliasedToMatch = m.is_aliased && m.aliased_to && m.aliased_to.toLowerCase().indexOf(query) !== -1;
                if (!nameMatch && !initialsMatch && !personaMatch && !aliasMatch && !aliasedToMatch) {
                    return false;
                }
            }

            // Category filters
            if (filter === "system_users") {
                return !!m.is_system_user;
            } else if (filter === "has_aliases") {
                return !m.is_aliased && !m.is_system_user && m.aliases && m.aliases.length > 0;
            } else if (filter === "active_sprint") {
                return !m.is_aliased && !m.is_system_user && ((m.score && m.score > 0) || (m.last_active_date && m.last_active_date !== ""));
            } else if (filter === "active_24h") {
                if (m.is_aliased || m.is_system_user || !m.last_active_date) return false;
                var lastRel = m.last_activity ? m.last_activity.relative : "";
                return lastRel.indexOf("m ago") !== -1 || lastRel.indexOf("h ago") !== -1 || lastRel.indexOf("s ago") !== -1 || lastRel.indexOf("Just now") !== -1;
            } else if (filter === "aliased") {
                return !!m.is_aliased;
            }
            return true;
        });

        // Sorting
        var s = root.sortBy;
        result.sort(function(a, b) {
            // Non-aliased profiles always sort before aliased ones when sorting by score or rank
            if (a.is_aliased !== b.is_aliased && (s === "score" || s === "last_active" || s === "tasks" || s === "commits")) {
                return a.is_aliased ? 1 : -1;
            }
            if (s === "score") {
                return (b.score || 0) - (a.score || 0);
            } else if (s === "name") {
                return a.name.localeCompare(b.name);
            } else if (s === "tasks") {
                return (b.tasks_completed || 0) - (a.tasks_completed || 0);
            } else if (s === "commits") {
                return (b.commits_count || 0) - (a.commits_count || 0);
            } else {
                // last_active default
                var dtA = a.last_active_date || "";
                var dtB = b.last_active_date || "";
                if (dtA !== dtB) return dtB.localeCompare(dtA);
                return (b.score || 0) - (a.score || 0);
            }
        });

        return result;
    }

    // Refresh selected user when profiles reload
    onRawProfilesChanged: {
        if (selectedUser && selectedUser.name) {
            var found = null;
            for (var i = 0; i < rawProfiles.length; i++) {
                if (rawProfiles[i].name === selectedUser.name) {
                    found = rawProfiles[i];
                    break;
                }
            }
            selectedUser = found;
        }
    }

    function selectUser(userObj) {
        selectedUser = userObj;
    }

    function selectUserByName(userName) {
        if (!userName) return;
        var target = userName.trim().toLowerCase();
        for (var i = 0; i < rawProfiles.length; i++) {
            var m = rawProfiles[i];
            if (m.name.toLowerCase() === target) {
                selectedUser = m;
                return;
            }
            if (m.aliases) {
                for (var j = 0; j < m.aliases.length; j++) {
                    if (m.aliases[j].toLowerCase() === target) {
                        selectedUser = m;
                        return;
                    }
                }
            }
        }
    }

    function runAutoDetect() {
        if (backend && typeof backend.auto_detect_aliases === "function") {
            autoDetectSuggestions = backend.auto_detect_aliases() || [];
            isAutoDetectOpen = true;
        }
    }

    function acceptSuggestion(canonical, alias) {
        if (backend && typeof backend.add_user_alias === "function") {
            backend.add_user_alias(canonical, alias);
            runAutoDetect();
        }
    }

    function findUserByName(name) {
        if (!name || !root.rawProfiles) return null;
        for (var i = 0; i < root.rawProfiles.length; i++) {
            if (root.rawProfiles[i].name === name) return root.rawProfiles[i];
        }
        return null;
    }

    function addAliasToSelectedUser(alias) {
        if (!selectedUser || !alias || !alias.trim()) return;
        if (backend && typeof backend.add_user_alias === "function") {
            backend.add_user_alias(selectedUser.name, alias.trim());
            newAliasInput = "";
        }
    }

    function removeAliasFromSelectedUser(alias) {
        if (!selectedUser || !alias) return;
        if (backend && typeof backend.remove_user_alias === "function") {
            backend.remove_user_alias(selectedUser.name, alias);
        }
    }

    function unlinkAliasProfile(canonicalName, aliasName) {
        if (backend && typeof backend.remove_user_alias === "function") {
            backend.remove_user_alias(canonicalName, aliasName);
        }
    }

    // Global background
    Rectangle {
        anchors.fill: parent
        color: "#0d1117"
    }

    // ==========================================
    // Main Content Split Layout
    // ==========================================
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================
        // Left Area: Header, Controls & User Cards
        // ==========================================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ------------------------------------------
            // Top Header & Statistics Banner
            // ------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headerCol.implicitHeight + 28
                color: "#161b22"
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: headerCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Title Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            width: 38
                            height: 38
                            radius: 8
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#1f6feb" }
                                GradientStop { position: 1.0; color: "#8957e5" }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "👤"
                                font.pixelSize: 18
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "Users & Contributor Profiles"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                Rectangle {
                                    implicitWidth: totalBadgeText.implicitWidth + 12
                                    implicitHeight: 20
                                    radius: 10
                                    color: Qt.rgba(31 / 255, 111 / 255, 235 / 255, 0.2)
                                    border.color: "#1f6feb"
                                    border.width: 1

                                    Text {
                                        id: totalBadgeText
                                        anchors.centerIn: parent
                                        text: (root.rawProfiles ? root.rawProfiles.length : 0) + " Team Members"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: "#58a6ff"
                                    }
                                }
                            }

                            Text {
                                text: "Unified identities, alias resolution across Git & TFS, real-time activity timelines, and productivity profiles."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                            }
                        }

                        // Top Action Buttons
                        Row {
                            spacing: 8

                            Button {
                                text: "⚡ Auto-Detect Aliases"
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
                                    implicitHeight: 32
                                    implicitWidth: 155
                                    radius: 6
                                    color: parent.hovered ? "#8957e5" : "#6e40c9"
                                    border.color: "#a371f7"
                                    border.width: 1
                                }
                                onClicked: root.runAutoDetect()
                            }

                            Button {
                                text: "➕ Link Alias"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#c9d1d9"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 32
                                    implicitWidth: 100
                                    radius: 6
                                    color: parent.hovered ? "#30363d" : "#21262d"
                                    border.color: "#30363d"
                                    border.width: 1
                                }
                                onClicked: isAddAliasModalOpen = true
                            }

                            Button {
                                text: "🔄 Refresh"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#c9d1d9"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    implicitHeight: 32
                                    implicitWidth: 80
                                    radius: 6
                                    color: parent.hovered ? "#30363d" : "#161b22"
                                    border.color: "#30363d"
                                    border.width: 1
                                }
                                onClicked: {
                                    if (backend) backend.recompute_team_motivation();
                                }
                            }
                        }
                    }

                    // KPI Counters Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // KPI: Total Members
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: 6
                            color: "#0d1117"
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Text { text: "👥"; font.pixelSize: 16 }
                                Column {
                                    Text { text: "TOTAL USERS"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: {
                                            var list = root.rawProfiles || [];
                                            var activeCount = 0;
                                            var aliasedCount = 0;
                                            for (var i = 0; i < list.length; i++) {
                                                if (list[i].is_aliased) aliasedCount++;
                                                else activeCount++;
                                            }
                                            return "" + activeCount + (aliasedCount > 0 ? " (+" + aliasedCount + " 🔗)" : "");
                                        }
                                        font.pixelSize: 14; font.weight: Font.Bold; color: "#f0f6fc"
                                    }
                                }
                            }
                        }

                        // KPI: Active This Week
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: 6
                            color: "#0d1117"
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Text { text: "🟢"; font.pixelSize: 14 }
                                Column {
                                    Text { text: "ACTIVE RECENTLY"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: {
                                            var active = 0;
                                            var list = root.rawProfiles || [];
                                            for (var i = 0; i < list.length; i++) {
                                                if (!list[i].is_aliased && (list[i].score > 0 || (list[i].last_active_date && list[i].last_active_date !== ""))) active++;
                                            }
                                            return "" + active;
                                        }
                                        font.pixelSize: 14; font.weight: Font.Bold; color: "#3fb950"
                                    }
                                }
                            }
                        }

                        // KPI: Aliases Configured
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: 6
                            color: "#0d1117"
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Text { text: "🔗"; font.pixelSize: 16 }
                                Column {
                                    Text { text: "MAPPED ALIASES"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: {
                                            var count = 0;
                                            var list = root.rawProfiles || [];
                                            for (var i = 0; i < list.length; i++) {
                                                if (list[i].aliases) count += list[i].aliases.length;
                                            }
                                            return "" + count;
                                        }
                                        font.pixelSize: 14; font.weight: Font.Bold; color: "#a371f7"
                                    }
                                }
                            }
                        }

                        // KPI: Top Scorer
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: 6
                            color: "#0d1117"
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Text { text: "👑"; font.pixelSize: 16 }
                                Column {
                                    Text { text: "LEADER / MVP"; font.pixelSize: 9; font.weight: Font.Bold; color: "#8b949e" }
                                    Text {
                                        text: {
                                            var list = root.rawProfiles || [];
                                            for (var i = 0; i < list.length; i++) {
                                                if (!list[i].is_aliased && list[i].score > 0) {
                                                    return list[i].name + " (" + list[i].score + " pts)";
                                                }
                                            }
                                            return "—";
                                        }
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: "#e3b341"
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------
            // Filter Toolbar & Search Bar
            // ------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                color: "#161b22"
                border.color: "#30363d"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Search Input Box
                    Rectangle {
                        implicitWidth: 260
                        implicitHeight: 32
                        radius: 6
                        color: "#0d1117"
                        border.color: searchInput.activeFocus ? "#58a6ff" : "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text { text: "🔍"; font.pixelSize: 12 }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                text: root.searchQuery
                                color: "#c9d1d9"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                selectByMouse: true
                                onTextChanged: root.searchQuery = text

                                Text {
                                    text: "Search name, alias, persona..."
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    color: "#6e7681"
                                    visible: !searchInput.text && !searchInput.activeFocus
                                }
                            }

                            Text {
                                visible: root.searchQuery !== ""
                                text: "✕"
                                font.pixelSize: 11
                                color: "#8b949e"
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchInput.text = "";
                                        root.searchQuery = "";
                                    }
                                }
                            }
                        }
                    }

                    // Filter Chips
                    Row {
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "all", label: "All Users" },
                                { id: "active_24h", label: "🟢 Active Today" },
                                { id: "active_sprint", label: "⚡ Active This Sprint" },
                                { id: "has_aliases", label: "🔗 Has Aliases" },
                                { id: "aliased", label: "🔗 Linked Aliases" },
                                { id: "system_users", label: "🤖 System Users" }
                            ]

                            Rectangle {
                                property bool isSelected: root.activeFilter === modelData.id
                                implicitHeight: 28
                                implicitWidth: chipText.implicitWidth + 16
                                radius: 14
                                color: isSelected ? Qt.rgba(31 / 255, 111 / 255, 235 / 255, 0.25) : (chipMa.containsMouse ? "#21262d" : "#0d1117")
                                border.color: isSelected ? "#58a6ff" : "#30363d"
                                border.width: 1

                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.weight: parent.isSelected ? Font.Bold : Font.Normal
                                    color: parent.isSelected ? "#58a6ff" : "#8b949e"
                                }

                                MouseArea {
                                    id: chipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.activeFilter = modelData.id
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Sort By Dropdown
                    RowLayout {
                        spacing: 6
                        Text {
                            text: "Sort by:"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                        }

                        ComboBox {
                            id: sortCombo
                            implicitHeight: 30
                            implicitWidth: 150
                            model: [
                                { text: "🕒 Last Active", id: "last_active" },
                                { text: "👑 Total XP / Score", id: "score" },
                                { text: "🔤 Name (A-Z)", id: "name" },
                                { text: "✅ Tasks Done", id: "tasks" },
                                { text: "💻 Total Commits", id: "commits" }
                            ]
                            textRole: "text"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            currentIndex: 0
                            onCurrentIndexChanged: {
                                if (currentIndex >= 0 && currentIndex < model.length) {
                                    root.sortBy = model[currentIndex].id;
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------
            // Main User Directory List / Grid
            // ------------------------------------------
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: parent.width
                clip: true

                ColumnLayout {
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Item { height: 6 }

                    // Empty State
                    Rectangle {
                        visible: root.filteredProfiles.length === 0
                        Layout.fillWidth: true
                        implicitHeight: 200
                        radius: 8
                        color: "#161b22"
                        border.color: "#30363d"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "🔍"
                                font.pixelSize: 32
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: "No user profiles found matching your search."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: "#c9d1d9"
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: "Try adjusting your query, clear filters, or sync new data from Azure DevOps."
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                color: "#8b949e"
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // User Profile Cards Repeater
                    Repeater {
                        model: root.filteredProfiles

                        Rectangle {
                            id: userCard
                            Layout.fillWidth: true
                            implicitHeight: cardCol.implicitHeight + 24
                            radius: 8
                            opacity: modelData.is_aliased ? 0.55 : 1.0
                            property bool isSelected: root.selectedUser && root.selectedUser.name === modelData.name
                            color: isSelected ? Qt.rgba(31 / 255, 111 / 255, 235 / 255, 0.12) : (cardMa.containsMouse ? "#1c2128" : "#161b22")
                            border.color: isSelected ? "#58a6ff" : (cardMa.containsMouse ? "#484f58" : "#30363d")
                            border.width: isSelected ? 2 : 1

                            ColumnLayout {
                                id: cardCol
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                // Top Row: Avatar, Name, Persona, Score Badge, View Profile Button
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    // Avatar with initials & online pulse
                                    Item {
                                        width: 44
                                        height: 44

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 22
                                            gradient: Gradient {
                                                GradientStop {
                                                    position: 0.0
                                                    color: {
                                                        var h = 0;
                                                        for (var i = 0; i < modelData.name.length; i++) h = (h * 31 + modelData.name.charCodeAt(i)) & 0xffffff;
                                                        var hue = Math.abs(h % 360) / 360.0;
                                                        return Qt.hsla(hue, 0.7, 0.5, 1.0);
                                                    }
                                                }
                                                GradientStop {
                                                    position: 1.0
                                                    color: "#161b22"
                                                }
                                            }
                                            border.color: Qt.rgba(255, 255, 255, 0.2)
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.initials || "??"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                                color: "#ffffff"
                                            }
                                        }

                                        // Activity indicator dot (hidden for aliased profiles)
                                        Rectangle {
                                            visible: !modelData.is_aliased
                                            anchors.bottom: parent.bottom
                                            anchors.right: parent.right
                                            width: 12
                                            height: 12
                                            radius: 6
                                            color: {
                                                var lastRel = modelData.last_activity ? modelData.last_activity.relative : "";
                                                if (lastRel.indexOf("m ago") !== -1 || lastRel.indexOf("s ago") !== -1 || lastRel.indexOf("Just now") !== -1) return "#3fb950";
                                                if (lastRel.indexOf("h ago") !== -1) return "#2ea043";
                                                if (lastRel.indexOf("Yesterday") !== -1) return "#d29922";
                                                return "#6e7681";
                                            }
                                            border.color: "#161b22"
                                            border.width: 2
                                        }
                                    }

                                    // User Name & Role Persona
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: modelData.name
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 15
                                                font.weight: Font.Bold
                                                color: "#f0f6fc"
                                            }

                                            // Rank Badge (active non-aliased members only)
                                            Rectangle {
                                                visible: !modelData.is_aliased && !!(modelData.rank && modelData.rank <= 10)
                                                implicitWidth: rankText.implicitWidth + 10
                                                implicitHeight: 18
                                                radius: 9
                                                color: modelData.rank === 1 ? Qt.rgba(242 / 255, 204 / 255, 17 / 255, 0.2) : (modelData.rank === 2 ? Qt.rgba(160 / 255, 174 / 255, 192 / 255, 0.2) : Qt.rgba(205 / 255, 127 / 255, 50 / 255, 0.2))
                                                border.color: modelData.rank === 1 ? "#f2cc11" : (modelData.rank === 2 ? "#a0aec0" : "#cd7f32")
                                                border.width: 1

                                                Text {
                                                    id: rankText
                                                    anchors.centerIn: parent
                                                    text: modelData.rank === 1 ? "🥇 #1 MVP" : (modelData.rank === 2 ? "🥈 #2" : (modelData.rank === 3 ? "🥉 #3" : "#" + modelData.rank))
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: modelData.rank === 1 ? "#f2cc11" : (modelData.rank === 2 ? "#e2e8f0" : "#f6ad55")
                                                }
                                            }

                                            // Streak flame pill (active non-aliased members only)
                                            Rectangle {
                                                visible: !modelData.is_aliased && !!(modelData.current_streak_weeks && modelData.current_streak_weeks >= 2)
                                                implicitWidth: streakText.implicitWidth + 8
                                                implicitHeight: 18
                                                radius: 9
                                                color: Qt.rgba(240 / 255, 136 / 255, 62 / 255, 0.2)
                                                border.color: "#f0883e"
                                                border.width: 1

                                                Text {
                                                    id: streakText
                                                    anchors.centerIn: parent
                                                    text: "🔥 " + modelData.current_streak_weeks + "w"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: "#ff9b57"
                                                }
                                            }

                                            // Linked Profile Pill (for aliased profiles)
                                            Rectangle {
                                                visible: !!modelData.is_aliased
                                                implicitWidth: aliasedBadgeText.implicitWidth + 10
                                                implicitHeight: 18
                                                radius: 9
                                                color: Qt.rgba(163 / 255, 113 / 255, 247 / 255, 0.2)
                                                border.color: "#a371f7"
                                                border.width: 1

                                                Text {
                                                    id: aliasedBadgeText
                                                    anchors.centerIn: parent
                                                    text: "🔗 Linked Profile"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: "#d2a8ff"
                                                }
                                            }

                                            // System User Excluded Pill
                                            Rectangle {
                                                visible: !!modelData.is_system_user
                                                implicitWidth: systemUserBadgeText.implicitWidth + 10
                                                implicitHeight: 18
                                                radius: 9
                                                color: Qt.rgba(248 / 255, 81 / 255, 73 / 255, 0.2)
                                                border.color: "#f85149"
                                                border.width: 1

                                                Text {
                                                    id: systemUserBadgeText
                                                    anchors.centerIn: parent
                                                    text: "🤖 System User"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: "#ff7b72"
                                                }
                                            }
                                        }

                                        // Persona & Working Style Chip / Linked attribution
                                        Text {
                                            text: modelData.is_aliased
                                                ? ("🔗 Linked alias of @" + (modelData.aliased_to || "primary profile"))
                                                : ((modelData.time_stats && modelData.time_stats.persona) ? modelData.time_stats.persona : "☀️ Team Contributor")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: modelData.is_aliased ? "#a371f7" : "#8b949e"
                                        }
                                    }

                                    // Total Score Badge
                                    Rectangle {
                                        implicitHeight: 28
                                        implicitWidth: scoreText.implicitWidth + 16
                                        radius: 14
                                        color: modelData.is_aliased ? "#21262d" : Qt.rgba(227 / 255, 179 / 255, 65 / 255, 0.15)
                                        border.color: modelData.is_aliased ? "#30363d" : "#e3b341"
                                        border.width: 1

                                        Text {
                                            id: scoreText
                                            anchors.centerIn: parent
                                            text: modelData.is_aliased ? "🔗 Linked" : ("👑 " + (modelData.score || 0) + " pts")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: modelData.is_aliased ? "#8b949e" : "#e3b341"
                                        }
                                    }

                                    // Inspect Button
                                    Rectangle {
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        radius: 6
                                        color: inspMa.containsMouse ? "#30363d" : "#21262d"
                                        border.color: inspMa.containsMouse ? "#58a6ff" : "#30363d"
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: userCard.isSelected ? "✕" : "→"
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            color: userCard.isSelected ? "#f85149" : "#58a6ff"
                                        }

                                        MouseArea {
                                            id: inspMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (userCard.isSelected) {
                                                    root.selectedUser = null;
                                                } else {
                                                    root.selectUser(modelData);
                                                }
                                            }
                                        }
                                    }
                                }

                                // Aliased to Primary link tag (shown when this is an aliased profile)
                                RowLayout {
                                    visible: !!modelData.is_aliased
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: "Primary Profile:"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#8b949e"
                                    }

                                    Rectangle {
                                        implicitWidth: primLinkText.implicitWidth + 14
                                        implicitHeight: 20
                                        radius: 4
                                        color: Qt.rgba(88 / 255, 166 / 255, 255 / 255, 0.15)
                                        border.color: "#388bfd"
                                        border.width: 1

                                        Text {
                                            id: primLinkText
                                            anchors.centerIn: parent
                                            text: "👤 " + (modelData.aliased_to || "")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var target = root.findUserByName(modelData.aliased_to);
                                                if (target) root.selectUser(target);
                                            }
                                        }
                                    }
                                }

                                // Aliases Tag Strip (shown when this is a canonical profile)
                                RowLayout {
                                    visible: !modelData.is_aliased
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: "Aliases:"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#6e7681"
                                    }

                                    // List of Aliases
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Repeater {
                                            model: modelData.aliases || []

                                            Rectangle {
                                                implicitWidth: aliasText.implicitWidth + 12
                                                implicitHeight: 20
                                                radius: 4
                                                color: "#21262d"
                                                border.color: "#30363d"
                                                border.width: 1

                                                Text {
                                                    id: aliasText
                                                    anchors.centerIn: parent
                                                    text: "@" + modelData
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    color: "#a371f7"
                                                }
                                            }
                                        }

                                        // Quick inline Add Alias Tag
                                        Rectangle {
                                            implicitWidth: 60
                                            implicitHeight: 20
                                            radius: 4
                                            color: addAlMa.containsMouse ? "#30363d" : "#161b22"
                                            border.color: "#30363d"
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: "+ Alias"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                                color: "#58a6ff"
                                            }

                                            MouseArea {
                                                id: addAlMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.selectUser(modelData);
                                                }
                                            }
                                        }
                                    }
                                }

                                // Last Activity Card Highlight
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 6
                                    color: "#0d1117"
                                    border.color: "#21262d"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: modelData.last_activity ? modelData.last_activity.icon : "📌"
                                            font.pixelSize: 12
                                        }

                                        Text {
                                            text: "Last Activity:"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#8b949e"
                                        }

                                        Text {
                                            text: modelData.last_activity ? modelData.last_activity.title : "No recorded events"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: "#c9d1d9"
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        // Relative Time Pill
                                        Rectangle {
                                            implicitWidth: relText.implicitWidth + 10
                                            implicitHeight: 18
                                            radius: 9
                                            color: Qt.rgba(56 / 255, 139 / 255, 253 / 255, 0.15)
                                            border.color: "#1f6feb"
                                            border.width: 1

                                            Text {
                                                id: relText
                                                anchors.centerIn: parent
                                                text: modelData.last_activity ? modelData.last_activity.relative : "Unknown"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: "#79c0ff"
                                            }
                                        }
                                    }
                                }

                                // Bottom Metric Chips: PRs, Commits, Tasks, Reviews
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // PRs chip
                                    Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: prChipText.implicitWidth + 14
                                        radius: 4
                                        color: "#21262d"
                                        border.color: "#30363d"
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "🔀"; font.pixelSize: 10 }
                                            Text { id: prChipText; text: (modelData.prs_closed || 0) + " Merged PRs"; font.pixelSize: 10; color: "#c9d1d9" }
                                        }
                                    }

                                    // Commits chip
                                    Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: commitChipText.implicitWidth + 14
                                        radius: 4
                                        color: "#21262d"
                                        border.color: "#30363d"
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "💻"; font.pixelSize: 10 }
                                            Text { id: commitChipText; text: (modelData.commits_count || 0) + " Commits"; font.pixelSize: 10; color: "#c9d1d9" }
                                        }
                                    }

                                    // Tasks chip
                                    Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: taskChipText.implicitWidth + 14
                                        radius: 4
                                        color: "#21262d"
                                        border.color: "#30363d"
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "✅"; font.pixelSize: 10 }
                                            Text { id: taskChipText; text: (modelData.tasks_completed || 0) + " Tasks Done"; font.pixelSize: 10; color: "#c9d1d9" }
                                        }
                                    }

                                    // Reviews chip
                                    Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: revChipText.implicitWidth + 14
                                        radius: 4
                                        color: "#21262d"
                                        border.color: "#30363d"
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text { text: "👁️"; font.pixelSize: 10 }
                                            Text { id: revChipText; text: (modelData.prs_reviewed || 0) + " Reviews"; font.pixelSize: 10; color: "#c9d1d9" }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Badges preview icons
                                    Row {
                                        spacing: 3
                                        Repeater {
                                            model: (modelData.badges || []).slice(0, 4)
                                            Text {
                                                text: modelData.icon || "🏅"
                                                font.pixelSize: 13
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: cardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectUser(modelData)
                            }
                        }
                    }

                    Item { height: 16 }
                }
            }
        }

        // ==========================================
        // Right Area: Selected User Profile Inspector
        // ==========================================
        Rectangle {
            id: inspectorPanel
            visible: root.isInspectorOpen
            Layout.preferredWidth: Math.max(300, Math.min(1200, root.inspectorWidth))
            Layout.fillHeight: true
            color: "#161b22"
            border.color: "#30363d"
            border.width: 1

            // Left edge resizer handle
            Rectangle {
                id: inspDragHandle
                width: 6
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                z: 20
                color: inspDragMa.pressed ? "#58a6ff" : (inspDragMa.containsMouse ? Qt.rgba(88 / 255, 166 / 255, 255 / 255, 0.3) : "transparent")

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 2
                    height: 24
                    radius: 1
                    color: inspDragMa.containsMouse ? "#58a6ff" : "#30363d"
                }

                MouseArea {
                    id: inspDragMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SizeHorCursor
                    property real startX: 0
                    property real startWidth: 0

                    onPressed: function(mouse) {
                        startX = mouse.x;
                        startWidth = inspectorPanel.width;
                    }

                    onPositionChanged: function(mouse) {
                        if (pressed) {
                            var delta = mouse.x - startX;
                            var newW = Math.max(300, Math.min(1200, startWidth - delta));
                            root.inspectorWidth = newW;
                        }
                    }

                    onReleased: {
                        if (backend && typeof backend.setRightSidebarWidth === "function") {
                            backend.setRightSidebarWidth(Math.round(root.inspectorWidth));
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Inspector Header
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 52
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 8

                        Text {
                            text: "👤 Profile Inspector"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle All Sections (Expand / Collapse All)
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 4
                            color: toggleAllMa.containsMouse ? "#30363d" : "transparent"
                            ToolTip.visible: toggleAllMa.containsMouse
                            ToolTip.text: (root.isAliasesCollapsed && root.isLastActivityCollapsed && root.isTimelineCollapsed && root.isTasksCollapsed && root.isBadgesCollapsed) ? "Expand all sections" : "Collapse all sections"

                            Text {
                                anchors.centerIn: parent
                                text: (root.isAliasesCollapsed && root.isLastActivityCollapsed && root.isTimelineCollapsed && root.isTasksCollapsed && root.isBadgesCollapsed) ? "⊞" : "⊟"
                                font.pixelSize: 14
                                color: "#8b949e"
                            }

                            MouseArea {
                                id: toggleAllMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleAllInspectorGroups()
                            }
                        }

                        // Close Inspector Button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 4
                            color: closeInspMa.containsMouse ? "#30363d" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 12
                                color: "#8b949e"
                            }

                            MouseArea {
                                id: closeInspMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedUser = null
                            }
                        }
                    }
                }

                // Inspector Body ScrollView
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: parent.width
                    clip: true

                    ColumnLayout {
                        width: parent.width - 24
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14

                        Item { height: 4 }

                        // User Hero Card
                        Rectangle {
                            visible: !!root.selectedUser
                            Layout.fillWidth: true
                            implicitHeight: heroCol.implicitHeight + 20
                            radius: 8
                            color: "#0d1117"
                            border.color: (root.selectedUser && root.selectedUser.is_aliased) ? "#a371f7" : "#30363d"

                            ColumnLayout {
                                id: heroCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                RowLayout {
                                    spacing: 12
                                    Rectangle {
                                        width: 52
                                        height: 52
                                        radius: 26
                                        color: (root.selectedUser && root.selectedUser.is_aliased) ? "#21262d" : "#1f6feb"
                                        border.color: (root.selectedUser && root.selectedUser.is_aliased) ? "#a371f7" : "#58a6ff"
                                        border.width: 2

                                        Text {
                                            anchors.centerIn: parent
                                            text: (root.selectedUser && root.selectedUser.initials) ? root.selectedUser.initials : "??"
                                            font.pixelSize: 18
                                            font.weight: Font.Bold
                                            color: "#ffffff"
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: (root.selectedUser && root.selectedUser.name) ? root.selectedUser.name : ""
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 16
                                                font.weight: Font.Bold
                                                color: "#ffffff"
                                            }

                                            Rectangle {
                                                visible: !!(root.selectedUser && root.selectedUser.is_aliased)
                                                implicitWidth: heroAliasedTag.implicitWidth + 10
                                                implicitHeight: 18
                                                radius: 9
                                                color: Qt.rgba(163 / 255, 113 / 255, 247 / 255, 0.2)
                                                border.color: "#a371f7"
                                                border.width: 1

                                                Text {
                                                    id: heroAliasedTag
                                                    anchors.centerIn: parent
                                                    text: "🔗 Linked Alias"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: "#d2a8ff"
                                                }
                                            }

                                            Rectangle {
                                                visible: !!(root.selectedUser && root.selectedUser.is_system_user)
                                                implicitWidth: heroSystemUserTag.implicitWidth + 10
                                                implicitHeight: 18
                                                radius: 9
                                                color: Qt.rgba(248 / 255, 81 / 255, 73 / 255, 0.2)
                                                border.color: "#f85149"
                                                border.width: 1

                                                Text {
                                                    id: heroSystemUserTag
                                                    anchors.centerIn: parent
                                                    text: "🤖 System User (Excluded)"
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: "#ff7b72"
                                                }
                                            }
                                        }

                                        Text {
                                            text: (root.selectedUser && root.selectedUser.is_aliased)
                                                ? ("🔗 Linked alias of @" + (root.selectedUser.aliased_to || "primary profile"))
                                                : ((root.selectedUser && root.selectedUser.is_system_user)
                                                    ? "🤖 System / Service Account (Out of scope for Hall of Fame)"
                                                    : ((root.selectedUser && root.selectedUser.time_stats && root.selectedUser.time_stats.persona) ? root.selectedUser.time_stats.persona : "☀️ Team Contributor"))
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            color: (root.selectedUser && root.selectedUser.is_aliased) ? "#a371f7" : ((root.selectedUser && root.selectedUser.is_system_user) ? "#ff7b72" : "#58a6ff")
                                        }

                                        Text {
                                            text: (root.selectedUser && root.selectedUser.is_aliased)
                                                ? "Statistics aggregated into primary profile • Excluded from rankings"
                                                : ((root.selectedUser && root.selectedUser.is_system_user)
                                                    ? "Excluded from MVP rankings, badges, streaks, and motivation stats"
                                                    : ("👑 " + ((root.selectedUser && root.selectedUser.score) ? root.selectedUser.score : 0) + " pts • Rank #" + ((root.selectedUser && root.selectedUser.rank) ? root.selectedUser.rank : "—")))
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: (root.selectedUser && root.selectedUser.is_aliased) ? "#8b949e" : ((root.selectedUser && root.selectedUser.is_system_user) ? "#8b949e" : "#e3b341")
                                        }

                                        // Quick System User Toggle Button
                                        Rectangle {
                                            visible: !!(root.selectedUser && !root.selectedUser.is_aliased)
                                            implicitWidth: toggleSysBtnText.implicitWidth + 20
                                            implicitHeight: 22
                                            radius: 11
                                            color: toggleSysMa.containsMouse ? (root.selectedUser && root.selectedUser.is_system_user ? "#238636" : "#da3633") : (root.selectedUser && root.selectedUser.is_system_user ? Qt.rgba(46/255, 160/255, 67/255, 0.2) : Qt.rgba(248/255, 81/255, 73/255, 0.15))
                                            border.color: root.selectedUser && root.selectedUser.is_system_user ? "#3fb950" : "#f85149"
                                            border.width: 1

                                            Text {
                                                id: toggleSysBtnText
                                                anchors.centerIn: parent
                                                text: (root.selectedUser && root.selectedUser.is_system_user) ? "✅ Include in Hall of Fame" : "🤖 Exclude from Hall of Fame"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: toggleSysMa.containsMouse ? "#ffffff" : ((root.selectedUser && root.selectedUser.is_system_user) ? "#3fb950" : "#ff7b72")
                                            }

                                            MouseArea {
                                                id: toggleSysMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.selectedUser && root.selectedUser.name) {
                                                        backend.toggle_system_user(root.selectedUser.name);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Section 1: Alias Manager (Collapsible)
                        Rectangle {
                            visible: !!root.selectedUser
                            Layout.fillWidth: true
                            implicitHeight: aliasMgrCol.implicitHeight + 20
                            radius: 8
                            color: "#0d1117"
                            border.color: (root.selectedUser && root.selectedUser.is_aliased) ? "#a371f7" : "#30363d"

                            ColumnLayout {
                                id: aliasMgrCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: root.isAliasesCollapsed ? 0 : 10

                                // Section 1 Header (Clickable)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    color: aliasHdrMa.containsMouse ? "#161b22" : "transparent"
                                    radius: 4

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 6

                                        Text {
                                            text: root.isAliasesCollapsed ? "▶" : "▼"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }

                                        Text {
                                            text: (root.selectedUser && root.selectedUser.is_aliased) ? "🔗 Linked Profile Status" : "🔗 Configured Aliases"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: (root.selectedUser && root.selectedUser.is_aliased) ? "#d2a8ff" : "#f0f6fc"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: (root.selectedUser && root.selectedUser.is_aliased) ? "Linked" : (((root.selectedUser && root.selectedUser.aliases) ? root.selectedUser.aliases.length : 0) + " mapped")
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: aliasHdrMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.isAliasesCollapsed = !root.isAliasesCollapsed
                                    }
                                }

                                // Section 1 Content Body
                                ColumnLayout {
                                    visible: !root.isAliasesCollapsed
                                    Layout.fillWidth: true
                                    spacing: 10

                                    // Case A: If current profile IS an alias linked to another profile
                                    ColumnLayout {
                                        visible: !!(root.selectedUser && root.selectedUser.is_aliased)
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: aliasedBannerInsideCol.implicitHeight + 16
                                            radius: 6
                                            color: Qt.rgba(163 / 255, 113 / 255, 247 / 255, 0.1)
                                            border.color: "#a371f7"
                                            border.width: 1

                                            ColumnLayout {
                                                id: aliasedBannerInsideCol
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 8

                                                Text {
                                                    text: "This profile is configured as an alias for " + (root.selectedUser ? root.selectedUser.aliased_to : "") + ". All its git activity, merged PRs, and work items are automatically credited to the primary profile. This profile is greyed out and excluded from individual leaderboard calculations."
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 11
                                                    color: "#c9d1d9"
                                                    wrapMode: Text.Wrap
                                                    Layout.fillWidth: true
                                                }

                                                RowLayout {
                                                    spacing: 8
                                                    Layout.topMargin: 4

                                                    Button {
                                                        text: "👤 Open Primary Profile (" + (root.selectedUser ? root.selectedUser.aliased_to : "") + ")"
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        contentItem: Text {
                                                            text: parent.text
                                                            font: parent.font
                                                            color: "#ffffff"
                                                            horizontalAlignment: Text.AlignHCenter
                                                            verticalAlignment: Text.AlignVCenter
                                                        }
                                                        background: Rectangle {
                                                            implicitHeight: 30
                                                            implicitWidth: 200
                                                            radius: 4
                                                            color: parent.hovered ? "#1f6feb" : "#238636"
                                                        }
                                                        onClicked: {
                                                            if (root.selectedUser && root.selectedUser.aliased_to) {
                                                                var target = root.findUserByName(root.selectedUser.aliased_to);
                                                                if (target) root.selectUser(target);
                                                            }
                                                        }
                                                    }

                                                    Button {
                                                        text: "✕ Unlink Alias"
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        contentItem: Text {
                                                            text: parent.text
                                                            font: parent.font
                                                            color: "#f85149"
                                                            horizontalAlignment: Text.AlignHCenter
                                                            verticalAlignment: Text.AlignVCenter
                                                        }
                                                        background: Rectangle {
                                                            implicitHeight: 30
                                                            implicitWidth: 100
                                                            radius: 4
                                                            color: parent.hovered ? Qt.rgba(248 / 255, 81 / 255, 73 / 255, 0.2) : "#21262d"
                                                            border.color: "#f85149"
                                                            border.width: 1
                                                        }
                                                        onClicked: {
                                                            if (root.selectedUser && root.selectedUser.aliased_to) {
                                                                root.unlinkAliasProfile(root.selectedUser.aliased_to, root.selectedUser.name);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Case B: If current profile IS a primary canonical profile
                                    ColumnLayout {
                                        visible: !root.selectedUser || !root.selectedUser.is_aliased
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "Commits, PRs, and tickets from mapped aliases and linked user profiles are merged into this profile."
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }

                                        // List of configured aliases with unlink button
                                        Repeater {
                                            model: (root.selectedUser && root.selectedUser.aliases) ? root.selectedUser.aliases : []

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 28
                                                radius: 4
                                                color: "#161b22"
                                                border.color: "#30363d"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 6

                                                    Text { text: "🏷️"; font.pixelSize: 10 }
                                                    Text {
                                                        text: "@" + modelData
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: "#a371f7"
                                                        Layout.fillWidth: true
                                                    }

                                                    Text {
                                                        text: "✕ Remove"
                                                        font.pixelSize: 10
                                                        color: "#f85149"
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: root.removeAliasFromSelectedUser(modelData)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Option 1: Dropdown / ComboBox selector for existing user profiles
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Layout.topMargin: 4

                                            Text {
                                                text: "Link User Profile as Alias:"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                color: "#c9d1d9"
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                ComboBox {
                                                    id: profilePickerCombo
                                                    Layout.fillWidth: true
                                                    implicitHeight: 32
                                                    model: ["— Select profile to link as alias —"].concat(root.candidateProfiles)
                                                    currentIndex: 0

                                                    contentItem: Text {
                                                        leftPadding: 10
                                                        rightPadding: 10
                                                        text: profilePickerCombo.displayText
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        color: profilePickerCombo.currentIndex === 0 ? "#8b949e" : "#58a6ff"
                                                        verticalAlignment: Text.AlignVCenter
                                                        elide: Text.ElideRight
                                                    }

                                                    background: Rectangle {
                                                        implicitHeight: 32
                                                        radius: 4
                                                        color: "#161b22"
                                                        border.color: profilePickerCombo.activeFocus ? "#58a6ff" : "#30363d"
                                                        border.width: 1
                                                    }

                                                    popup: Popup {
                                                        y: profilePickerCombo.height + 2
                                                        width: profilePickerCombo.width
                                                        implicitHeight: Math.min(contentItem.implicitHeight + 8, 200)
                                                        padding: 4
                                                        contentItem: ListView {
                                                            clip: true
                                                            implicitHeight: contentHeight
                                                            model: profilePickerCombo.popup.visible ? profilePickerCombo.delegateModel : null
                                                            currentIndex: profilePickerCombo.highlightedIndex
                                                            ScrollIndicator.vertical: ScrollIndicator { }
                                                        }
                                                        background: Rectangle {
                                                            color: "#161b22"
                                                            border.color: "#30363d"
                                                            radius: 6
                                                        }
                                                    }

                                                    delegate: ItemDelegate {
                                                        width: profilePickerCombo.width - 8
                                                        implicitHeight: 28
                                                        highlighted: profilePickerCombo.highlightedIndex === index
                                                        contentItem: Text {
                                                            text: modelData
                                                            color: highlighted ? "#58a6ff" : (index === 0 ? "#8b949e" : "#c9d1d9")
                                                            font.family: "Segoe UI, sans-serif"
                                                            font.pixelSize: 11
                                                            verticalAlignment: Text.AlignVCenter
                                                        }
                                                        background: Rectangle {
                                                            color: highlighted ? "#21262d" : "transparent"
                                                            radius: 4
                                                        }
                                                    }
                                                }

                                                Button {
                                                    text: "+ Link Profile"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    enabled: profilePickerCombo.currentIndex > 0
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: parent.enabled ? "#ffffff" : "#6e7681"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 32
                                                        implicitWidth: 96
                                                        radius: 4
                                                        color: !parent.enabled ? "#21262d" : (parent.hovered ? "#2ea043" : "#238636")
                                                    }
                                                    onClicked: {
                                                        if (profilePickerCombo.currentIndex > 0) {
                                                            var chosen = profilePickerCombo.currentText;
                                                            root.addAliasToSelectedUser(chosen);
                                                            profilePickerCombo.currentIndex = 0;
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Option 2: Custom Text / Git Handle Alias Input
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Layout.topMargin: 4

                                            Text {
                                                text: "Or enter custom git handle / email alias:"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#8b949e"
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 30
                                                    radius: 4
                                                    color: "#161b22"
                                                    border.color: addAliasInputBox.activeFocus ? "#58a6ff" : "#30363d"

                                                    TextInput {
                                                        id: addAliasInputBox
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        text: root.newAliasInput
                                                        color: "#c9d1d9"
                                                        font.pixelSize: 11
                                                        onTextChanged: root.newAliasInput = text
                                                        onAccepted: {
                                                            root.addAliasToSelectedUser(text);
                                                        }

                                                        Text {
                                                            text: "Enter custom handle (e.g. asmith, alex@corp.com)..."
                                                            font.pixelSize: 11
                                                            color: "#6e7681"
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            visible: !addAliasInputBox.text && !addAliasInputBox.activeFocus
                                                        }
                                                    }
                                                }

                                                Button {
                                                    text: "+ Add Alias"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    enabled: !!(root.newAliasInput && root.newAliasInput.trim())
                                                    contentItem: Text {
                                                        text: parent.text
                                                        font: parent.font
                                                        color: parent.enabled ? "#ffffff" : "#6e7681"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    background: Rectangle {
                                                        implicitHeight: 30
                                                        implicitWidth: 80
                                                        radius: 4
                                                        color: !parent.enabled ? "#21262d" : (parent.hovered ? "#388bfd" : "#1f6feb")
                                                    }
                                                    onClicked: root.addAliasToSelectedUser(root.newAliasInput)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Section 2: Last Activity Spotlight (Collapsible)
                        Rectangle {
                            visible: !!(root.selectedUser && root.selectedUser.last_activity)
                            Layout.fillWidth: true
                            implicitHeight: lastActCol.implicitHeight + 20
                            radius: 8
                            color: "#0d1117"
                            border.color: "#1f6feb"
                            border.width: 1

                            ColumnLayout {
                                id: lastActCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: root.isLastActivityCollapsed ? 0 : 6

                                // Section 2 Header (Clickable)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    color: lastActHdrMa.containsMouse ? "#161b22" : "transparent"
                                    radius: 4

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 6

                                        Text {
                                            text: root.isLastActivityCollapsed ? "▶" : "▼"
                                            font.pixelSize: 10
                                            color: "#58a6ff"
                                        }

                                        Text { text: "⏱️"; font.pixelSize: 12 }

                                        Text {
                                            text: "LATEST ACTIVITY TRACKED"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: (root.selectedUser && root.selectedUser.last_activity) ? root.selectedUser.last_activity.relative : ""
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: "#79c0ff"
                                        }
                                    }

                                    MouseArea {
                                        id: lastActHdrMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.isLastActivityCollapsed = !root.isLastActivityCollapsed
                                    }
                                }

                                // Section 2 Body
                                RowLayout {
                                    visible: !root.isLastActivityCollapsed
                                    spacing: 8
                                    Layout.fillWidth: true

                                    Text {
                                        text: (root.selectedUser && root.selectedUser.last_activity && root.selectedUser.last_activity.icon) ? root.selectedUser.last_activity.icon : "📌"
                                        font.pixelSize: 16
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            text: (root.selectedUser && root.selectedUser.last_activity) ? root.selectedUser.last_activity.title : ""
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#f0f6fc"
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: "Timestamp: " + ((root.selectedUser && root.selectedUser.last_activity) ? root.selectedUser.last_activity.timestamp : "") + ((root.selectedUser && root.selectedUser.last_activity && root.selectedUser.last_activity.repo_or_id) ? " • " + root.selectedUser.last_activity.repo_or_id : "")
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }
                                }
                            }
                        }

                        // Section 3: Activity Timeline History (Collapsible)
                        Rectangle {
                            visible: !!root.selectedUser
                            Layout.fillWidth: true
                            implicitHeight: actStreamCol.implicitHeight + 20
                            radius: 8
                            color: "#0d1117"
                            border.color: "#30363d"

                            ColumnLayout {
                                id: actStreamCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: root.isTimelineCollapsed ? 0 : 8

                                // Section 3 Header (Clickable)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    color: timelineHdrMa.containsMouse ? "#161b22" : "transparent"
                                    radius: 4

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 6

                                        Text {
                                            text: root.isTimelineCollapsed ? "▶" : "▼"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }

                                        Text {
                                            text: "📜 Recent Activity Timeline"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#f0f6fc"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: ((root.selectedUser && root.selectedUser.recent_activities) ? root.selectedUser.recent_activities.length : 0) + " events"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: timelineHdrMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.isTimelineCollapsed = !root.isTimelineCollapsed
                                    }
                                }

                                // Section 3 Body
                                ColumnLayout {
                                    visible: !root.isTimelineCollapsed
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: (root.selectedUser && root.selectedUser.recent_activities) ? root.selectedUser.recent_activities : []

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: actEntryCol.implicitHeight + 12
                                            radius: 4
                                            color: "#161b22"
                                            border.color: "#21262d"

                                            ColumnLayout {
                                                id: actEntryCol
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 2

                                                RowLayout {
                                                    spacing: 6
                                                    Text { text: modelData.icon || "📌"; font.pixelSize: 11 }
                                                    Text {
                                                        text: modelData.title
                                                        font.family: "Segoe UI, sans-serif"
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        color: "#c9d1d9"
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                    Text {
                                                        text: modelData.relative
                                                        font.pixelSize: 9
                                                        color: "#58a6ff"
                                                    }
                                                }

                                                Text {
                                                    text: modelData.timestamp + (modelData.repo_or_id ? " • " + modelData.repo_or_id : "")
                                                    font.pixelSize: 9
                                                    color: "#6e7681"
                                                    anchors.leftMargin: 18
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Section 4: Assigned Work Items (Collapsible)
                        Rectangle {
                            visible: !!(root.selectedUser && root.selectedUser.assigned_work_items && root.selectedUser.assigned_work_items.length > 0)
                            Layout.fillWidth: true
                            implicitHeight: wiCol.implicitHeight + 20
                            radius: 8
                            color: "#0d1117"
                            border.color: "#30363d"

                            ColumnLayout {
                                id: wiCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: root.isTasksCollapsed ? 0 : 8

                                // Section 4 Header (Clickable)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    color: tasksHdrMa.containsMouse ? "#161b22" : "transparent"
                                    radius: 4

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 6

                                        Text {
                                            text: root.isTasksCollapsed ? "▶" : "▼"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }

                                        Text {
                                            text: "📋 Active Assigned Tasks"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#f0f6fc"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: ((root.selectedUser && root.selectedUser.assigned_work_items) ? root.selectedUser.assigned_work_items.length : 0) + " tasks"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: tasksHdrMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.isTasksCollapsed = !root.isTasksCollapsed
                                    }
                                }

                                // Section 4 Body
                                ColumnLayout {
                                    visible: !root.isTasksCollapsed
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: (root.selectedUser && root.selectedUser.assigned_work_items) ? root.selectedUser.assigned_work_items : []

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 30
                                            radius: 4
                                            color: "#161b22"
                                            border.color: "#21262d"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 6

                                                Text {
                                                    text: "#" + modelData.id
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: "#58a6ff"
                                                }

                                                Text {
                                                    text: modelData.title
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 10
                                                    color: "#c9d1d9"
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: modelData.state
                                                    font.pixelSize: 9
                                                    color: "#3fb950"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Section 5: Badges Showcase (Collapsible)
                        Rectangle {
                            visible: !!(root.selectedUser && root.selectedUser.badges && root.selectedUser.badges.length > 0)
                            Layout.fillWidth: true
                            implicitHeight: badgesCol.implicitHeight + 20
                            radius: 8
                            color: "#0d1117"
                            border.color: "#30363d"

                            ColumnLayout {
                                id: badgesCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: root.isBadgesCollapsed ? 0 : 8

                                // Section 5 Header (Clickable)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    color: badgesHdrMa.containsMouse ? "#161b22" : "transparent"
                                    radius: 4

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 6

                                        Text {
                                            text: root.isBadgesCollapsed ? "▶" : "▼"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }

                                        Text {
                                            text: "🏅 Earned Badges"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#f0f6fc"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: ((root.selectedUser && root.selectedUser.badges) ? root.selectedUser.badges.length : 0) + " badges"
                                            font.pixelSize: 10
                                            color: "#8b949e"
                                        }
                                    }

                                    MouseArea {
                                        id: badgesHdrMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.isBadgesCollapsed = !root.isBadgesCollapsed
                                    }
                                }

                                // Section 5 Body
                                Flow {
                                    visible: !root.isBadgesCollapsed
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: (root.selectedUser && root.selectedUser.badges) ? root.selectedUser.badges : []

                                        Rectangle {
                                            implicitWidth: bText.implicitWidth + 14
                                            implicitHeight: 24
                                            radius: 4
                                            color: Qt.rgba(227 / 255, 179 / 255, 65 / 255, 0.1)
                                            border.color: "#d29922"

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text { text: modelData.icon || "🏅"; font.pixelSize: 10 }
                                                Text { id: bText; text: modelData.name || ""; font.pixelSize: 10; color: "#f0f6fc" }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item { height: 16 }
                    }
                }
            }
        }
    }

    // ==========================================
    // Auto-Detect Aliases Modal Dialog
    // ==========================================
    Dialog {
        id: autoDetectDialog
        visible: root.isAutoDetectOpen
        title: "⚡ Auto-Detected User Alias Suggestions"
        modal: true
        anchors.centerIn: parent
        width: Math.min(640, root.width - 40)
        height: Math.min(500, root.height - 40)
        standardButtons: Dialog.Close
        onClosed: root.isAutoDetectOpen = false

        background: Rectangle {
            color: "#161b22"
            border.color: "#30363d"
            radius: 8
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "The engine scanned Git commits and TFS history to identify unlinked usernames, commit authors, and email aliases matching your team members."
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                color: "#8b949e"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Rectangle {
                visible: !root.autoDetectSuggestions || root.autoDetectSuggestions.length === 0
                Layout.fillWidth: true
                implicitHeight: 120
                radius: 6
                color: "#0d1117"
                border.color: "#30363d"
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "✓"; font.pixelSize: 24; color: "#3fb950"; Layout.alignment: Qt.AlignHCenter }
                    Text { text: "All Git commit authors and user aliases are currently mapped!"; font.pixelSize: 12; color: "#c9d1d9"; Layout.alignment: Qt.AlignHCenter }
                }
            }

            ScrollView {
                visible: !!(root.autoDetectSuggestions && root.autoDetectSuggestions.length > 0)
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width - 16
                    spacing: 8

                    Repeater {
                        model: root.autoDetectSuggestions

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: sugCol.implicitHeight + 16
                            radius: 6
                            color: "#0d1117"
                            border.color: modelData.confidence === "high" ? "#238636" : "#30363d"
                            border.width: 1

                            ColumnLayout {
                                id: sugCol
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                RowLayout {
                                    spacing: 8
                                    Text { text: "👤"; font.pixelSize: 14 }
                                    Text {
                                        text: modelData.canonical
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                    Text { text: "←"; font.pixelSize: 12; color: "#8b949e" }
                                    Rectangle {
                                        implicitHeight: 20
                                        implicitWidth: sugAliasText.implicitWidth + 10
                                        radius: 4
                                        color: Qt.rgba(163 / 255, 113 / 255, 247 / 255, 0.2)
                                        border.color: "#a371f7"
                                        Text {
                                            id: sugAliasText
                                            anchors.centerIn: parent
                                            text: "@" + modelData.alias
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#d2a8ff"
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Button {
                                        text: "✓ Accept & Link"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: "#ffffff"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 26
                                            implicitWidth: 110
                                            radius: 4
                                            color: parent.hovered ? "#2ea043" : "#238636"
                                        }
                                        onClicked: root.acceptSuggestion(modelData.canonical, modelData.alias)
                                    }
                                }

                                Text {
                                    text: "Reason: " + modelData.reason + " • " + modelData.activity_count + " events (" + modelData.source + ")"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // Manual Add Alias Mapping Dialog
    // ==========================================
    Dialog {
        id: addAliasDialog
        visible: root.isAddAliasModalOpen
        title: "➕ Link User Alias"
        modal: true
        anchors.centerIn: parent
        width: 440
        standardButtons: Dialog.Ok | Dialog.Cancel
        onClosed: root.isAddAliasModalOpen = false
        onAccepted: {
            if (root.manualCanonInput.trim() && root.manualAliasInput.trim()) {
                if (backend && typeof backend.add_user_alias === "function") {
                    backend.add_user_alias(root.manualCanonInput.trim(), root.manualAliasInput.trim());
                }
                root.manualCanonInput = "";
                root.manualAliasInput = "";
            }
        }

        background: Rectangle {
            color: "#161b22"
            border.color: "#30363d"
            radius: 8
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "Map an alternative git username or email address to a primary team member name."
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                color: "#8b949e"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            ColumnLayout {
                spacing: 4
                Text { text: "Canonical Team Member Name:"; font.pixelSize: 11; font.weight: Font.Bold; color: "#c9d1d9" }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 4
                    color: "#0d1117"
                    border.color: "#30363d"
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 6
                        text: root.manualCanonInput
                        color: "#f0f6fc"
                        font.pixelSize: 12
                        onTextChanged: root.manualCanonInput = text
                    }
                }
            }

            ColumnLayout {
                spacing: 4
                Text { text: "Alias to map (e.g. git commit author name or email):"; font.pixelSize: 11; font.weight: Font.Bold; color: "#c9d1d9" }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 4
                    color: "#0d1117"
                    border.color: "#30363d"
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 6
                        text: root.manualAliasInput
                        color: "#f0f6fc"
                        font.pixelSize: 12
                        onTextChanged: root.manualAliasInput = text
                    }
                }
            }
        }
    }
}
