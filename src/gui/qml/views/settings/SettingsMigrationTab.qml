import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

ColumnLayout {
    id: migrationTabRoot
    Layout.fillWidth: true
    spacing: 16

    property var submoduleAuditEntries: []
    property var migrationStatusEntries: []
    property string forgejoConnStatusText: ""
    property bool forgejoConnSuccess: false
    property bool showForgejoToken: false

    function refreshMigrationModels() {
        if (!backend) return;
        submoduleAuditEntries = backend.getSubmoduleAuditList() || [];
        migrationStatusEntries = backend.getMigrationStatusList() || [];
    }

    Component.onCompleted: {
        Qt.callLater(refreshMigrationModels);
    }

    Connections {
        target: backend

        function onSubmoduleAuditCompleted(report) {
            migrationTabRoot.refreshMigrationModels();
            if (report) {
                var needsFix = report.needs_conversion_count || 0;
                var totalSubs = report.total_submodules || 0;
                if (needsFix > 0) {
                    root.bannerMsg = "⚠️ Submodule Audit: Found " + needsFix + " non-relative TFS URL(s) across " + (report.repos_needing_conversion || 0) + " repository/repositories.";
                    root.bannerType = "info";
                } else {
                    root.bannerMsg = "✅ Submodule Audit: All " + totalSubs + " submodule URL(s) are already using clean relative paths!";
                    root.bannerType = "success";
                }
            }
        }

        function onSubmoduleConversionCompleted(res) {
            migrationTabRoot.refreshMigrationModels();
            if (res) {
                var updCount = (res.updated_repos || []).length;
                var failCount = (res.failed_repos || []).length;
                if (failCount === 0) {
                    root.bannerMsg = "✅ Converted .gitmodules to relative paths in " + updCount + " repository/repositories.";
                    root.bannerType = "success";
                } else {
                    root.bannerMsg = "⚠️ Updated " + updCount + " repo(s), failed on " + failCount + " repo(s). Check Sync Logs for details.";
                    root.bannerType = "error";
                }
            }
        }

        function onRepositoryBackupCompleted(manifest) {
            migrationTabRoot.refreshMigrationModels();
            if (manifest) {
                var ok = manifest.ok_count || 0;
                var fail = manifest.failed_count || 0;
                if (fail === 0) {
                    root.bannerMsg = "✅ Local Backup (" + (manifest.backup_mode || "both") + ") complete: " + ok + " repositories verified at " + (manifest.target_dir || "");
                    root.bannerType = "success";
                } else {
                    root.bannerMsg = "⚠️ Local Backup finished with " + fail + " error(s) and " + ok + " succeeded.";
                    root.bannerType = "error";
                }
            }
        }

        function onForgejoSyncCompleted(res) {
            migrationTabRoot.refreshMigrationModels();
            if (res) {
                var ok = res.ok_count || 0;
                var fail = res.failed_count || 0;
                if (fail === 0) {
                    root.bannerMsg = "✅ Forgejo Standby Sync complete: " + ok + " repositories synced to Organization '" + (res.org_name || "") + "'.";
                    root.bannerType = "success";
                } else {
                    root.bannerMsg = "⚠️ Forgejo Sync finished with " + fail + " error(s) and " + ok + " succeeded.";
                    root.bannerType = "error";
                }
            }
        }
    }

    // =========================================================================
    // 1. MILESTONE 1: Submodule (.gitmodules) URL Auditor & Relative Converter
    // =========================================================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: subAuditCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: subAuditCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text { text: "🔍"; font.pixelSize: 20 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Submodule URL Check & Relative-Path Conversion (.gitmodules)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Audits .gitmodules across all repositories to detect hardcoded absolute TFS URLs and convert them to portable relative paths (../RepoName) before local cloning or Forgejo migration."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Button {
                    text: "🔍 Check Submodules"
                    enabled: backend ? !backend.isBusy : false
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 165; radius: 6
                        color: parent.hovered ? "#388bfd" : "#1f6feb"
                        border.color: "#58a6ff"; border.width: 1
                    }
                    onClicked: {
                        if (backend) backend.checkSubmodulesAsync("");
                    }
                }

                Button {
                    text: "🛠️ Convert All to Relative"
                    enabled: backend ? (!backend.isBusy && migrationTabRoot.submoduleAuditEntries.length > 0) : false
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 185; radius: 6
                        color: parent.hovered ? "#2ea043" : "#238636"
                        border.color: "#3fb950"; border.width: 1
                    }
                    onClicked: {
                        if (backend) backend.convertSubmodulesToRelativeAsync([], "", false);
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Submodule Audit Entries List
            Text {
                visible: migrationTabRoot.submoduleAuditEntries.length === 0
                text: "No cached submodule audit entries yet. Click '🔍 Check Submodules' to scan all project repositories."
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 11
                color: "#8b949e"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: migrationTabRoot.submoduleAuditEntries.length > 0

                Repeater {
                    model: migrationTabRoot.submoduleAuditEntries

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 6
                        color: "#0d1117"
                        border.color: modelData.classification === "RELATIVE_OK" ? "#238636" : "#d29922"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Text {
                                text: modelData.classification === "RELATIVE_OK" ? "✓" : "⚠️"
                                font.pixelSize: 12
                                color: modelData.classification === "RELATIVE_OK" ? "#3fb950" : "#f0883e"
                            }

                            Text {
                                text: (modelData.parent_repo_name || "") + " ➔ " + (modelData.submodule_path || "")
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: "#f0f6fc"
                            }

                            Text {
                                text: modelData.current_url || ""
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                color: "#8b949e"
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            Text {
                                visible: modelData.classification !== "RELATIVE_OK" && !!modelData.proposed_relative_url
                                text: "➔ " + (modelData.proposed_relative_url || "")
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#58a6ff"
                            }

                            Rectangle {
                                implicitHeight: 20
                                implicitWidth: clsTxt.implicitWidth + 12
                                radius: 10
                                color: modelData.classification === "RELATIVE_OK" ? "#162b20" : "#3d2800"
                                border.color: modelData.classification === "RELATIVE_OK" ? "#238636" : "#d29922"
                                border.width: 1

                                Text {
                                    id: clsTxt
                                    anchors.centerIn: parent
                                    text: modelData.classification || ""
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: modelData.classification === "RELATIVE_OK" ? "#3fb950" : "#f0883e"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 2. PATH 1: Local Repository Backup (Worktree / Bare Mirror / Both Toggle)
    // =========================================================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: path1Col.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: path1Col
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text { text: "💾"; font.pixelSize: 20 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Path 1: Local Repository Backup (Recursive Clones & Bare Mirrors)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Clones and incrementally updates all repositories in topological order (submodules first) with a SQLite database snapshot and backup_manifest.json."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Target Directory Input + Browse
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Target Folder:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#c9d1d9"
                }

                TextField {
                    id: backupDirInput
                    Layout.fillWidth: true
                    implicitHeight: 34
                    font.family: "Consolas, monospace"
                    font.pixelSize: 12
                    text: backend ? backend.backupTargetDir : ""
                    placeholderText: "e.g. D:/TFS_Backup"
                    placeholderTextColor: "#484f58"
                    color: "#f0f6fc"
                    background: Rectangle {
                        color: "#0d1117"; radius: 6
                        border.color: backupDirInput.activeFocus ? "#58a6ff" : "#30363d"; border.width: 1
                    }
                    onEditingFinished: {
                        if (backend) backend.backupTargetDir = backupDirInput.text;
                    }
                }

                Button {
                    text: "📁 Browse..."
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#f0f6fc"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 105; radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: parent.hovered ? "#58a6ff" : "#30363d"; border.width: 1
                    }
                    onClicked: {
                        if (backend) {
                            var chosen = backend.browse_backup_dir();
                            if (chosen) backupDirInput.text = chosen;
                        }
                    }
                }
            }

            // Backup Format Toggle (Worktree | Bare Mirror | Both) + Run Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Backup Format:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#c9d1d9"
                }

                Repeater {
                    model: [
                        { id: "worktree", label: "📁 Worktree (--recurse-submodules)" },
                        { id: "mirror",   label: "🪞 Bare Mirror (--mirror)" },
                        { id: "both",     label: "⚡ Both (Mirror + Worktree)" }
                    ]

                    Rectangle {
                        property bool isCurrentMode: (backend ? backend.backupMode : "both") === modelData.id
                        implicitHeight: 32
                        implicitWidth: modeLabel.implicitWidth + 24
                        radius: 6
                        color: isCurrentMode ? "#16243b" : "#0d1117"
                        border.color: isCurrentMode ? "#58a6ff" : "#30363d"
                        border.width: 1

                        Text {
                            id: modeLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: parent.isCurrentMode ? Font.Bold : Font.Normal
                            color: parent.isCurrentMode ? "#58a6ff" : "#8b949e"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (backend) backend.backupMode = modelData.id;
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "🔄 Run Standby Backup"
                    enabled: backend ? !backend.isBusy : false
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 170; radius: 6
                        color: parent.hovered ? "#2ea043" : "#238636"
                        border.color: "#3fb950"; border.width: 1
                    }
                    onClicked: {
                        if (backend) {
                            backend.backupTargetDir = backupDirInput.text;
                            backend.backupRepositoriesAsync(backupDirInput.text, backend.backupMode, false);
                        }
                    }
                }

                Button {
                    text: "⚡ Force Full Update"
                    enabled: backend ? !backend.isBusy : false
                    font.pixelSize: 12
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 145; radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: "#30363d"; border.width: 1
                    }
                    onClicked: {
                        if (backend) {
                            backend.backupTargetDir = backupDirInput.text;
                            backend.backupRepositoriesAsync(backupDirInput.text, backend.backupMode, true);
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 3. PATH 2: Standby Migration to Local Git Instance (Forgejo)
    // =========================================================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: path2Col.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: path2Col
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text { text: "🚀"; font.pixelSize: 20 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Path 2: Standby Migration to Local Git Instance (Forgejo / Gitea)"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Provisions the target Forgejo Organization and mirrors all Git repositories and submodules so your local instance stays ready as a live standby."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 10
                columnSpacing: 10

                Text { text: "Forgejo URL:"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#c9d1d9" }
                TextField {
                    id: forgejoUrlInput
                    Layout.fillWidth: true
                    implicitHeight: 34
                    font.family: "Consolas, monospace"; font.pixelSize: 12
                    text: backend ? backend.forgejoUrl : ""
                    placeholderText: "http://localhost:3000"
                    placeholderTextColor: "#484f58"; color: "#f0f6fc"
                    background: Rectangle {
                        color: "#0d1117"; radius: 6
                        border.color: forgejoUrlInput.activeFocus ? "#58a6ff" : "#30363d"; border.width: 1
                    }
                    onEditingFinished: if (backend) backend.forgejoUrl = forgejoUrlInput.text
                }

                Text { text: "Target Org:"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#c9d1d9" }
                TextField {
                    id: forgejoOrgInput
                    Layout.fillWidth: true
                    implicitHeight: 34
                    font.family: "Consolas, monospace"; font.pixelSize: 12
                    text: backend ? backend.forgejoOrg : ""
                    placeholderText: "Organization name (defaults to project)"
                    placeholderTextColor: "#484f58"; color: "#f0f6fc"
                    background: Rectangle {
                        color: "#0d1117"; radius: 6
                        border.color: forgejoOrgInput.activeFocus ? "#58a6ff" : "#30363d"; border.width: 1
                    }
                    onEditingFinished: if (backend) backend.forgejoOrg = forgejoOrgInput.text
                }

                Text { text: "API Token:"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#c9d1d9" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField {
                        id: forgejoTokenInput
                        Layout.fillWidth: true
                        implicitHeight: 34
                        echoMode: migrationTabRoot.showForgejoToken ? TextInput.Normal : TextInput.Password
                        font.family: "Consolas, monospace"; font.pixelSize: 12
                        text: backend ? backend.forgejoToken : ""
                        placeholderText: "Forgejo Personal Access Token"
                        placeholderTextColor: "#484f58"; color: "#f0f6fc"
                        background: Rectangle {
                            color: "#0d1117"; radius: 6
                            border.color: forgejoTokenInput.activeFocus ? "#58a6ff" : "#30363d"; border.width: 1
                        }
                        onEditingFinished: if (backend) backend.forgejoToken = forgejoTokenInput.text
                    }
                    Button {
                        text: migrationTabRoot.showForgejoToken ? "🙈" : "👁️"
                        implicitWidth: 34; implicitHeight: 34
                        onClicked: migrationTabRoot.showForgejoToken = !migrationTabRoot.showForgejoToken
                    }
                }

                Text { text: "Sync Strategy:"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#c9d1d9" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [
                            { id: "push",        label: "📤 Push from Local Mirror" },
                            { id: "pull_mirror", label: "🔄 Forgejo Pull-Mirror" }
                        ]
                        Rectangle {
                            property bool isCurrentStrat: (backend ? backend.forgejoStrategy : "push") === modelData.id
                            implicitHeight: 32
                            implicitWidth: stratTxt.implicitWidth + 20
                            radius: 6
                            color: isCurrentStrat ? "#16243b" : "#0d1117"
                            border.color: isCurrentStrat ? "#58a6ff" : "#30363d"
                            border.width: 1
                            Text {
                                id: stratTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 11
                                font.weight: parent.isCurrentStrat ? Font.Bold : Font.Normal
                                color: parent.isCurrentStrat ? "#58a6ff" : "#8b949e"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (backend) backend.forgejoStrategy = modelData.id
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    text: "🔌 Test Forgejo Connection"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#f0f6fc"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 190; radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: parent.hovered ? "#58a6ff" : "#30363d"; border.width: 1
                    }
                    onClicked: {
                        if (!backend) return;
                        backend.forgejoUrl = forgejoUrlInput.text;
                        backend.forgejoToken = forgejoTokenInput.text;
                        backend.forgejoOrg = forgejoOrgInput.text;
                        var res = backend.testForgejoConnection(forgejoUrlInput.text, forgejoTokenInput.text);
                        if (res && res.success) {
                            migrationTabRoot.forgejoConnSuccess = true;
                            migrationTabRoot.forgejoConnStatusText = "✓ Connected (Forgejo " + (res.version || "") + (res.username ? " • @" + res.username : "") + ")";
                        } else {
                            migrationTabRoot.forgejoConnSuccess = false;
                            migrationTabRoot.forgejoConnStatusText = "❌ " + ((res && res.error) ? res.error : "Connection failed");
                        }
                    }
                }

                Text {
                    visible: migrationTabRoot.forgejoConnStatusText !== ""
                    text: migrationTabRoot.forgejoConnStatusText
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: migrationTabRoot.forgejoConnSuccess ? "#3fb950" : "#f85149"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "🚀 Sync Repositories to Forgejo"
                    enabled: backend ? !backend.isBusy : false
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 215; radius: 6
                        color: parent.hovered ? "#388bfd" : "#1f6feb"
                        border.color: "#58a6ff"; border.width: 1
                    }
                    onClicked: {
                        if (!backend) return;
                        backend.forgejoUrl = forgejoUrlInput.text;
                        backend.forgejoToken = forgejoTokenInput.text;
                        backend.forgejoOrg = forgejoOrgInput.text;
                        backend.syncForgejoAsync(
                            forgejoUrlInput.text,
                            forgejoTokenInput.text,
                            forgejoOrgInput.text,
                            backend.forgejoStrategy,
                            false
                        );
                    }
                }
            }
        }
    }

    // =========================================================================
    // 4. Repository Standby Status Matrix
    // =========================================================================
    Rectangle {
        Layout.fillWidth: true
        visible: migrationTabRoot.migrationStatusEntries.length > 0
        implicitHeight: statusMatrixCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: statusMatrixCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            Text {
                text: "📋 Repository Backup & Standby Status (" + migrationTabRoot.migrationStatusEntries.length + ")"
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 14
                font.weight: Font.Bold
                color: "#f0f6fc"
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            Repeater {
                model: migrationTabRoot.migrationStatusEntries

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 6
                    color: "#0d1117"
                    border.color: "#21262d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Text {
                            text: modelData.repo_name || ""
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                            Layout.preferredWidth: 220
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: locBadge.implicitWidth + 12
                            radius: 10
                            color: modelData.local_status === "OK" ? "#162b20" : (modelData.local_status === "FAILED" ? "#3c1e1e" : "#21262d")
                            border.color: modelData.local_status === "OK" ? "#238636" : (modelData.local_status === "FAILED" ? "#f85149" : "#30363d")
                            border.width: 1
                            Text {
                                id: locBadge
                                anchors.centerIn: parent
                                text: "Local: " + (modelData.local_status || "PENDING")
                                font.pixelSize: 10; font.weight: Font.Bold
                                color: modelData.local_status === "OK" ? "#3fb950" : (modelData.local_status === "FAILED" ? "#f85149" : "#8b949e")
                            }
                        }

                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: fgBadge.implicitWidth + 12
                            radius: 10
                            color: modelData.forgejo_status === "OK" ? "#16243b" : (modelData.forgejo_status === "FAILED" ? "#3c1e1e" : "#21262d")
                            border.color: modelData.forgejo_status === "OK" ? "#388bfd" : (modelData.forgejo_status === "FAILED" ? "#f85149" : "#30363d")
                            border.width: 1
                            Text {
                                id: fgBadge
                                anchors.centerIn: parent
                                text: "Forgejo: " + (modelData.forgejo_status || "PENDING")
                                font.pixelSize: 10; font.weight: Font.Bold
                                color: modelData.forgejo_status === "OK" ? "#58a6ff" : (modelData.forgejo_status === "FAILED" ? "#f85149" : "#8b949e")
                            }
                        }

                        Text {
                            text: modelData.last_error ? ("⚠️ " + modelData.last_error) : (modelData.local_worktree_path || modelData.local_mirror_path || "")
                            font.family: "Consolas, monospace"
                            font.pixelSize: 10
                            color: modelData.last_error ? "#f85149" : "#8b949e"
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}

