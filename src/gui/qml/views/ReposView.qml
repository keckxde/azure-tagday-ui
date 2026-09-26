import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components"

Item {
    id: root
    property string searchQuery: ""
    property string selectedCategory: (pendingPrsCount > 0) ? "🏷️ PENDING PRs" : (unmergedBranchesCount > 0 ? "🌿 UNMERGED BRANCHES" : "ALL")
    property int currentPage: 1
    property int pageSize: 15
    property int totalPages: 1
    property int totalMatchingCount: 0
    property int contentMargins: 20

    readonly property int pendingPrsCount: {
        if (!backend || !backend.repositories)
            return 0;
        var count = 0;
        var list = backend.repositories;
        for (var i = 0; i < list.length; i++) {
            if (list[i].has_untagged_prs || (list[i].prs_after_tag_count && list[i].prs_after_tag_count > 0))
                count++;
        }
        return count;
    }

    readonly property int unmergedBranchesCount: {
        if (!backend || !backend.repositories)
            return 0;
        var count = 0;
        var list = backend.repositories;
        for (var i = 0; i < list.length; i++) {
            if (list[i].has_unmerged_branches || (list[i].unmerged_branches_count && list[i].unmerged_branches_count > 0))
                count++;
        }
        return count;
    }

    readonly property int pendingCount: {
        if (!backend || !backend.repositories)
            return 0;
        var count = 0;
        var list = backend.repositories;
        for (var i = 0; i < list.length; i++) {
            if (list[i].has_pending_changes)
                count++;
        }
        return count;
    }

    function validateSelectedCategory() {
        if (selectedCategory === "🏷️ PENDING PRs" && root.pendingPrsCount === 0) {
            selectedCategory = (root.unmergedBranchesCount > 0) ? "🌿 UNMERGED BRANCHES" : "ALL";
        } else if (selectedCategory === "🌿 UNMERGED BRANCHES" && root.unmergedBranchesCount === 0) {
            selectedCategory = (root.pendingPrsCount > 0) ? "🏷️ PENDING PRs" : "ALL";
        } else if (selectedCategory === "⚠️ PENDING" && root.pendingCount === 0) {
            selectedCategory = "ALL";
        }
    }

    onPendingPrsCountChanged: validateSelectedCategory()
    onUnmergedBranchesCountChanged: validateSelectedCategory()
    onPendingCountChanged: validateSelectedCategory()

    // Shared Column Widths for pixel-perfect alignment across Header and Rows
    readonly property int colRepoWidth: 240
    readonly property int colStableWidth: 140
    readonly property int colUnstableWidth: 140
    readonly property int colBranchWidth: 120

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: root.contentMargins
        spacing: 16

        // Top Toolbar Actions Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "Repositories"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 18
                font.weight: Font.Bold
                color: "#f0f6fc"
            }

            Text {
                text: {
                    var extra = [];
                    if (root.pendingPrsCount > 0) extra.push(root.pendingPrsCount + " untagged PRs");
                    if (root.unmergedBranchesCount > 0) extra.push(root.unmergedBranchesCount + " unmerged branches");
                    return "(" + root.totalMatchingCount + " repos" + (extra.length > 0 ? " • " + extra.join(" • ") : "") + ")";
                }
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 13
                color: (root.pendingPrsCount > 0 || root.unmergedBranchesCount > 0) ? "#f0883e" : "#8b949e"
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                text: "🏷️ Category Settings"
                font.pixelSize: 11
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#bc8cff"
                }
                background: Rectangle {
                    implicitHeight: 32
                    implicitWidth: 145
                    radius: 6
                    color: parent.hovered ? "#21262d" : "#161b22"
                    border.color: "#30363d"
                }
                onClicked: repoCategoriesDialog.openDialog()
            }

            Button {
                text: "📑 Open TAGDAY.md"
                font.pixelSize: 11
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#58a6ff"
                }
                background: Rectangle {
                    implicitHeight: 32
                    implicitWidth: 140
                    radius: 6
                    color: parent.hovered ? "#21262d" : "#161b22"
                    border.color: "#30363d"
                }
                onClicked: {
                    if (backend)
                        backend.open_tagday_markdown_report();
                }
            }

            SearchBar {
                placeholder: "Filter repositories..."
                onSearchUpdated: function (query) {
                    root.searchQuery = query;
                }
            }

            Button {
                text: "↻ Refresh"
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#f0f6fc"
                }
                background: Rectangle {
                    implicitHeight: 32
                    implicitWidth: 80
                    radius: 6
                    color: parent.hovered ? "#30363d" : "#21262d"
                    border.color: "#30363d"
                }
                onClicked: backend.refresh_all_data()
            }
        }

        // Category & Pending Filter Bar with Full Width Wrapping
        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: parent ? parent.width : root.width
            implicitHeight: catFlow.implicitHeight

            Flow {
                id: catFlow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                Repeater {
                    model: {
                        var base = [];
                        if (root.pendingPrsCount > 0) {
                            base.push("🏷️ PENDING PRs");
                        }
                        if (root.unmergedBranchesCount > 0) {
                            base.push("🌿 UNMERGED BRANCHES");
                        }
                        if (root.pendingCount > 0 && root.pendingPrsCount === 0 && root.unmergedBranchesCount === 0) {
                            base.push("⚠️ PENDING");
                        }
                        base.push("ALL");
                        if (backend && backend.repoCategories) {
                            for (var i = 0; i < backend.repoCategories.length; i++) {
                                base.push(backend.repoCategories[i].name);
                            }
                        } else {
                            base.push("GENERIC", "3RDPARTY", "OTHERS");
                        }
                        return base;
                    }
                    Button {
                        text: {
                            if (modelData === "🏷️ PENDING PRs")
                                return "🏷️ PENDING PRs (" + root.pendingPrsCount + ")";
                            if (modelData === "🌿 UNMERGED BRANCHES")
                                return "🌿 UNMERGED BRANCHES (" + root.unmergedBranchesCount + ")";
                            if (modelData === "⚠️ PENDING")
                                return "⚠️ ALL PENDING (" + root.pendingCount + ")";
                            return modelData;
                        }
                        checkable: true
                        checked: root.selectedCategory === modelData
                        font.pixelSize: 11
                        font.weight: checked ? Font.DemiBold : Font.Normal
                        leftPadding: 14
                        rightPadding: 14
                        topPadding: 4
                        bottomPadding: 4
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: {
                                if (parent.checked) return "#ffffff";
                                if (modelData === "🏷️ PENDING PRs") return "#f0883e";
                                if (modelData === "🌿 UNMERGED BRANCHES") return "#bc8cff";
                                if (modelData === "⚠️ PENDING") return "#f0883e";
                                return "#8b949e";
                            }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 28
                            radius: 14
                            color: {
                                if (parent.checked) {
                                    if (modelData === "🏷️ PENDING PRs") return "#d29922";
                                    if (modelData === "🌿 UNMERGED BRANCHES") return "#8957e5";
                                    if (modelData === "⚠️ PENDING") return "#d29922";
                                    return (backend ? backend.get_category_color(modelData) : "#1f6feb");
                                }
                                return parent.hovered ? "#21262d" : "#161b22";
                            }
                            border.color: {
                                if (parent.checked) {
                                    if (modelData === "🏷️ PENDING PRs") return "#e3b341";
                                    if (modelData === "🌿 UNMERGED BRANCHES") return "#a371f7";
                                    if (modelData === "⚠️ PENDING") return "#e3b341";
                                    return "#388bfd";
                                }
                                if (modelData === "🏷️ PENDING PRs") return "#6e4b10";
                                if (modelData === "🌿 UNMERGED BRANCHES") return "#5a3e85";
                                if (modelData === "⚠️ PENDING") return "#6e4b10";
                                return "#30363d";
                            }
                        }
                        onClicked: root.selectedCategory = modelData
                    }
                }
            }
        }

        // Table Header
        Rectangle {
            Layout.fillWidth: true
            height: 38
            color: "#161b22"
            radius: 6
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14 + (repoVBar.visible ? repoVBar.width + 4 : 0)
                spacing: 12

                Text {
                    text: "REPOSITORY"
                    Layout.preferredWidth: root.colRepoWidth
                    Layout.minimumWidth: root.colRepoWidth
                    Layout.maximumWidth: root.colRepoWidth
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }
                Text {
                    text: "STABLE TAG"
                    Layout.preferredWidth: root.colStableWidth
                    Layout.minimumWidth: root.colStableWidth
                    Layout.maximumWidth: root.colStableWidth
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }
                Text {
                    text: "UNSTABLE TAG"
                    Layout.preferredWidth: root.colUnstableWidth
                    Layout.minimumWidth: root.colUnstableWidth
                    Layout.maximumWidth: root.colUnstableWidth
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }
                Text {
                    text: "PENDING CHANGES"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 200
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }
                Text {
                    text: "BRANCH"
                    Layout.preferredWidth: root.colBranchWidth
                    Layout.minimumWidth: root.colBranchWidth
                    Layout.maximumWidth: root.colBranchWidth
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#8b949e"
                }
                Item {
                    Layout.preferredWidth: 24
                } // Spacer matching jump chevron
            }
        }

        // Repositories List
        ListView {
            id: repoListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4

            model: ListModel {
                id: filteredRepos
            }

            ScrollBar.vertical: ScrollBar {
                id: repoVBar
                active: true
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: repoVBar.pressed ? "#58a6ff" : (repoVBar.hovered ? "#8b949e" : "#30363d")
                }
                background: Rectangle {
                    implicitWidth: 6
                    color: "transparent"
                }
            }

            delegate: Rectangle {
                id: rowRect
                width: repoListView.width - (repoVBar.visible ? repoVBar.width + 4 : 0)
                height: 52
                color: itemMouse.containsMouse ? "#1c2128" : "#0d1117"
                radius: 6
                border.color: itemMouse.containsMouse ? (model.has_pending_changes ? "#d29922" : "#388bfd") : "#21262d"
                border.width: 1

                // Left pending indicator bar
                Rectangle {
                    width: 3
                    height: parent.height - 12
                    anchors.left: parent.left
                    anchors.leftMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 1.5
                    color: (model.prs_after_tag_count > 0) ? "#f0883e" : "#bc8cff"
                    visible: !!model.has_pending_changes
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    // 1. Repository Name & Category
                    ColumnLayout {
                        Layout.preferredWidth: root.colRepoWidth
                        spacing: 3

                        Text {
                            text: model.name
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Row {
                            spacing: 6
                            StatusBadge {
                                text: model.category || "OTHERS"
                                badgeColor: backend ? backend.get_category_color(model.category || "OTHERS") : "#6e7681"

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: repoCategoriesDialog.openDialog()
                                }
                            }
                        }
                    }

                    // 2. Stable Tag
                    Item {
                        Layout.preferredWidth: root.colStableWidth
                        height: parent.height

                        Rectangle {
                            visible: !!(model.stable_tag && model.stable_tag !== "-")
                            anchors.verticalCenter: parent.verticalCenter
                            height: 24
                            width: Math.min(parent.width, stableRow.implicitWidth + 14)
                            radius: 4
                            color: "#13231b"
                            border.color: "#238636"
                            border.width: 1

                            Row {
                                id: stableRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: "🛡️"
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    id: stableText
                                    text: model.stable_tag || "-"
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#3fb950"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        Text {
                            visible: !model.stable_tag || model.stable_tag === "-"
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            text: "-"
                            font.family: "Consolas, monospace"
                            font.pixelSize: 12
                            color: "#484f58"
                        }
                    }

                    // 3. Unstable Tag
                    Item {
                        Layout.preferredWidth: root.colUnstableWidth
                        height: parent.height

                        Rectangle {
                            visible: !!(model.unstable_tag && model.unstable_tag !== "-")
                            anchors.verticalCenter: parent.verticalCenter
                            height: 24
                            width: Math.min(parent.width, unstableRow.implicitWidth + 14)
                            radius: 4
                            color: "#142233"
                            border.color: "#388bfd"
                            border.width: 1

                            Row {
                                id: unstableRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: "⚡"
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    id: unstableText
                                    text: model.unstable_tag || "-"
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#79c0ff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        Text {
                            visible: !model.unstable_tag || model.unstable_tag === "-"
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            text: "-"
                            font.family: "Consolas, monospace"
                            font.pixelSize: 12
                            color: "#484f58"
                        }
                    }

                    // 4. Pending Changes Information (Separated Untagged PRs and Unmerged Branches)
                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 200
                        height: parent.height

                        RowLayout {
                            visible: !!model.has_pending_changes
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 6

                            // Badge 1: Untagged PRs
                            Rectangle {
                                visible: !!(model.prs_after_tag_count > 0)
                                height: 26
                                radius: 4
                                color: "#281b0f"
                                border.color: "#d29922"
                                border.width: 1
                                implicitWidth: prRow.implicitWidth + 16

                                Row {
                                    id: prRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "🏷️"
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: model.prs_after_tag_count + " untagged PR" + (model.prs_after_tag_count > 1 ? "s" : "")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#f0883e"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            // Badge 2: Unmerged Branches
                            Rectangle {
                                visible: !!(model.unmerged_branches_count > 0)
                                height: 26
                                radius: 4
                                color: "#1e172a"
                                border.color: "#8957e5"
                                border.width: 1
                                implicitWidth: brRow.implicitWidth + 16

                                Row {
                                    id: brRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "🌿"
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: model.unmerged_branches_count + " branch" + (model.unmerged_branches_count > 1 ? "es" : "") + " ahead"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#bc8cff"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            // Badge 3: Active PRs (if any)
                            Rectangle {
                                visible: !!(model.active_prs_count > 0)
                                height: 26
                                radius: 4
                                color: "#142233"
                                border.color: "#388bfd"
                                border.width: 1
                                implicitWidth: actRow.implicitWidth + 16

                                Row {
                                    id: actRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "🔀"
                                        font.pixelSize: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: model.active_prs_count + " active PR" + (model.active_prs_count > 1 ? "s" : "")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#79c0ff"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        // Clean badge when up to date
                        Row {
                            visible: !model.has_pending_changes
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                text: "✓"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#238636"
                            }
                            Text {
                                text: "Clean / Up to date"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#3fb950"
                            }
                        }
                    }

                    // 5. Default Branch
                    Item {
                        Layout.preferredWidth: root.colBranchWidth
                        Layout.minimumWidth: root.colBranchWidth
                        Layout.maximumWidth: root.colBranchWidth
                        height: parent.height

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: "🌿"
                                font.pixelSize: 10
                            }
                            Text {
                                text: model.default_branch || "main"
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                color: "#8b949e"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // 6. Jump Chevron Indicator
                    Text {
                        text: "➔"
                        font.pixelSize: 13
                        color: model.has_pending_changes ? "#d29922" : "#388bfd"
                        opacity: itemMouse.containsMouse ? 1.0 : 0.4
                        Layout.preferredWidth: 24
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 350
                    ToolTip.text: "Click to open Tag Day details for " + model.name
                    onClicked: {
                        if (typeof window !== "undefined" && window.navigateToTagDayRepo) {
                            window.navigateToTagDayRepo(model.name);
                        }
                    }
                }
            }
        }

        // Pagination Bar
        Rectangle {
            Layout.fillWidth: true
            height: 46
            color: "#161b22"
            radius: 6
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: "Page " + root.currentPage + " of " + Math.max(1, root.totalPages) + " (" + root.totalMatchingCount + " repositories)"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                }

                Item {
                    Layout.fillWidth: true
                }

                // Page size selector
                Row {
                    spacing: 4
                    Text {
                        text: "Rows:"
                        font.pixelSize: 12
                        color: "#8b949e"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        model: [10, 15, 25, 50]
                        Button {
                            text: modelData.toString()
                            checkable: true
                            checked: root.pageSize === modelData
                            font.pixelSize: 11
                            font.weight: checked ? Font.DemiBold : Font.Normal
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: parent.checked ? "#ffffff" : "#8b949e"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 26
                                implicitWidth: 36
                                radius: 4
                                color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                                border.color: parent.checked ? "#388bfd" : "#30363d"
                            }
                            onClicked: {
                                root.pageSize = modelData;
                                root.currentPage = 1;
                                root.updateFilteredModel();
                            }
                        }
                    }
                }

                Item {
                    width: 10
                }

                // First Page
                Button {
                    text: "«"
                    enabled: root.currentPage > 1
                    font.pixelSize: 14
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: parent.enabled ? "#f0f6fc" : "#484f58"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 28
                        implicitWidth: 32
                        radius: 4
                        color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                        border.color: "#30363d"
                    }
                    onClicked: {
                        root.currentPage = 1;
                        root.updateFilteredModel();
                    }
                }

                // Previous Page
                Button {
                    text: "‹ Prev"
                    enabled: root.currentPage > 1
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: parent.enabled ? "#f0f6fc" : "#484f58"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 28
                        implicitWidth: 64
                        radius: 4
                        color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                        border.color: "#30363d"
                    }
                    onClicked: {
                        if (root.currentPage > 1) {
                            root.currentPage--;
                            root.updateFilteredModel();
                        }
                    }
                }

                // Next Page
                Button {
                    text: "Next ›"
                    enabled: root.currentPage < root.totalPages
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: parent.enabled ? "#f0f6fc" : "#484f58"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 28
                        implicitWidth: 64
                        radius: 4
                        color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                        border.color: "#30363d"
                    }
                    onClicked: {
                        if (root.currentPage < root.totalPages) {
                            root.currentPage++;
                            root.updateFilteredModel();
                        }
                    }
                }

                // Last Page
                Button {
                    text: "»"
                    enabled: root.currentPage < root.totalPages
                    font.pixelSize: 14
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: parent.enabled ? "#f0f6fc" : "#484f58"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 28
                        implicitWidth: 32
                        radius: 4
                        color: parent.enabled ? (parent.hovered ? "#30363d" : "#21262d") : "#161b22"
                        border.color: "#30363d"
                    }
                    onClicked: {
                        root.currentPage = root.totalPages;
                        root.updateFilteredModel();
                    }
                }
            }
        }
    }

    function updateFilteredModel() {
        root.validateSelectedCategory();
        filteredRepos.clear();
        if (!backend || !backend.repositories)
            return;
        var list = backend.repositories || [];
        var q = (root.searchQuery || "").toLowerCase();
        var cat = root.selectedCategory;

        var matched = [];
        for (var i = 0; i < list.length; i++) {
            var item = list[i];
            var matchesQuery = !q || item.name.toLowerCase().indexOf(q) !== -1;
            var matchesCategory = false;
            if (cat === "ALL") {
                matchesCategory = true;
            } else if (cat === "🏷️ PENDING PRs" || cat === "PENDING_PRS") {
                matchesCategory = !!item.has_untagged_prs || (item.prs_after_tag_count > 0);
            } else if (cat === "🌿 UNMERGED BRANCHES" || cat === "UNMERGED_BRANCHES") {
                matchesCategory = !!item.has_unmerged_branches || (item.unmerged_branches_count > 0);
            } else if (cat === "⚠️ PENDING" || cat === "PENDING") {
                matchesCategory = !!item.has_pending_changes;
            } else {
                matchesCategory = (item.category === cat);
            }

            if (matchesQuery && matchesCategory) {
                matched.push(item);
            }
        }

        root.totalMatchingCount = matched.length;
        root.totalPages = Math.ceil(matched.length / root.pageSize) || 1;
        if (root.currentPage > root.totalPages) {
            root.currentPage = root.totalPages;
        }
        if (root.currentPage < 1) {
            root.currentPage = 1;
        }

        var startIdx = (root.currentPage - 1) * root.pageSize;
        var endIdx = Math.min(startIdx + root.pageSize, matched.length);

        for (var j = startIdx; j < endIdx; j++) {
            filteredRepos.append(matched[j]);
        }
    }

    Connections {
        target: backend
        function onRepositoriesChanged() {
            root.validateSelectedCategory();
            root.updateFilteredModel();
        }
        function onRepoCategoriesChanged() {
            root.updateFilteredModel();
        }
    }

    onSearchQueryChanged: {
        root.currentPage = 1;
        root.updateFilteredModel();
    }
    onSelectedCategoryChanged: {
        root.currentPage = 1;
        root.updateFilteredModel();
    }
    Component.onCompleted: root.updateFilteredModel()

    RepoCategoriesDialog {
        id: repoCategoriesDialog
    }
}
