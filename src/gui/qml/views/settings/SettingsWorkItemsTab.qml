import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

ColumnLayout {
    id: tabRoot
    Layout.fillWidth: true
    spacing: 16

    // ==========================================
    // Agile & Deadline Attribute Configuration Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: deadlineCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: deadlineCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                spacing: 8
                Text { text: "🎯"; font.pixelSize: 16 }
                Text {
                    text: "Work Item Deadline Attribute Configuration"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                }
            }

            Text {
                text: "Specify a custom TFS / Azure DevOps field reference name used for milestone deadlines (e.g. Custom.MilestoneDeadline). If left empty, the application automatically inspects Microsoft.VSTS.Scheduling.TargetDate, DueDate, FinishDate, or weekly sprint milestone dates."
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                color: "#8b949e"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                TextField {
                    id: deadlineFieldInput
                    Layout.fillWidth: true
                    implicitHeight: 34
                    font.family: "Consolas, monospace"
                    font.pixelSize: 12
                    text: (backend && backend.customDeadlineField) ? backend.customDeadlineField : ""
                    placeholderText: "e.g. Microsoft.VSTS.Scheduling.TargetDate or Custom.MilestoneDeadline"
                    placeholderTextColor: "#484f58"
                    color: "#f0f6fc"
                    background: Rectangle {
                        color: "#0d1117"
                        radius: 6
                        border.color: deadlineFieldInput.activeFocus ? "#58a6ff" : "#30363d"
                        border.width: 1
                    }
                }

                Button {
                    text: "💾 Save Attribute"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 130; radius: 6
                        color: parent.hovered ? "#1f6feb" : "#238636"
                        border.color: "#3fb950"
                    }
                    onClicked: {
                        if (backend) {
                            backend.setCustomDeadlineField(deadlineFieldInput.text);
                            root.bannerMsg = "Custom deadline field updated to: " + (deadlineFieldInput.text.trim() || "Default (TargetDate / DueDate)");
                            root.bannerType = "success";
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#30363d"
                Layout.topMargin: 4
                Layout.bottomMargin: 4
            }

            // TFS / Azure DevOps Team Name & Sprint Taskboard URL Configuration
            RowLayout {
                spacing: 8
                Text { text: "🎯"; font.pixelSize: 18 }
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Azure DevOps / TFS Sprint Taskboard URL Configuration & Testing"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Configure team assignment, customize the URL template for your TFS/Azure DevOps server, and test sprint links in your browser."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }
            }

            // 1. Team Name Assignment
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Team Name Assignment:"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: "#c9d1d9"
                    }

                    Rectangle {
                        visible: !(backend && backend.tfsTeamName)
                        implicitHeight: 18
                        implicitWidth: defaultBadgeTxt.implicitWidth + 12
                        radius: 9
                        color: "#1f2937"
                        border.color: "#374151"
                        border.width: 1

                        Text {
                            id: defaultBadgeTxt
                            anchors.centerIn: parent
                            text: "Using Default: " + ((backend && backend.defaultTfsTeam) ? backend.defaultTfsTeam : "{Project} Team")
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#58a6ff"
                        }
                    }
                }

                Text {
                    text: "Specify the Team Name that sprint iterations are assigned to. When left empty, the application will use the Default Team ('" + ((backend && backend.defaultTfsTeam) ? backend.defaultTfsTeam : "{Project} Team") + "')."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    TextField {
                        id: teamNameInput
                        Layout.fillWidth: true
                        implicitHeight: 34
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        text: (backend && backend.tfsTeamName) ? backend.tfsTeamName : ""
                        placeholderText: (backend && backend.defaultTfsTeam) ? ("Default: " + backend.defaultTfsTeam) : "Default: {Project} Team"
                        placeholderTextColor: "#484f58"
                        color: "#f0f6fc"
                        background: Rectangle {
                            color: "#0d1117"
                            radius: 6
                            border.color: teamNameInput.activeFocus ? "#58a6ff" : "#30363d"
                            border.width: 1
                        }
                    }

                    Button {
                        text: "💾 Save Team"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        contentItem: Text {
                            text: parent.text; font: parent.font; color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 34; implicitWidth: 130; radius: 6
                            color: parent.hovered ? "#2ea043" : "#238636"
                            border.color: "#3fb950"
                        }
                        onClicked: {
                            if (backend) {
                                backend.setTfsTeamName(teamNameInput.text);
                                var savedTeam = teamNameInput.text.trim();
                                root.bannerMsg = "TFS Team Name updated to: " + (savedTeam || ("Default Team (" + (backend.defaultTfsTeam || "Project Team") + ")"));
                                root.bannerType = "success";
                            }
                        }
                    }
                }
            }

            // 2. Sprint URL Syntax Template & Presets
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Layout.topMargin: 4

                Text {
                    text: "Sprint URL Syntax Template:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#c9d1d9"
                }

                Text {
                    text: "Select a syntax preset matching your server environment, or craft a custom URL template using placeholders."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                // Presets Row
                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { name: "⚡ Modern Hierarchical (Default)", tmpl: "{base_url}/{collection}/{project}/_sprints/{view_mode}/{team}/{iteration_path}" },
                            { name: "📁 Team Sprints Leaf", tmpl: "{base_url}/{collection}/{project}/_sprints/{view_mode}/{team}/sprints/{iteration_leaf}" },
                            { name: "📋 TFS Boards Taskboard", tmpl: "{base_url}/{collection}/{project}/{team}/_boards/iteration/taskboard/{iteration_leaf}" },
                            { name: "🗂️ TFS Legacy Backlogs", tmpl: "{base_url}/{collection}/{project}/{team}/_backlogs/iteration/{iteration_leaf}" },
                            { name: "☁️ Azure Cloud Simple", tmpl: "{base_url}/{collection}/{project}/_sprints/{view_mode}/{team}/{iteration_leaf}" }
                        ]

                        Rectangle {
                            implicitHeight: 26
                            implicitWidth: presetLabel.implicitWidth + 16
                            radius: 13
                            color: (sprintUrlTemplateInput.text === modelData.tmpl || (!sprintUrlTemplateInput.text && modelData.tmpl.includes("{iteration_path}"))) ? "#1f6feb22" : "#21262d"
                            border.color: (sprintUrlTemplateInput.text === modelData.tmpl || (!sprintUrlTemplateInput.text && modelData.tmpl.includes("{iteration_path}"))) ? "#58a6ff" : "#30363d"
                            border.width: 1

                            Text {
                                id: presetLabel
                                anchors.centerIn: parent
                                text: modelData.name
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: (sprintUrlTemplateInput.text === modelData.tmpl || (!sprintUrlTemplateInput.text && modelData.tmpl.includes("{iteration_path}"))) ? "#58a6ff" : "#c9d1d9"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    sprintUrlTemplateInput.text = modelData.tmpl;
                                }
                            }
                        }
                    }
                }

                // Template input & save row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    TextField {
                        id: sprintUrlTemplateInput
                        Layout.fillWidth: true
                        implicitHeight: 34
                        font.family: "Consolas, Segoe UI, sans-serif"
                        font.pixelSize: 11
                        text: (backend && backend.sprintUrlTemplate) ? backend.sprintUrlTemplate : "{base_url}/{collection}/{project}/_sprints/{view_mode}/{team}/{iteration_path}"
                        placeholderText: "e.g. {base_url}/{collection}/{project}/_sprints/{view_mode}/{team}/{iteration_path}"
                        placeholderTextColor: "#484f58"
                        color: "#58a6ff"
                        background: Rectangle {
                            color: "#0d1117"
                            radius: 6
                            border.color: sprintUrlTemplateInput.activeFocus ? "#58a6ff" : "#30363d"
                            border.width: 1
                        }
                    }

                    Button {
                        text: "💾 Save Syntax"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        contentItem: Text {
                            text: parent.text; font: parent.font; color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 34; implicitWidth: 130; radius: 6
                            color: parent.hovered ? "#2ea043" : "#238636"
                            border.color: "#3fb950"
                        }
                        onClicked: {
                            if (backend) {
                                backend.setSprintUrlTemplate(sprintUrlTemplateInput.text);
                                root.bannerMsg = "Sprint URL Syntax Template updated!";
                                root.bannerType = "success";
                            }
                        }
                    }

                    Button {
                        text: "↺ Reset"
                        font.pixelSize: 11
                        contentItem: Text {
                            text: parent.text; font: parent.font; color: "#8b949e"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 34; implicitWidth: 70; radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            sprintUrlTemplateInput.text = "{base_url}/{collection}/{project}/_sprints/{view_mode}/{team}/{iteration_path}";
                            if (backend) {
                                backend.setSprintUrlTemplate("");
                                root.bannerMsg = "Sprint URL Syntax Template reset to default.";
                                root.bannerType = "info";
                            }
                        }
                    }
                }

                // Placeholder Tokens Chips
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: "Tokens (click to append):"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [
                                "{base_url}", "{collection}", "{project}", "{team}", "{view_mode}", "{iteration_path}", "{iteration_leaf}", "{workitem_id}"
                            ]
                            Rectangle {
                                implicitHeight: 20
                                implicitWidth: tokenText.implicitWidth + 10
                                radius: 4
                                color: "#161b22"
                                border.color: "#30363d"
                                border.width: 1

                                Text {
                                    id: tokenText
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 10
                                    color: "#79c0ff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!sprintUrlTemplateInput.text.includes(modelData)) {
                                            sprintUrlTemplateInput.text = sprintUrlTemplateInput.text + "/" + modelData;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 3. Interactive Testing Sandbox & Live URL Preview
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: testSandboxCol.implicitHeight + 24
                radius: 6
                color: "#0d1117"
                border.color: "#21262d"
                border.width: 1

                ColumnLayout {
                    id: testSandboxCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        spacing: 6
                        Text { text: "🧪"; font.pixelSize: 14 }
                        Text {
                            text: "Sprint URL Live Preview & Browser Test Sandbox"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                    }

                    // Test Parameter Inputs
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Sample Sprint:"; font.pixelSize: 10; color: "#8b949e" }
                            TextField {
                                id: testSprintInput
                                Layout.fillWidth: true
                                implicitHeight: 28
                                font.pixelSize: 11
                                text: "week-2634"
                                color: "#f0f6fc"
                                background: Rectangle { color: "#161b22"; radius: 4; border.color: "#30363d" }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Sample Team:"; font.pixelSize: 10; color: "#8b949e" }
                            TextField {
                                id: testTeamInput
                                Layout.fillWidth: true
                                implicitHeight: 28
                                font.pixelSize: 11
                                text: teamNameInput.text.trim() || "Alpha Team"
                                color: "#f0f6fc"
                                background: Rectangle { color: "#161b22"; radius: 4; border.color: "#30363d" }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Sample Work Item ID:"; font.pixelSize: 10; color: "#8b949e" }
                            TextField {
                                id: testWiInput
                                Layout.fillWidth: true
                                implicitHeight: 28
                                font.pixelSize: 11
                                text: "5634858"
                                color: "#f0f6fc"
                                background: Rectangle { color: "#161b22"; radius: 4; border.color: "#30363d" }
                            }
                        }
                    }

                    // Live Formatted URL Display & Test Button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 4
                            color: "#161b22"
                            border.color: "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                Text { text: "🔗"; font.pixelSize: 12 }
                                Text {
                                    id: livePreviewUrlText
                                    Layout.fillWidth: true
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 11
                                    color: "#58a6ff"
                                    elide: Text.ElideMiddle
                                    text: backend ? backend.preview_sprint_url(
                                        testWiInput.text.trim(),
                                        testSprintInput.text.trim(),
                                        testTeamInput.text.trim(),
                                        sprintUrlTemplateInput.text.trim()
                                    ) : ""
                                }
                            }
                        }

                        Button {
                            text: "🌐 Open in Browser"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            contentItem: Text {
                                text: parent.text; font: parent.font; color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 32; implicitWidth: 140; radius: 4
                                color: parent.hovered ? "#388bfd" : "#1f6feb"
                            }
                            onClicked: {
                                if (backend) {
                                    backend.test_open_sprint_url(
                                        testWiInput.text.trim(),
                                        testSprintInput.text.trim(),
                                        testTeamInput.text.trim(),
                                        sprintUrlTemplateInput.text.trim()
                                    );
                                    root.bannerMsg = "Opened sprint URL in system browser for verification.";
                                    root.bannerType = "info";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // Project Area Path Settings & Work Item Filter Card
    // ==========================================
    Rectangle {
        id: areaPathCard
        Layout.fillWidth: true
        implicitHeight: areaPathCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        property var rulesList: []
        property bool filterEnabled: true
        property string testSampleText: ""
        property var testResult: ({ matched: false, rule: "" })

        function loadAreaSettings() {
            if (backend) {
                filterEnabled = backend.areaPathFilterEnabled;
                var src = backend.areaPathRules || [];
                var copy = [];
                for (var i = 0; i < src.length; i++) {
                    copy.push({
                        path: src[i].path || "",
                        include_children: src[i].include_children !== undefined ? src[i].include_children : true
                    });
                }
                rulesList = copy;
            }
        }

        function saveAreaSettings() {
            if (backend) {
                backend.saveAreaPathRules(JSON.stringify(rulesList), filterEnabled);
                root.bannerMsg = "Project Area Path settings saved (" + rulesList.length + " rule(s), filter " + (filterEnabled ? "enabled" : "disabled") + ").";
                root.bannerType = "success";
            }
        }

        function fetchFromTfs() {
            if (backend) {
                var res = backend.fetch_area_paths_from_tfs();
                if (res && res.success) {
                    loadAreaSettings();
                    root.bannerMsg = res.message || "Area Path settings fetched from TFS successfully.";
                    root.bannerType = res.is_permission_warning ? "info" : "success";
                } else if (res && res.error) {
                    root.bannerMsg = res.is_permission_error 
                        ? res.error 
                        : ("Failed to fetch Area Paths from TFS: " + res.error);
                    root.bannerType = res.is_permission_error ? "warning" : "error";
                }
            }
        }

        function deleteRule(idx) {
            if (idx >= 0 && idx < rulesList.length) {
                var removed = rulesList[idx];
                var updated = [];
                for (var i = 0; i < rulesList.length; i++) {
                    if (i !== idx) {
                        updated.push(rulesList[i]);
                    }
                }
                rulesList = updated;
                root.bannerMsg = "Deleted Area Path rule: " + (removed ? removed.path : "");
                root.bannerType = "info";
            }
        }

        function clearAllRules() {
            rulesList = [];
            if (backend) {
                backend.clear_area_path_rules();
            }
            root.bannerMsg = "Cleared all Area Path filter rules.";
            root.bannerType = "info";
        }

        function resetDefaults() {
            if (backend) {
                backend.reset_area_path_settings();
                loadAreaSettings();
                root.bannerMsg = "Area Path filter reset to project root defaults.";
                root.bannerType = "info";
            }
        }

        function updateTest(text) {
            testSampleText = text;
            if (backend && text.trim() !== "") {
                testResult = backend.test_area_path_match(text);
            } else {
                testResult = { matched: false, rule: "" };
            }
        }

        Component.onCompleted: loadAreaSettings()

        Connections {
            target: backend
            function onAreaPathSettingsChanged() {
                areaPathCard.loadAreaSettings();
            }
            function onSettingsChanged() {
                areaPathCard.loadAreaSettings();
            }
        }

        ColumnLayout {
            id: areaPathCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text { text: "🌿"; font.pixelSize: 20 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Project Area Path Settings & Work Item Filter"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Read Area Path settings from Azure DevOps / TFS and automatically filter considered work items across Tag Day reports, sprint metrics, workload explorer, and dashboards. If PAT lacks teamsettings permissions, custom Area Path rules can still be configured manually below."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Item { Layout.fillWidth: true }

                // Status Pill
                Rectangle {
                    implicitHeight: 22
                    implicitWidth: areaFilterStatusText.implicitWidth + 16
                    radius: 11
                    color: (backend && backend.areaPathFilterEnabled && areaPathCard.rulesList.length > 0)
                        ? "#162b20" : (!backend || !backend.areaPathFilterEnabled ? "#3c2d1e" : "#16243b")
                    border.color: (backend && backend.areaPathFilterEnabled && areaPathCard.rulesList.length > 0)
                        ? "#238636" : (!backend || !backend.areaPathFilterEnabled ? "#d29922" : "#388bfd")
                    border.width: 1

                    Text {
                        id: areaFilterStatusText
                        anchors.centerIn: parent
                        text: {
                            if (!backend || !backend.areaPathFilterEnabled) {
                                return "● Filter Disabled (All items)";
                            }
                            if (areaPathCard.rulesList.length === 0) {
                                return "● No Filter Rules";
                            }
                            var fCount = backend.workItemsFilteredByAreaPathCount || 0;
                            return "● Filter Active (" + areaPathCard.rulesList.length + " rules" + (fCount > 0 ? (" • " + fCount + " excluded") : "") + ")";
                        }
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: (backend && backend.areaPathFilterEnabled && areaPathCard.rulesList.length > 0)
                            ? "#3fb950" : (!backend || !backend.areaPathFilterEnabled ? "#e3b341" : "#58a6ff")
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Master Filter Toggle & Default Area Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                CheckBox {
                    id: chkAreaFilterEnabled
                    text: "Automatically filter work items by Project Area Path settings"
                    checked: areaPathCard.filterEnabled
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0f6fc"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                    onCheckedChanged: {
                        areaPathCard.filterEnabled = checked;
                    }
                }

                Item { Layout.fillWidth: true }

                // Default Project Area Path Badge & Clear Action
                Rectangle {
                    implicitHeight: 26
                    implicitWidth: defAreaRow.implicitWidth + 16
                    radius: 4
                    color: (backend && backend.defaultAreaPath && backend.defaultAreaPath.trim() !== "") ? "#0d1117" : "#162b20"
                    border.color: (backend && backend.defaultAreaPath && backend.defaultAreaPath.trim() !== "") ? "#30363d" : "#238636"
                    border.width: 1

                    RowLayout {
                        id: defAreaRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "Default Area:"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                        }

                        Text {
                            text: (backend && backend.defaultAreaPath && backend.defaultAreaPath.trim() !== "") 
                                ? backend.defaultAreaPath 
                                : "None (Filtering on Sub-Areas only)"
                            font.family: (backend && backend.defaultAreaPath && backend.defaultAreaPath.trim() !== "") ? "Consolas, monospace" : "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: (backend && backend.defaultAreaPath && backend.defaultAreaPath.trim() !== "") ? "#58a6ff" : "#3fb950"
                        }

                        // Delete / Clear Default Area button
                        Button {
                            visible: !!(backend && backend.defaultAreaPath && backend.defaultAreaPath.trim() !== "")
                            implicitHeight: 20
                            implicitWidth: 20
                            text: "✖"
                            ToolTip.visible: hovered
                            ToolTip.text: "Delete Default Area to filter only on specific Sub-Areas"
                            contentItem: Text {
                                text: parent.text
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: parent.hovered ? "#f85149" : "#8b949e"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 3
                                color: parent.hovered ? "#3c1e1e" : "transparent"
                            }
                            onClicked: {
                                if (backend) {
                                    backend.deleteDefaultAreaPath();
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: "When enabled, only work items belonging to the configured Area Paths below (or their sub-areas if checked) will be evaluated in metrics, dashboard counts, sprint reports, tagday milestones, and workload views."
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 11
                color: "#8b949e"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // Rules Table Header
            Rectangle {
                Layout.fillWidth: true
                height: 30
                color: "#0d1117"
                radius: 4
                border.color: "#30363d"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Text {
                        text: "AREA PATH"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: "#8b949e"
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "SUB-AREAS SCOPE"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: "#8b949e"
                        Layout.preferredWidth: 160
                    }

                    Text {
                        text: "ACTIONS"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: "#8b949e"
                        horizontalAlignment: Text.AlignHCenter
                        Layout.preferredWidth: 60
                    }
                }
            }

            // Active Rules List Repeater
            Repeater {
                model: areaPathCard.rulesList

                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 4
                    color: ruleItemMa.containsMouse ? "#1c2128" : "#0d1117"
                    border.color: "#21262d"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: "📁"; font.pixelSize: 12 }

                            Text {
                                text: modelData.path || ""
                                font.family: "Consolas, monospace"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: "#f0f6fc"
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }
                        }

                        // Include sub-areas toggle / pill
                        Rectangle {
                            Layout.preferredWidth: 160
                            implicitHeight: 24
                            radius: 4
                            color: modelData.include_children ? "#162b20" : "#21262d"
                            border.color: modelData.include_children ? "#238636" : "#30363d"
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: modelData.include_children ? "✓ Include sub-areas (*)" : "• Exact area only"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    color: modelData.include_children ? "#3fb950" : "#8b949e"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var updated = [];
                                    for (var i = 0; i < areaPathCard.rulesList.length; i++) {
                                        if (i === index) {
                                            updated.push({
                                                path: areaPathCard.rulesList[i].path,
                                                include_children: !areaPathCard.rulesList[i].include_children
                                            });
                                        } else {
                                            updated.push(areaPathCard.rulesList[i]);
                                        }
                                    }
                                    areaPathCard.rulesList = updated;
                                }
                            }
                        }

                        // Remove Rule Button
                        Button {
                            Layout.preferredWidth: 60
                            implicitHeight: 24
                            text: "🗑️"
                            ToolTip.visible: hovered
                            ToolTip.text: "Remove this Area Path rule"
                            contentItem: Text {
                                text: parent.text
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 4
                                color: parent.hovered ? "#3c1e1e" : "transparent"
                                border.color: parent.hovered ? "#f85149" : "#30363d"
                            }
                            onClicked: areaPathCard.deleteRule(index)
                        }
                    }

                    MouseArea {
                        id: ruleItemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: true
                    }
                }
            }

            // Empty state
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                visible: areaPathCard.rulesList.length === 0
                color: "#0d1117"
                radius: 4
                border.color: "#21262d"

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "ℹ️"; font.pixelSize: 13 }
                    Text {
                        text: "No Area Path rules defined. Click 'Fetch from TFS' to auto-read the project settings or add an area path below."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }
            }

            // Add Rule Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                TextField {
                    id: newAreaPathInput
                    Layout.fillWidth: true
                    implicitHeight: 34
                    font.family: "Consolas, monospace"
                    font.pixelSize: 12
                    placeholderText: "e.g. " + (backend && backend.projectName ? backend.projectName : "Project") + "\\AreaName or SubArea"
                    placeholderTextColor: "#484f58"
                    color: "#f0f6fc"
                    background: Rectangle {
                        color: "#0d1117"
                        radius: 6
                        border.color: newAreaPathInput.activeFocus ? "#58a6ff" : "#30363d"
                        border.width: 1
                    }
                    onAccepted: addAreaPathBtn.clicked()
                }

                CheckBox {
                    id: chkIncludeSubAreas
                    text: "Include Sub-Areas (*)"
                    checked: true
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#8b949e"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                }

                Button {
                    id: addAreaPathBtn
                    text: "➕ Add Rule"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 100; radius: 6
                        color: parent.hovered ? "#1f6feb" : "#238636"
                        border.color: "#3fb950"
                    }
                    onClicked: {
                        var val = newAreaPathInput.text.trim();
                        if (!val) return;
                        var exists = false;
                        for (var i = 0; i < areaPathCard.rulesList.length; i++) {
                            if (areaPathCard.rulesList[i].path.toLowerCase() === val.toLowerCase()) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists) {
                            var updated = [];
                            for (var j = 0; j < areaPathCard.rulesList.length; j++) {
                                updated.push(areaPathCard.rulesList[j]);
                            }
                            updated.push({
                                path: val,
                                include_children: chkIncludeSubAreas.checked
                            });
                            areaPathCard.rulesList = updated;
                            newAreaPathInput.text = "";
                        }
                    }
                }
            }

            // Discovered Area Paths Dropdown / Helper if available
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: !!(backend && backend.allDiscoveredAreaPaths && backend.allDiscoveredAreaPaths.length > 0)

                Text {
                    text: "Discovered Area Paths in Project:"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                ComboBox {
                    id: discoveredAreasCombo
                    Layout.fillWidth: true
                    implicitHeight: 28
                    font.family: "Consolas, monospace"
                    font.pixelSize: 11
                    model: backend ? backend.allDiscoveredAreaPaths : []
                    background: Rectangle {
                        color: "#0d1117"
                        radius: 4
                        border.color: "#30363d"
                    }
                }

                Button {
                    text: "Add Selected"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 28; implicitWidth: 100; radius: 4
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: "#30363d"
                    }
                    onClicked: {
                        var chosen = discoveredAreasCombo.currentText;
                        if (chosen) {
                            newAreaPathInput.text = chosen;
                            addAreaPathBtn.clicked();
                        }
                    }
                }
            }

            // Filter Rule Test Sandbox
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: areaSandboxCol.implicitHeight + 20
                radius: 6
                color: "#0d1117"
                border.color: "#21262d"
                border.width: 1

                ColumnLayout {
                    id: areaSandboxCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        spacing: 6
                        Text { text: "🧪"; font.pixelSize: 14 }
                        Text {
                            text: "Area Path Rule Test Sandbox"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        TextField {
                            id: testAreaInput
                            Layout.fillWidth: true
                            implicitHeight: 30
                            font.family: "Consolas, monospace"
                            font.pixelSize: 11
                            placeholderText: "Type sample Area Path (e.g. " + (backend && backend.projectName ? backend.projectName : "Project") + "\\SubArea\\Feature)"
                            placeholderTextColor: "#484f58"
                            color: "#f0f6fc"
                            background: Rectangle { color: "#161b22"; radius: 4; border.color: "#30363d" }
                            onTextChanged: areaPathCard.updateTest(text)
                        }

                        // Match status badge
                        Rectangle {
                            implicitHeight: 30
                            implicitWidth: 180
                            radius: 4
                            color: testAreaInput.text.trim() === "" ? "#21262d" : (areaPathCard.testResult.matched ? "#162b20" : "#3c1e1e")
                            border.color: testAreaInput.text.trim() === "" ? "#30363d" : (areaPathCard.testResult.matched ? "#238636" : "#f85149")
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: testAreaInput.text.trim() === "" 
                                    ? "Enter test path" 
                                    : (areaPathCard.testResult.matched 
                                        ? ("✓ Included (" + (areaPathCard.testResult.rule || "Match") + ")")
                                        : "🚫 Excluded (Filtered out)")
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: testAreaInput.text.trim() === "" ? "#8b949e" : (areaPathCard.testResult.matched ? "#3fb950" : "#f85149")
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // Action Buttons Row
            RowLayout {
                Layout.topMargin: 4
                spacing: 10

                Button {
                    text: "🔄 Fetch from Azure DevOps / TFS"
                    font.pixelSize: 12
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 230; radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: parent.hovered ? "#58a6ff" : "#30363d"
                        border.width: 1
                    }
                    onClicked: areaPathCard.fetchFromTfs()
                }

                Button {
                    text: "↺ Reset to Project Defaults"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#8b949e"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 170; radius: 6
                        color: parent.hovered ? "#30363d" : "transparent"
                        border.color: "#30363d"
                    }
                    onClicked: areaPathCard.resetDefaults()
                }

                Button {
                    text: "🗑️ Clear All Rules"
                    font.pixelSize: 11
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#f85149"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 130; radius: 6
                        color: parent.hovered ? "#3c1e1e" : "transparent"
                        border.color: parent.hovered ? "#f85149" : "#30363d"
                    }
                    onClicked: areaPathCard.clearAllRules()
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Scope: " + (backend ? backend.workItemsCount : 0) + " items considered" + (backend && backend.workItemsFilteredByAreaPathCount > 0 ? (" (" + backend.workItemsFilteredByAreaPathCount + " filtered out)") : "")
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#8b949e"
                }

                Button {
                    text: "💾 Save Area Path Settings"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 190; radius: 6
                        color: parent.hovered ? "#1f6feb" : "#238636"
                        border.color: "#3fb950"
                    }
                    onClicked: areaPathCard.saveAreaSettings()
                }
            }
        }
    }

    // ==========================================
    // Work Item Tag Categories Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: tagCatCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        // Local state for the editable rules list and add-row
        property var tagRules: []
        property string newPattern: ""
        property string newCategory: ""

        id: tagCatCard

        function loadRules() {
            if (backend && backend.tagCategories) {
                // Deep-copy so edits don't mutate the backend list directly
                var src = backend.tagCategories;
                var copy = [];
                for (var i = 0; i < src.length; i++) {
                    copy.push({ pattern: src[i].pattern || "", category: src[i].category || "" });
                }
                tagRules = copy;
            }
        }

        function saveRules() {
            if (!backend) return;
            backend.save_tag_categories(JSON.stringify(tagRules));
            root.bannerMsg = "Tag categories saved (" + tagRules.length + " rules).";
            root.bannerType = "success";
        }

        function resetToDefaults() {
            tagRules = [
                { pattern: "Target:*",    category: "Milestone" },
                { pattern: "Subsystem:*", category: "PBS" },
                { pattern: "v*.*.*",      category: "Software Revision" },
                { pattern: "OI",          category: "Open Item" },
                { pattern: "MP",          category: "Merkpunkt" }
            ];
            saveRules();
        }

        Component.onCompleted: loadRules()

        Connections {
            target: backend
            function onTagCategoriesChanged() { tagCatCard.loadRules(); }
        }

        ColumnLayout {
            id: tagCatCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // ---- Header ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { text: "🏷️"; font.pixelSize: 18 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Work Item Tag Categories"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Map tag patterns to category names. Use * for wildcards (e.g. Target:* → Milestone). Rules are evaluated top-to-bottom; the first match wins."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "↺ Reset to Defaults"
                    font.pixelSize: 11
                    ToolTip.visible: hovered
                    ToolTip.text: "Restore the five built-in rules"
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#8b949e"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 28; implicitWidth: 130; radius: 5
                        color: parent.hovered ? "#30363d" : "transparent"
                        border.color: "#30363d"
                    }
                    onClicked: tagCatCard.resetToDefaults()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // ---- Table Header ----
            Rectangle {
                Layout.fillWidth: true
                height: 28
                color: "#0d1117"
                radius: 4
                border.color: "#21262d"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text { text: "#";        font.pixelSize: 10; font.weight: Font.Bold; color: "#6e7681"; Layout.preferredWidth: 20 }
                    Text { text: "PATTERN";  font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e"; Layout.fillWidth: true }
                    Text { text: "CATEGORY"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e"; Layout.preferredWidth: 160 }
                    Text { text: "";          font.pixelSize: 10; color: "transparent";   Layout.preferredWidth: 54 }
                }
            }

            // ---- Rules List ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: tagCatCard.tagRules

                    delegate: Rectangle {
                        id: ruleRow
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 5
                        color: ruleRowMa.containsMouse ? "#1c2128" : "#0d1117"
                        border.color: "#21262d"

                        property int ruleIndex: index

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            // Row number
                            Text {
                                text: (ruleRow.ruleIndex + 1) + "."
                                font.pixelSize: 11
                                color: "#484f58"
                                Layout.preferredWidth: 20
                            }

                            // Pattern field (editable)
                            TextField {
                                id: patternField
                                Layout.fillWidth: true
                                implicitHeight: 26
                                text: modelData.pattern
                                font.family: "Consolas, monospace"
                                font.pixelSize: 11
                                color: "#58a6ff"
                                placeholderText: "e.g.  Target:*  or  v*.*.*"
                                placeholderTextColor: "#484f58"
                                background: Rectangle {
                                    color: patternField.activeFocus ? "#0d2344" : "transparent"
                                    radius: 4
                                    border.color: patternField.activeFocus ? "#388bfd" : "transparent"
                                }
                                onEditingFinished: {
                                    var rules = tagCatCard.tagRules.slice();
                                    rules[ruleRow.ruleIndex] = { pattern: text.trim(), category: rules[ruleRow.ruleIndex].category };
                                    tagCatCard.tagRules = rules;
                                }
                            }

                            // Category field (editable)
                            TextField {
                                id: categoryField
                                Layout.preferredWidth: 160
                                implicitHeight: 26
                                text: modelData.category
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#e6edf3"
                                placeholderText: "Category name"
                                placeholderTextColor: "#484f58"
                                background: Rectangle {
                                    color: categoryField.activeFocus ? "#1a2a1a" : "transparent"
                                    radius: 4
                                    border.color: categoryField.activeFocus ? "#3fb950" : "transparent"
                                }
                                onEditingFinished: {
                                    var rules = tagCatCard.tagRules.slice();
                                    rules[ruleRow.ruleIndex] = { pattern: rules[ruleRow.ruleIndex].pattern, category: text.trim() };
                                    tagCatCard.tagRules = rules;
                                }
                            }

                            // Move up / down / remove buttons
                            RowLayout {
                                spacing: 2
                                Layout.preferredWidth: 54

                                // ↑ Move up
                                Text {
                                    text: "↑"
                                    font.pixelSize: 13
                                    color: upMa.containsMouse ? "#79c0ff" : "#484f58"
                                    visible: ruleRow.ruleIndex > 0
                                    MouseArea {
                                        id: upMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var rules = tagCatCard.tagRules.slice();
                                            var tmp = rules[ruleRow.ruleIndex - 1];
                                            rules[ruleRow.ruleIndex - 1] = rules[ruleRow.ruleIndex];
                                            rules[ruleRow.ruleIndex] = tmp;
                                            tagCatCard.tagRules = rules;
                                        }
                                    }
                                    ToolTip.visible: upMa.containsMouse; ToolTip.text: "Move rule up"
                                }

                                // ↓ Move down
                                Text {
                                    text: "↓"
                                    font.pixelSize: 13
                                    color: downMa.containsMouse ? "#79c0ff" : "#484f58"
                                    visible: ruleRow.ruleIndex < tagCatCard.tagRules.length - 1
                                    MouseArea {
                                        id: downMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var rules = tagCatCard.tagRules.slice();
                                            var tmp = rules[ruleRow.ruleIndex + 1];
                                            rules[ruleRow.ruleIndex + 1] = rules[ruleRow.ruleIndex];
                                            rules[ruleRow.ruleIndex] = tmp;
                                            tagCatCard.tagRules = rules;
                                        }
                                    }
                                    ToolTip.visible: downMa.containsMouse; ToolTip.text: "Move rule down"
                                }

                                // ✕ Remove
                                Text {
                                    text: "✕"
                                    font.pixelSize: 12
                                    color: removeMa.containsMouse ? "#f85149" : "#484f58"
                                    MouseArea {
                                        id: removeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var rules = tagCatCard.tagRules.slice();
                                            rules.splice(ruleRow.ruleIndex, 1);
                                            tagCatCard.tagRules = rules;
                                        }
                                    }
                                    ToolTip.visible: removeMa.containsMouse; ToolTip.text: "Remove rule"
                                }
                            }
                        }

                        MouseArea {
                            id: ruleRowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            cursorShape: Qt.ArrowCursor
                        }
                    }
                }

                // Empty placeholder
                Text {
                    visible: tagCatCard.tagRules.length === 0
                    text: "No rules defined. Add a rule below or click '↺ Reset to Defaults'."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#484f58"
                    Layout.topMargin: 4
                }
            }

            // ---- Add New Rule Row ----
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: 5
                color: "#0d1117"
                border.color: "#238636"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "+"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#3fb950"
                        Layout.preferredWidth: 20
                    }

                    TextField {
                        id: newPatternField
                        Layout.fillWidth: true
                        implicitHeight: 26
                        text: tagCatCard.newPattern
                        font.family: "Consolas, monospace"
                        font.pixelSize: 11
                        color: "#58a6ff"
                        placeholderText: "Pattern  (e.g. QA:*)"
                        placeholderTextColor: "#484f58"
                        background: Rectangle {
                            color: newPatternField.activeFocus ? "#0d2344" : "transparent"
                            radius: 4
                            border.color: newPatternField.activeFocus ? "#388bfd" : "transparent"
                        }
                        onTextChanged: tagCatCard.newPattern = text
                        Keys.onReturnPressed: newCategoryField.forceActiveFocus()
                    }

                    TextField {
                        id: newCategoryField
                        Layout.preferredWidth: 160
                        implicitHeight: 26
                        text: tagCatCard.newCategory
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#e6edf3"
                        placeholderText: "Category name"
                        placeholderTextColor: "#484f58"
                        background: Rectangle {
                            color: newCategoryField.activeFocus ? "#1a2a1a" : "transparent"
                            radius: 4
                            border.color: newCategoryField.activeFocus ? "#3fb950" : "transparent"
                        }
                        onTextChanged: tagCatCard.newCategory = text
                        Keys.onReturnPressed: addRuleBtn.clicked()
                    }

                    Button {
                        id: addRuleBtn
                        text: "Add"
                        enabled: tagCatCard.newPattern.trim() !== "" && tagCatCard.newCategory.trim() !== ""
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        contentItem: Text {
                            text: parent.text; font: parent.font
                            color: parent.enabled ? "#ffffff" : "#484f58"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 28; implicitWidth: 54; radius: 5
                            color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#21262d"
                            border.color: parent.enabled ? "#3fb950" : "#30363d"
                        }
                        onClicked: {
                            var p = tagCatCard.newPattern.trim();
                            var c = tagCatCard.newCategory.trim();
                            if (p && c) {
                                var rules = tagCatCard.tagRules.slice();
                                rules.push({ pattern: p, category: c });
                                tagCatCard.tagRules = rules;
                                tagCatCard.newPattern = "";
                                tagCatCard.newCategory = "";
                                newPatternField.text = "";
                                newCategoryField.text = "";
                                newPatternField.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // ---- Save Button ----
            RowLayout {
                Layout.topMargin: 4
                spacing: 10

                Item { Layout.fillWidth: true }

                Text {
                    text: tagCatCard.tagRules.length + " rule(s) configured"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: "#484f58"
                }

                Button {
                    text: "💾 Save Tag Categories"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34; implicitWidth: 180; radius: 6
                        color: parent.hovered ? "#1f6feb" : "#238636"
                        border.color: "#3fb950"
                    }
                    onClicked: tagCatCard.saveRules()
                }
            }
        }
    }
}
