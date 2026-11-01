import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

Item {
    id: pipelinesTabRoot
    property var root: null
    property string statusFilter: "all" // "all", "favorites", "problems", "failed", "unstable", "healthy"
    property string searchQuery: ""
    property string viewMode: (typeof backend !== "undefined" && backend && backend.pipelinesViewMode) ? backend.pipelinesViewMode : "cards" // "cards" (default) or "list"
    property int favRevision: 0

    Layout.fillWidth: true
    Layout.fillHeight: true

    Connections {
        target: (typeof backend !== "undefined" && backend) ? backend : null
        ignoreUnknownSignals: true
        function onPipelinesViewModeChanged() {
            if (backend && backend.pipelinesViewMode) {
                pipelinesTabRoot.viewMode = backend.pipelinesViewMode;
            }
        }
        function onFavoritePipelinesChanged() {
            pipelinesTabRoot.favRevision++;
        }
        function onPipelinesDataChanged() {
            pipelinesTabRoot.favRevision++;
        }
    }

    function setViewMode(mode) {
        var m = (mode === "list") ? "list" : "cards";
        pipelinesTabRoot.viewMode = m;
        if (typeof backend !== "undefined" && backend && typeof backend.setPipelinesViewMode === "function") {
            backend.setPipelinesViewMode(m);
        }
    }

    function isPipeFav(p) {
        var _rev = pipelinesTabRoot.favRevision;
        if (!p) return false;
        if (p.is_favorite === true) return true;
        if (typeof backend !== "undefined" && backend && typeof backend.isPipelineFavorite === "function") {
            var key = (p.pipeline_id && p.pipeline_id > 0) ? String(p.pipeline_id) : (p.name || "");
            if (key && backend.isPipelineFavorite(key)) return true;
        }
        return false;
    }

    function togglePipeFav(p) {
        if (!p) return;
        var key = (p.name && String(p.name).trim() !== "") ? String(p.name) : String(p.pipeline_id || "");
        if (typeof backend !== "undefined" && backend && typeof backend.toggleFavoritePipeline === "function") {
            backend.toggleFavoritePipeline(key);
        }
        pipelinesTabRoot.favRevision++;
    }

    function openExternalUrl(urlStr) {
        if (!urlStr || String(urlStr).trim() === "") return;
        if (typeof backend !== "undefined" && backend && typeof backend.open_url === "function") {
            backend.open_url(String(urlStr));
        } else {
            Qt.openUrlExternally(String(urlStr));
        }
    }

    function openTfsPipeline(p) {
        if (!p) return;
        var urlStr = p.web_url || p.pipeline_url || p.url || "";
        var pid = p.pipeline_id || 0;
        if (typeof backend !== "undefined" && backend && typeof backend.open_pipeline_in_tfs === "function") {
            backend.open_pipeline_in_tfs(pid, urlStr);
        } else if (urlStr) {
            openExternalUrl(urlStr);
        }
    }

    function openTfsBuild(buildId, buildUrl) {
        var urlStr = buildUrl || "";
        var bid = buildId || 0;
        if (typeof backend !== "undefined" && backend && typeof backend.open_build_in_tfs === "function" && (bid > 0 || urlStr !== "")) {
            backend.open_build_in_tfs(bid, urlStr);
        } else if (urlStr) {
            openExternalUrl(urlStr);
        }
    }

    readonly property var pipelinesSummary: (typeof backend !== "undefined" && backend && backend.pipelinesData && backend.pipelinesData.summary) ? backend.pipelinesData.summary : ({
        "total_pipelines": 0,
        "favorite_count": 0,
        "healthy_count": 0,
        "unstable_count": 0,
        "failed_count": 0,
        "problem_count": 0,
        "running_count": 0,
        "aborted_or_idle_count": 0,
        "total_builds": 0,
        "overall_health_pct": 100.0,
        "overall_weather_icon": "☀️",
        "overall_weather_key": "sunny"
    })

    function sumVal(key, defVal) {
        return (pipelinesSummary && pipelinesSummary[key] !== undefined && pipelinesSummary[key] !== null) ? pipelinesSummary[key] : defVal;
    }

    readonly property var allPipelines: (typeof backend !== "undefined" && backend && backend.pipelinesData && backend.pipelinesData.pipelines) ? backend.pipelinesData.pipelines : []
    readonly property var problemPipelines: (typeof backend !== "undefined" && backend && backend.pipelinesData && backend.pipelinesData.problem_pipelines) ? backend.pipelinesData.problem_pipelines : []

    readonly property int favoriteCount: {
        var _rev = pipelinesTabRoot.favRevision;
        var list = allPipelines || [];
        var cnt = 0;
        for (var i = 0; i < list.length; i++) {
            if (isPipeFav(list[i])) cnt++;
        }
        return cnt > 0 ? cnt : sumVal("favorite_count", 0);
    }

    readonly property var filteredPipelines: {
        var _rev = pipelinesTabRoot.favRevision;
        var list = allPipelines || [];
        var favs = [];
        var others = [];
        var q = (searchQuery || "").trim().toLowerCase();
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (!p) continue;
            var fav = isPipeFav(p);
            if (statusFilter === "favorites" && !fav) continue;
            if (statusFilter === "problems" && !p.has_problem) continue;
            if (statusFilter === "failed" && p.status_key !== "failed") continue;
            if (statusFilter === "unstable" && p.status_key !== "unstable") continue;
            if (statusFilter === "healthy" && p.status_key !== "success") continue;

            if (q.length > 0) {
                var hay = ((p.name || "") + " " + (p.repo_name || "") + " " + (p.last_branch || "") + " " + (p.culprit_who || "") + " " + (p.culprit_what || "") + " " + (p.hint_text || "") + " " + (p.suspects_str || "")).toLowerCase();
                if (hay.indexOf(q) < 0) continue;
            }
            if (fav) {
                favs.push(p);
            } else {
                others.push(p);
            }
        }
        return favs.concat(others);
    }

    ScrollView {
        id: pipeScrollView
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: Math.max(300, pipeScrollView.availableWidth - 20)
            spacing: 16

            // ==========================================
            // Top Header, Independent Sync & Auto-Sync Bar
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: topBarCol.implicitHeight + 28
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: topBarCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: pipelinesTabRoot.sumVal("overall_weather_icon", "🔧")
                            font.pixelSize: 22
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Jenkins Build Pipeline Monitor & Culprit Analysis"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "Karten- & Listenansicht mit Favoriten-Priorisierung (⭐), direkten TFS Pipeline-/Job-Links sowie Verursacher-Hinweisen (Wer & Was)"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Independent Pipeline Sync Button
                        Button {
                            id: btnSyncPipelinesOnly
                            text: (typeof backend !== "undefined" && backend && backend.isBusy) ? "⏳ Syncing..." : "🔄 Sync Pipelines"
                            enabled: (typeof backend !== "undefined" && backend) ? !backend.isBusy : false
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: parent.enabled ? "#58a6ff" : "#8b949e"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 32
                                implicitWidth: 145
                                radius: 6
                                color: parent.enabled ? (parent.hovered ? "#1f324d" : "#121d2f") : "#21262d"
                                border.color: parent.enabled ? "#388bfd" : "#30363d"
                                border.width: 1
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: "Aktualisiert unabhängig nur die Build-Pipelines, letzten Läufe und Fehler-Timelines aus TFS"
                            onClicked: {
                                if (typeof backend !== "undefined" && backend) backend.sync_pipelines_async();
                            }
                        }

                        // Sync & Generate Full Report Button
                        Button {
                            text: "⚡ Sync & Report"
                            enabled: (typeof backend !== "undefined" && backend) ? !backend.isBusy : false
                            font.pixelSize: 12
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
                                implicitWidth: 145
                                radius: 6
                                color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#30363d"
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: "Synchronisiert Build-Pipelines aus TFS und erstellt BUILD_PIPELINES.md & CSV"
                            onClicked: {
                                if (typeof backend !== "undefined" && backend) backend.generate_pipelines_report_async();
                            }
                        }

                        Button {
                            text: "📑 BUILD_PIPELINES.md"
                            font.pixelSize: 12
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#f0f6fc"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 32
                                implicitWidth: 165
                                radius: 6
                                color: parent.hovered ? "#30363d" : "#21262d"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (typeof backend !== "undefined" && backend) backend.open_pipelines_report_file();
                            }
                        }

                        Button {
                            text: "📊 CSV"
                            font.pixelSize: 12
                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#f0f6fc"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 32
                                implicitWidth: 78
                                radius: 6
                                color: parent.hovered ? "#30363d" : "#21262d"
                                border.color: "#30363d"
                            }
                            onClicked: {
                                if (typeof backend !== "undefined" && backend) backend.open_pipelines_csv_file();
                            }
                        }
                    }

                    // Auto-Sync Pipeline Integration Bar
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 6
                        color: "#0d1117"
                        border.color: (typeof backend !== "undefined" && backend && backend.autoSyncEnabled) ? "#1f6feb" : "#21262d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                text: "⏱️ Auto-Sync Integration:"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: "#c9d1d9"
                            }

                            // Auto-Sync ON/OFF Toggle Pill
                            Rectangle {
                                implicitHeight: 22
                                implicitWidth: pipeAutoToggleRow.implicitWidth + 14
                                radius: 11
                                color: (typeof backend !== "undefined" && backend && backend.autoSyncEnabled) ? "#162b20" : "#21262d"
                                border.color: (typeof backend !== "undefined" && backend && backend.autoSyncEnabled) ? "#238636" : "#30363d"
                                border.width: 1

                                RowLayout {
                                    id: pipeAutoToggleRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: (typeof backend !== "undefined" && backend && backend.autoSyncEnabled) ? "#3fb950" : "#8b949e"
                                    }
                                    Text {
                                        text: (typeof backend !== "undefined" && backend && backend.autoSyncEnabled)
                                            ? ("Aktiv (" + backend.nextAutoSyncText + ")")
                                            : "Aus (Off)"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: (typeof backend !== "undefined" && backend && backend.autoSyncEnabled) ? "#3fb950" : "#8b949e"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof backend !== "undefined" && backend) {
                                            backend.setAutoSyncEnabled(!backend.autoSyncEnabled);
                                        }
                                    }
                                }
                            }

                            // Scope Selector: Full Sync (incl. Pipelines) vs. Pipelines Only
                            RowLayout {
                                spacing: 6
                                Text {
                                    text: "Modus:"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 10
                                    color: "#8b949e"
                                }

                                Repeater {
                                    model: [
                                        { scope: "all", label: "🔄 Komplett (inkl. Pipelines)" },
                                        { scope: "pipelines", label: "🔧 Nur Pipelines" }
                                    ]

                                    Rectangle {
                                        property bool isScopeActive: (typeof backend !== "undefined" && backend && backend.autoSyncScope === modelData.scope)
                                        implicitHeight: 22
                                        implicitWidth: scopePillTxt.implicitWidth + 14
                                        radius: 4
                                        color: isScopeActive ? "#192b45" : (scopePillMa.containsMouse ? "#21262d" : "#161b22")
                                        border.color: isScopeActive ? "#388bfd" : "#30363d"
                                        border.width: 1

                                        Text {
                                            id: scopePillTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: parent.isScopeActive ? Font.DemiBold : Font.Normal
                                            color: parent.isScopeActive ? "#58a6ff" : "#8b949e"
                                        }

                                        MouseArea {
                                            id: scopePillMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof backend !== "undefined" && backend) {
                                                    backend.setAutoSyncScope(modelData.scope);
                                                    if (!backend.autoSyncEnabled) {
                                                        backend.setAutoSyncEnabled(true);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: (typeof backend !== "undefined" && backend) ? backend.autoSyncStatusText : "Auto-sync: Off"
                                font.family: "Consolas, monospace"
                                font.pixelSize: 10
                                color: "#8b949e"
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Jenkins KPI Summary Cards Row
            // ==========================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Card 1: Overall Health & Weather
                Rectangle {
                    Layout.fillWidth: true
                    height: 74
                    radius: 8
                    color: "#161b22"
                    border.color: pipelinesTabRoot.sumVal("problem_count", 0) > 0 ? "#d29922" : "#238636"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        Text {
                            text: "GESAMT-WETTER & HEALTH"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#8b949e"
                        }
                        RowLayout {
                            spacing: 8
                            Text {
                                text: pipelinesTabRoot.sumVal("overall_weather_icon", "☀️") + " " + pipelinesTabRoot.sumVal("overall_health_pct", 100) + "%"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 20
                                font.weight: Font.Bold
                                color: pipelinesTabRoot.sumVal("problem_count", 0) > 0 ? "#e3b341" : "#3fb950"
                            }
                            Text {
                                text: "(" + pipelinesTabRoot.sumVal("total_builds", 0) + " Builds)"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#8b949e"
                            }
                        }
                    }
                }

                // Card 2: Total Pipelines
                Rectangle {
                    Layout.fillWidth: true
                    height: 74
                    radius: 8
                    color: pipelinesTabRoot.statusFilter === "all" ? "#192b45" : "#161b22"
                    border.color: pipelinesTabRoot.statusFilter === "all" ? "#388bfd" : "#30363d"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        Text {
                            text: "ALLE PIPELINES"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#8b949e"
                        }
                        Text {
                            text: "🔧 " + pipelinesTabRoot.sumVal("total_pipelines", 0)
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            color: "#f0f6fc"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pipelinesTabRoot.statusFilter = "all"
                    }
                }

                // Card 3: Favorites
                Rectangle {
                    Layout.fillWidth: true
                    height: 74
                    radius: 8
                    color: pipelinesTabRoot.statusFilter === "favorites" ? "#2b2212" : "#161b22"
                    border.color: pipelinesTabRoot.statusFilter === "favorites" ? "#e3b341" : (pipelinesTabRoot.favoriteCount > 0 ? "#9e6a03" : "#30363d")
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        Text {
                            text: "FAVORITEN (IMMER ZUERST)"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#8b949e"
                        }
                        Text {
                            text: "⭐ " + pipelinesTabRoot.favoriteCount
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            color: "#e3b341"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pipelinesTabRoot.statusFilter = (pipelinesTabRoot.statusFilter === "favorites" ? "all" : "favorites")
                    }
                }

                // Card 4: Passing / Sunny
                Rectangle {
                    Layout.fillWidth: true
                    height: 74
                    radius: 8
                    color: pipelinesTabRoot.statusFilter === "healthy" ? "#12261e" : "#161b22"
                    border.color: pipelinesTabRoot.statusFilter === "healthy" ? "#3fb950" : "#30363d"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        Text {
                            text: "STABIL / ERFOLGREICH"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#8b949e"
                        }
                        Text {
                            text: "🟢 " + pipelinesTabRoot.sumVal("healthy_count", 0)
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            color: "#3fb950"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pipelinesTabRoot.statusFilter = "healthy"
                    }
                }

                // Card 5: Unstable
                Rectangle {
                    Layout.fillWidth: true
                    height: 74
                    radius: 8
                    color: pipelinesTabRoot.statusFilter === "unstable" ? "#272115" : "#161b22"
                    border.color: pipelinesTabRoot.statusFilter === "unstable" ? "#d29922" : "#30363d"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        Text {
                            text: "INSTABIL (UNSTABLE)"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#8b949e"
                        }
                        Text {
                            text: "🟡 " + pipelinesTabRoot.sumVal("unstable_count", 0)
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            color: "#e3b341"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pipelinesTabRoot.statusFilter = "unstable"
                    }
                }

                // Card 6: Failed / Broken
                Rectangle {
                    Layout.fillWidth: true
                    height: 74
                    radius: 8
                    color: pipelinesTabRoot.statusFilter === "failed" ? "#2d1418" : "#161b22"
                    border.color: pipelinesTabRoot.sumVal("failed_count", 0) > 0 ? "#f85149" : "#30363d"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        Text {
                            text: "FEHLGESCHLAGEN (BROKEN)"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#8b949e"
                        }
                        Text {
                            text: "🔴 " + pipelinesTabRoot.sumVal("failed_count", 0)
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            color: "#f85149"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pipelinesTabRoot.statusFilter = "failed"
                    }
                }
            }

            // ==========================================
            // Filter, Search & View Mode Switcher Bar (Cards vs. List)
            // ==========================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { key: "all", label: "Alle (" + pipelinesTabRoot.sumVal("total_pipelines", 0) + ")" },
                            { key: "favorites", label: "⭐ Favoriten (" + pipelinesTabRoot.favoriteCount + ")" },
                            { key: "problems", label: "🚨 Nur Probleme (" + pipelinesTabRoot.sumVal("problem_count", 0) + ")" },
                            { key: "failed", label: "🔴 Broken (" + pipelinesTabRoot.sumVal("failed_count", 0) + ")" },
                            { key: "unstable", label: "🟡 Instabil (" + pipelinesTabRoot.sumVal("unstable_count", 0) + ")" },
                            { key: "healthy", label: "🟢 Sonnig / Stabil (" + pipelinesTabRoot.sumVal("healthy_count", 0) + ")" }
                        ]

                        Button {
                            text: modelData.label
                            checkable: true
                            checked: pipelinesTabRoot.statusFilter === modelData.key
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
                                implicitHeight: 30
                                implicitWidth: contentItem.implicitWidth + 18
                                radius: 6
                                color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                                border.color: parent.checked ? "#388bfd" : "#30363d"
                            }
                            onClicked: pipelinesTabRoot.statusFilter = modelData.key
                        }
                    }

                    TextField {
                        id: pipelineSearchField
                        width: 240
                        placeholderText: "🔍 Pipeline, Repo, Verursacher (Wer/Was)..."
                        text: pipelinesTabRoot.searchQuery
                        onTextChanged: pipelinesTabRoot.searchQuery = text
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#f0f6fc"
                        placeholderTextColor: "#8b949e"
                        background: Rectangle {
                            implicitHeight: 30
                            radius: 6
                            color: "#0d1117"
                            border.color: pipelineSearchField.activeFocus ? "#388bfd" : "#30363d"
                        }
                    }
                }

                // View Mode Toggle: Cards (default) vs. List
                Rectangle {
                    implicitHeight: 32
                    implicitWidth: viewModeRow.implicitWidth + 8
                    radius: 6
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    RowLayout {
                        id: viewModeRow
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            property bool activeMode: pipelinesTabRoot.viewMode === "cards"
                            implicitHeight: 24
                            implicitWidth: cardsBtnTxt.implicitWidth + 16
                            radius: 4
                            color: activeMode ? "#1f6feb" : (cardsBtnMa.containsMouse ? "#21262d" : "transparent")
                            border.color: activeMode ? "#388bfd" : "transparent"

                            Text {
                                id: cardsBtnTxt
                                anchors.centerIn: parent
                                text: "🃏 Karten"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: parent.activeMode ? Font.Bold : Font.Normal
                                color: parent.activeMode ? "#ffffff" : "#8b949e"
                            }

                            MouseArea {
                                id: cardsBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pipelinesTabRoot.setViewMode("cards")
                            }
                        }

                        Rectangle {
                            property bool activeMode: pipelinesTabRoot.viewMode === "list"
                            implicitHeight: 24
                            implicitWidth: listBtnTxt.implicitWidth + 16
                            radius: 4
                            color: activeMode ? "#1f6feb" : (listBtnMa.containsMouse ? "#21262d" : "transparent")
                            border.color: activeMode ? "#388bfd" : "transparent"

                            Text {
                                id: listBtnTxt
                                anchors.centerIn: parent
                                text: "📋 Liste"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                font.weight: parent.activeMode ? Font.Bold : Font.Normal
                                color: parent.activeMode ? "#ffffff" : "#8b949e"
                            }

                            MouseArea {
                                id: listBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pipelinesTabRoot.setViewMode("list")
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Empty State (Shared for Cards & List)
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                height: 96
                visible: (filteredPipelines ? filteredPipelines.length : 0) === 0
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: (allPipelines ? allPipelines.length : 0) === 0
                        ? "Noch keine Build-Pipelines im lokalen Cache gefunden. Klicke oben auf '🔄 Sync Pipelines' oder '⚡ Sync & Report'."
                        : "Keine Pipelines für den gewählten Filter gefunden."
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    color: "#8b949e"
                }
            }

            // ==========================================
            // VIEW MODE 1: KARTEN-DARSTELLUNG (Cards Grid - Default)
            // ==========================================
            GridLayout {
                id: cardsGrid
                Layout.fillWidth: true
                visible: pipelinesTabRoot.viewMode === "cards" && (filteredPipelines ? filteredPipelines.length : 0) > 0
                columns: parent.width > 1320 ? 3 : (parent.width > 740 ? 2 : 1)
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: filteredPipelines

                    Rectangle {
                        id: pipeCard
                        property bool isFav: pipelinesTabRoot.isPipeFav(modelData)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 340
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: cardInnerCol.implicitHeight + 24
                        radius: 8
                        color: modelData.has_problem ? "#1a1316" : (isFav ? "#161c26" : "#161b22")
                        border.color: isFav
                            ? "#e3b341"
                            : (modelData.has_problem ? (modelData.status_key === "failed" ? "#f85149" : "#d29922") : "#30363d")
                        border.width: isFav ? 2 : 1

                        ColumnLayout {
                            id: cardInnerCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8

                            // Row 1: Favorite Star, Status Ball, Clickable Pipeline Name & Weather Badge
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // Favorite Star Toggle Button
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 5
                                    color: favCardMa.containsMouse ? "#21262d" : (pipeCard.isFav ? "#2b2212" : "transparent")
                                    border.color: pipeCard.isFav ? "#e3b341" : (favCardMa.containsMouse ? "#30363d" : "transparent")
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: pipeCard.isFav ? "⭐" : "☆"
                                        font.pixelSize: 14
                                        color: pipeCard.isFav ? "#e3b341" : "#8b949e"
                                    }

                                    MouseArea {
                                        id: favCardMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pipelinesTabRoot.togglePipeFav(modelData)
                                    }
                                    ToolTip.visible: favCardMa.containsMouse
                                    ToolTip.text: pipeCard.isFav
                                        ? "Aus Favoriten entfernen"
                                        : "Als Favorit markieren (wird immer zuerst angezeigt)"
                                }

                                Text {
                                    text: modelData.status_ball || "⚪"
                                    font.pixelSize: 15
                                }

                                // Clickable Pipeline Name -> Opens Pipeline in TFS
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: cardPipeTitle.implicitHeight

                                    Text {
                                        id: cardPipeTitle
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (modelData.name || "Unknown Pipeline") + " ↗"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        font.underline: cardTitleMa.containsMouse
                                        color: cardTitleMa.containsMouse ? "#58a6ff" : "#f0f6fc"
                                        elide: Text.ElideRight
                                    }

                                    MouseArea {
                                        id: cardTitleMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pipelinesTabRoot.openTfsPipeline(modelData)
                                    }
                                    ToolTip.visible: cardTitleMa.containsMouse
                                    ToolTip.text: "Pipeline in TFS öffnen: " + (modelData.web_url || modelData.url || modelData.name || "")
                                }

                                // Weather Pill
                                Rectangle {
                                    height: 22
                                    implicitWidth: cardWeatherTxt.implicitWidth + 12
                                    radius: 11
                                    color: "#0d1117"
                                    border.color: (modelData.weather_score !== undefined && modelData.weather_score < 60) ? "#f85149" : ((modelData.weather_score !== undefined && modelData.weather_score < 80) ? "#d29922" : "#238636")
                                    border.width: 1

                                    Text {
                                        id: cardWeatherTxt
                                        anchors.centerIn: parent
                                        text: (modelData.weather_icon || "☀️") + " " + (modelData.weather_score !== undefined ? modelData.weather_score : 100) + "%"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: (modelData.weather_score !== undefined && modelData.weather_score < 60) ? "#ff7b72" : ((modelData.weather_score !== undefined && modelData.weather_score < 80) ? "#e3b341" : "#3fb950")
                                    }
                                }
                            }

                            // Row 2: Repo @ Branch, Failure Streak & Last 5 Runs (Clickable Build Jobs)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    height: 20
                                    implicitWidth: Math.min(200, cardRepoTxt.implicitWidth + 12)
                                    radius: 4
                                    color: cardRepoMa.containsMouse ? "#30363d" : "#21262d"
                                    border.color: "#30363d"

                                    Text {
                                        id: cardRepoTxt
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        verticalAlignment: Text.AlignVCenter
                                        text: (modelData.repo_name || "-") + " @ " + (modelData.last_branch || "-")
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 10
                                        color: "#58a6ff"
                                        elide: Text.ElideRight
                                    }

                                    MouseArea {
                                        id: cardRepoMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: modelData.repo_url ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (modelData.repo_url) pipelinesTabRoot.openExternalUrl(modelData.repo_url);
                                        }
                                    }
                                    ToolTip.visible: cardRepoMa.containsMouse && !!modelData.repo_url
                                    ToolTip.text: "Repository in TFS öffnen: " + (modelData.repo_url || "")
                                }

                                Rectangle {
                                    visible: (modelData.consecutive_failures || 0) > 0
                                    height: 20
                                    implicitWidth: cardStreakTxt.implicitWidth + 10
                                    radius: 4
                                    color: "#2d1418"
                                    border.color: "#f85149"

                                    Text {
                                        id: cardStreakTxt
                                        anchors.centerIn: parent
                                        text: modelData.consecutive_failures + "x 🔴 (#" + (modelData.broken_since_build || "-") + ")"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: "#ff7b72"
                                    }

                                    MouseArea {
                                        id: cardStreakMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pipelinesTabRoot.openTfsBuild(modelData.broken_since_id, modelData.broken_since_url)
                                    }
                                    ToolTip.visible: cardStreakMa.containsMouse
                                    ToolTip.text: "Ersten fehlgeschlagenen Build #" + (modelData.broken_since_build || "") + " in TFS öffnen"
                                }

                                Item { Layout.fillWidth: true }

                                // Interactive Last 5 Build Jobs
                                RowLayout {
                                    spacing: 3
                                    Text {
                                        text: "Letzte 5:"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#8b949e"
                                    }
                                    Repeater {
                                        model: (modelData.last_5_runs && modelData.last_5_runs.length > 0) ? modelData.last_5_runs : []
                                        Rectangle {
                                            width: 20
                                            height: 20
                                            radius: 4
                                            color: runBallMa.containsMouse ? "#30363d" : "#0d1117"
                                            border.color: runBallMa.containsMouse ? "#58a6ff" : "#21262d"

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.status_ball || "⚪"
                                                font.pixelSize: 10
                                            }

                                            MouseArea {
                                                id: runBallMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: pipelinesTabRoot.openTfsBuild(modelData.build_id, modelData.web_url || modelData.url)
                                            }
                                            ToolTip.visible: runBallMa.containsMouse
                                            ToolTip.text: "Build #" + (modelData.build_number || "") + " (" + (modelData.status_label || "") + ")\nDatum: " + (modelData.date || "-") + " · Dauer: " + (modelData.duration_str || "-") + "\nKlicken zum Öffnen in TFS"
                                        }
                                    }
                                    Text {
                                        visible: !modelData.last_5_runs || modelData.last_5_runs.length === 0
                                        text: modelData.last_5_balls || "⚪"
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            // Row 3: Compact Metrics Grid (Latest Job, Last Success, Last Failure, Duration) with TFS Job Links
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: cardMetricsRow.implicitHeight + 12
                                color: "#0d1117"
                                radius: 6
                                border.color: "#21262d"

                                RowLayout {
                                    id: cardMetricsRow
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 8

                                    // Latest Build Job
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: "LETZTER JOB"
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                            color: "#8b949e"
                                        }
                                        Text {
                                            text: (modelData.last_build_number && modelData.last_build_number !== "-")
                                                ? ("#" + modelData.last_build_number + " (" + (modelData.last_duration_str || "-") + ") ↗")
                                                : "-"
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            font.underline: latestJobMa.containsMouse
                                            color: latestJobMa.containsMouse ? "#79c0ff" : "#58a6ff"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true

                                            MouseArea {
                                                id: latestJobMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: !!(modelData.last_build_id || modelData.last_build_url)
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: pipelinesTabRoot.openTfsBuild(modelData.last_build_id, modelData.last_build_url)
                                            }
                                        }
                                    }

                                    // Last Success Job
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: "LAST SUCCESS"
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                            color: "#8b949e"
                                        }
                                        Text {
                                            text: (modelData.last_success_build ? ("#" + modelData.last_success_build + " ↗") : "Nie")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.underline: lastSuccMa.containsMouse && !!modelData.last_success_build
                                            color: modelData.last_success_build ? "#3fb950" : "#6e7681"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true

                                            MouseArea {
                                                id: lastSuccMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: !!(modelData.last_success_id || modelData.last_success_url)
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: pipelinesTabRoot.openTfsBuild(modelData.last_success_id, modelData.last_success_url)
                                            }
                                            ToolTip.visible: lastSuccMa.containsMouse && !!modelData.last_success_display
                                            ToolTip.text: "Letzter erfolgreicher Job: " + (modelData.last_success_display || "")
                                        }
                                    }

                                    // Last Failure Job
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: "LAST FAILURE"
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                            color: "#8b949e"
                                        }
                                        Text {
                                            text: (modelData.last_failure_build ? ("#" + modelData.last_failure_build + " ↗") : "Nie")
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.underline: lastFailMa.containsMouse && !!modelData.last_failure_build
                                            color: modelData.last_failure_build ? "#ff7b72" : "#6e7681"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true

                                            MouseArea {
                                                id: lastFailMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: !!(modelData.last_failure_id || modelData.last_failure_url)
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: pipelinesTabRoot.openTfsBuild(modelData.last_failure_id, modelData.last_failure_url)
                                            }
                                            ToolTip.visible: lastFailMa.containsMouse && !!modelData.last_failure_display
                                            ToolTip.text: "Letzter fehlgeschlagener Job: " + (modelData.last_failure_display || "")
                                        }
                                    }
                                }
                            }

                            // Row 4: Culprit Analysis (Wer & Was) or Healthy Status Box
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: cardCulpritCol.implicitHeight + 12
                                color: modelData.has_problem ? "#1c1214" : "#0f1d17"
                                radius: 6
                                border.color: modelData.has_problem ? "#6e2226" : "#1f4429"
                                border.width: 1

                                ColumnLayout {
                                    id: cardCulpritCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 6
                                    spacing: 3

                                    Text {
                                        visible: modelData.has_problem
                                        text: "👤 Wer: " + (modelData.culprit_who || "Unbekannt")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: "#e3b341"
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        visible: modelData.has_problem
                                        text: "🔍 Was: " + (modelData.culprit_what || "-")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: "#f0f6fc"
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: modelData.has_problem
                                            ? ("💡 " + (modelData.hint_text || ""))
                                            : ("✅ " + (modelData.weather_label || "Pipeline läuft stabil."))
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: modelData.has_problem ? "#ff7b72" : "#3fb950"
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // Row 5: Direct TFS Action Links Footer (Pipeline & Build Jobs)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // Link 1: Open Pipeline in TFS
                                Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: cardPipeLinkTxt.implicitWidth + 14
                                    radius: 4
                                    color: cardPipeLinkMa.containsMouse ? "#1f6feb" : "#21262d"
                                    border.color: cardPipeLinkMa.containsMouse ? "#58a6ff" : "#30363d"
                                    border.width: 1

                                    Text {
                                        id: cardPipeLinkTxt
                                        anchors.centerIn: parent
                                        text: "🔗 Pipeline in TFS"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: cardPipeLinkMa.containsMouse ? "#ffffff" : "#58a6ff"
                                    }

                                    MouseArea {
                                        id: cardPipeLinkMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pipelinesTabRoot.openTfsPipeline(modelData)
                                    }
                                    ToolTip.visible: cardPipeLinkMa.containsMouse
                                    ToolTip.text: modelData.web_url || modelData.url || "Pipeline in TFS öffnen"
                                }

                                // Link 2: Open Latest Build Job in TFS
                                Rectangle {
                                    visible: !!(modelData.last_build_id || modelData.last_build_url)
                                    implicitHeight: 24
                                    implicitWidth: cardJobLinkTxt.implicitWidth + 14
                                    radius: 4
                                    color: cardJobLinkMa.containsMouse ? "#30363d" : "#161b22"
                                    border.color: cardJobLinkMa.containsMouse ? "#58a6ff" : "#30363d"
                                    border.width: 1

                                    Text {
                                        id: cardJobLinkTxt
                                        anchors.centerIn: parent
                                        text: "🔧 Job #" + (modelData.last_build_number || "-") + " in TFS"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: "#c9d1d9"
                                    }

                                    MouseArea {
                                        id: cardJobLinkMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pipelinesTabRoot.openTfsBuild(modelData.last_build_id, modelData.last_build_url)
                                    }
                                    ToolTip.visible: cardJobLinkMa.containsMouse
                                    ToolTip.text: modelData.last_build_url || "Letzten Pipeline-Job in TFS öffnen"
                                }

                                // Link 3: Open Failed Build Job in TFS (if different or broken)
                                Rectangle {
                                    visible: modelData.has_problem && !!(modelData.last_failure_id || modelData.last_failure_url) && (modelData.last_failure_id !== modelData.last_build_id)
                                    implicitHeight: 24
                                    implicitWidth: cardFailJobTxt.implicitWidth + 14
                                    radius: 4
                                    color: cardFailJobMa.containsMouse ? "#490202" : "#2d1418"
                                    border.color: "#f85149"
                                    border.width: 1

                                    Text {
                                        id: cardFailJobTxt
                                        anchors.centerIn: parent
                                        text: "🔴 Fehler-Job #" + (modelData.last_failure_build || "-")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: "#ff7b72"
                                    }

                                    MouseArea {
                                        id: cardFailJobMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pipelinesTabRoot.openTfsBuild(modelData.last_failure_id, modelData.last_failure_url)
                                    }
                                    ToolTip.visible: cardFailJobMa.containsMouse
                                    ToolTip.text: modelData.last_failure_url || "Fehlgeschlagenen Job in TFS öffnen"
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // VIEW MODE 2: LISTEN-DARSTELLUNG (Classic Jenkins Table)
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                visible: pipelinesTabRoot.viewMode === "list" && (filteredPipelines ? filteredPipelines.length : 0) > 0
                implicitHeight: jenkinsTableCol.implicitHeight + 24
                color: "#161b22"
                radius: 8
                border.color: "#30363d"
                border.width: 1

                ColumnLayout {
                    id: jenkinsTableCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 6

                    // Table Header (★ | S | W | Letzte 5 | Pipeline / Job & Branch | Last Success | Last Failure | Duration | Verursacher / Hinweis | TFS Links)
                    Rectangle {
                        Layout.fillWidth: true
                        height: 32
                        color: "#21262d"
                        radius: 4

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text { text: "★"; Layout.preferredWidth: 26; font.pixelSize: 11; font.weight: Font.Bold; color: "#e3b341" }
                            Text { text: "S"; Layout.preferredWidth: 26; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                            Text { text: "W (Health)"; Layout.preferredWidth: 80; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                            Text { text: "Letzte 5"; Layout.preferredWidth: 105; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                            Text { text: "Pipeline / Job & Branch"; Layout.preferredWidth: 200; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                            Text { text: "Last Success"; Layout.preferredWidth: 125; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                            Text { text: "Last Failure"; Layout.preferredWidth: 125; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                            Text { text: "Duration"; Layout.preferredWidth: 65; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                            Text { text: "Verursacher / Hinweis (Wer & Was)"; Layout.fillWidth: true; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                            Text { text: "TFS Links"; Layout.preferredWidth: 150; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                        }
                    }

                    // Rows
                    Repeater {
                        model: filteredPipelines

                        Rectangle {
                            id: listRowRect
                            property bool isFav: pipelinesTabRoot.isPipeFav(modelData)
                            Layout.fillWidth: true
                            implicitHeight: Math.max(46, rowLayout.implicitHeight + 14)
                            color: modelData.has_problem ? "#1c1417" : (isFav ? "#161c26" : (index % 2 === 0 ? "#0d1117" : "#161b22"))
                            radius: 4
                            border.color: isFav ? "#e3b341" : (modelData.has_problem ? (modelData.status_key === "failed" ? "#6e2226" : "#5a4315") : "#21262d")
                            border.width: 1

                            RowLayout {
                                id: rowLayout
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                                spacing: 8

                                // Favorite Star Toggle
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    height: 24
                                    radius: 4
                                    color: listFavMa.containsMouse ? "#21262d" : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: listRowRect.isFav ? "⭐" : "☆"
                                        font.pixelSize: 13
                                        color: listRowRect.isFav ? "#e3b341" : "#8b949e"
                                    }

                                    MouseArea {
                                        id: listFavMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pipelinesTabRoot.togglePipeFav(modelData)
                                    }
                                    ToolTip.visible: listFavMa.containsMouse
                                    ToolTip.text: listRowRect.isFav ? "Aus Favoriten entfernen" : "Als Favorit markieren (immer zuerst)"
                                }

                                // S (Status Ball)
                                Text {
                                    Layout.preferredWidth: 26
                                    text: modelData.status_ball || "⚪"
                                    font.pixelSize: 15
                                }

                                // W (Weather Icon + Score)
                                Text {
                                    Layout.preferredWidth: 80
                                    text: (modelData.weather_icon || "☀️") + " " + (modelData.weather_score !== undefined ? modelData.weather_score : 100) + "%"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: (modelData.weather_score !== undefined && modelData.weather_score < 60) ? "#f85149" : ((modelData.weather_score !== undefined && modelData.weather_score < 80) ? "#e3b341" : "#3fb950")
                                }

                                // Last 5 Balls (Clickable to open individual build jobs in TFS)
                                RowLayout {
                                    Layout.preferredWidth: 105
                                    spacing: 2
                                    Repeater {
                                        model: (modelData.last_5_runs && modelData.last_5_runs.length > 0) ? modelData.last_5_runs : []
                                        Rectangle {
                                            width: 18
                                            height: 18
                                            radius: 3
                                            color: listRunBallMa.containsMouse ? "#30363d" : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.status_ball || "⚪"
                                                font.pixelSize: 10
                                            }
                                            MouseArea {
                                                id: listRunBallMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: pipelinesTabRoot.openTfsBuild(modelData.build_id, modelData.web_url || modelData.url)
                                            }
                                            ToolTip.visible: listRunBallMa.containsMouse
                                            ToolTip.text: "Job #" + (modelData.build_number || "") + " in TFS öffnen"
                                        }
                                    }
                                    Text {
                                        visible: !modelData.last_5_runs || modelData.last_5_runs.length === 0
                                        text: modelData.last_5_balls || "-"
                                        font.pixelSize: 11
                                        color: "#c9d1d9"
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                // Pipeline Name + Repo & Branch (Clickable TFS Links)
                                ColumnLayout {
                                    Layout.preferredWidth: 200
                                    spacing: 2
                                    Text {
                                        text: (modelData.name || "Unknown") + " ↗"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        font.underline: listPipeNameMa.containsMouse
                                        color: listPipeNameMa.containsMouse ? "#58a6ff" : "#f0f6fc"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true

                                        MouseArea {
                                            id: listPipeNameMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: pipelinesTabRoot.openTfsPipeline(modelData)
                                        }
                                    }
                                    Text {
                                        text: (modelData.repo_name || "-") + " (" + (modelData.last_branch || "-") + ")"
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 10
                                        color: "#58a6ff"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Last Success (Clickable Build Link)
                                Text {
                                    Layout.preferredWidth: 125
                                    text: modelData.last_success_display || "Nie"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.underline: listSuccMa.containsMouse && !!modelData.last_success_build
                                    color: "#3fb950"
                                    elide: Text.ElideRight

                                    MouseArea {
                                        id: listSuccMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: !!(modelData.last_success_id || modelData.last_success_url)
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: pipelinesTabRoot.openTfsBuild(modelData.last_success_id, modelData.last_success_url)
                                    }
                                }

                                // Last Failure (Clickable Build Link)
                                Text {
                                    Layout.preferredWidth: 125
                                    text: modelData.last_failure_display || "Nie"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 11
                                    font.underline: listFailMa.containsMouse && !!modelData.last_failure_build
                                    color: (modelData.last_failure_build && modelData.last_failure_build !== "-") ? "#ff7b72" : "#8b949e"
                                    elide: Text.ElideRight

                                    MouseArea {
                                        id: listFailMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: !!(modelData.last_failure_id || modelData.last_failure_url)
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: pipelinesTabRoot.openTfsBuild(modelData.last_failure_id, modelData.last_failure_url)
                                    }
                                }

                                // Last Duration
                                Text {
                                    Layout.preferredWidth: 65
                                    text: modelData.last_duration_str || "-"
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 11
                                    color: "#c9d1d9"
                                }

                                // Verursacher / Hinweis (Wer & Was)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        visible: modelData.has_problem
                                        text: "👤 Wer: " + (modelData.culprit_who || "-") + "  •  🔍 Was: " + (modelData.culprit_what || "-")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#ff7b72"
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: modelData.hint_text || "✅ Stabil"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        color: modelData.has_problem ? "#e3b341" : "#8b949e"
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                // TFS Quick Action Links (Pipeline & Latest Job)
                                RowLayout {
                                    Layout.preferredWidth: 150
                                    spacing: 4

                                    Rectangle {
                                        implicitHeight: 22
                                        implicitWidth: listPipeBtnTxt.implicitWidth + 10
                                        radius: 4
                                        color: listPipeBtnMa.containsMouse ? "#1f6feb" : "#21262d"
                                        border.color: listPipeBtnMa.containsMouse ? "#58a6ff" : "#30363d"

                                        Text {
                                            id: listPipeBtnTxt
                                            anchors.centerIn: parent
                                            text: "🔗 Pipeline"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            color: listPipeBtnMa.containsMouse ? "#ffffff" : "#58a6ff"
                                        }

                                        MouseArea {
                                            id: listPipeBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: pipelinesTabRoot.openTfsPipeline(modelData)
                                        }
                                        ToolTip.visible: listPipeBtnMa.containsMouse
                                        ToolTip.text: "Pipeline in TFS öffnen"
                                    }

                                    Rectangle {
                                        visible: !!(modelData.last_build_id || modelData.last_build_url)
                                        implicitHeight: 22
                                        implicitWidth: listJobBtnTxt.implicitWidth + 10
                                        radius: 4
                                        color: listJobBtnMa.containsMouse ? "#30363d" : "#161b22"
                                        border.color: listJobBtnMa.containsMouse ? "#58a6ff" : "#30363d"

                                        Text {
                                            id: listJobBtnTxt
                                            anchors.centerIn: parent
                                            text: "🔧 #" + (modelData.last_build_number || "Job")
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 10
                                            color: "#c9d1d9"
                                        }

                                        MouseArea {
                                            id: listJobBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: pipelinesTabRoot.openTfsBuild(modelData.last_build_id, modelData.last_build_url)
                                        }
                                        ToolTip.visible: listJobBtnMa.containsMouse
                                        ToolTip.text: "Letzten Pipeline-Job #" + (modelData.last_build_number || "") + " in TFS öffnen"
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Detailed Problem-Analyse Section (Wer / Was ist der Verursacher?)
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                visible: (problemPipelines ? problemPipelines.length : 0) > 0
                implicitHeight: culpritCol.implicitHeight + 28
                color: "#1c1214"
                radius: 8
                border.color: "#f85149"
                border.width: 1

                ColumnLayout {
                    id: culpritCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "🚨 Detail-Analyse aller Problem-Pipelines: Wer / Was könnte der Verursacher sein? (" + (problemPipelines ? problemPipelines.length : 0) + ")"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: "#ff7b72"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Hinweise auf Commit-Autoren, Pull Requests und fehlgeschlagene Build-Tasks"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                        }
                    }

                    Repeater {
                        model: problemPipelines

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: probItemCol.implicitHeight + 20
                            color: "#161b22"
                            radius: 6
                            border.color: modelData.status_key === "failed" ? "#f85149" : "#d29922"
                            border.width: 1

                            ColumnLayout {
                                id: probItemCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 6

                                // Row 1: Favorite, Pipeline Title (TFS Link), Weather & Failure Streak (TFS Job Link)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: pipelinesTabRoot.isPipeFav(modelData) ? "⭐" : "☆"
                                        font.pixelSize: 14
                                        color: pipelinesTabRoot.isPipeFav(modelData) ? "#e3b341" : "#8b949e"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: pipelinesTabRoot.togglePipeFav(modelData)
                                        }
                                    }

                                    Text {
                                        text: (modelData.status_ball || "🔴") + " " + (modelData.weather_icon || "⛈️")
                                        font.pixelSize: 15
                                    }

                                    Text {
                                        text: (modelData.name || "Unknown Pipeline") + " ↗"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        font.underline: probPipeMa.containsMouse
                                        color: probPipeMa.containsMouse ? "#58a6ff" : "#f0f6fc"

                                        MouseArea {
                                            id: probPipeMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: pipelinesTabRoot.openTfsPipeline(modelData)
                                        }
                                    }

                                    Rectangle {
                                        height: 20
                                        width: repoBranchTxt.implicitWidth + 12
                                        radius: 4
                                        color: "#21262d"
                                        border.color: "#30363d"
                                        Text {
                                            id: repoBranchTxt
                                            anchors.centerIn: parent
                                            text: (modelData.repo_name || "-") + " @ " + (modelData.last_branch || "-")
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 10
                                            color: "#58a6ff"
                                        }
                                    }

                                    Rectangle {
                                        visible: (modelData.consecutive_failures || 0) > 0
                                        height: 20
                                        width: streakTxt.implicitWidth + 12
                                        radius: 4
                                        color: "#2d1418"
                                        border.color: "#f85149"
                                        Text {
                                            id: streakTxt
                                            anchors.centerIn: parent
                                            text: modelData.consecutive_failures + "x fehlgeschlagen seit #" + (modelData.broken_since_build || "-") + " ↗"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: "#ff7b72"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: pipelinesTabRoot.openTfsBuild(modelData.broken_since_id, modelData.broken_since_url)
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "Letzte 5: " + (modelData.last_5_balls || "-") + " (" + (modelData.weather_score !== undefined ? modelData.weather_score : 0) + "%)"
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#8b949e"
                                    }
                                }

                                // Row 2: WER & WAS boxes
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        implicitHeight: whoBoxCol.implicitHeight + 12
                                        color: "#0d1117"
                                        radius: 4
                                        border.color: "#30363d"

                                        ColumnLayout {
                                            id: whoBoxCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 6
                                            spacing: 2

                                            Text {
                                                text: "👤 WER (MÖGLICHER VERURSACHER)"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#e3b341"
                                            }
                                            Text {
                                                text: modelData.culprit_who || "Unbekannt"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                color: "#f0f6fc"
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                visible: !!(modelData.suspects && modelData.suspects.length > 1)
                                                text: "Beteiligt seit letztem grünen Build: " + (modelData.suspects_str || "")
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#8b949e"
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        implicitHeight: whatBoxCol.implicitHeight + 12
                                        color: "#0d1117"
                                        radius: 4
                                        border.color: "#30363d"

                                        ColumnLayout {
                                            id: whatBoxCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 6
                                            spacing: 2

                                            Text {
                                                text: "🔍 WAS (FEHLER / COMMIT / STEP)"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#58a6ff"
                                            }
                                            Text {
                                                text: modelData.culprit_what || "-"
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                color: "#f0f6fc"
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }

                                // Row 3: Einfacher Hinweis (Actionable Hint)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: hintTxt.implicitHeight + 10
                                    color: "#192b45"
                                    radius: 4
                                    border.color: "#388bfd"

                                    Text {
                                        id: hintTxt
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: 8
                                        text: "💡 Hinweis: " + (modelData.hint_text || "")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 11
                                        color: "#e6edf3"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
