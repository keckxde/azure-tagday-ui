import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

Item {
    id: pipelinesTabRoot
    property var root: null
    property string statusFilter: "all" // "all", "problems", "failed", "unstable", "healthy"
    property string searchQuery: ""

    Layout.fillWidth: true
    Layout.fillHeight: true

    readonly property var pipelinesSummary: (typeof backend !== "undefined" && backend && backend.pipelinesData && backend.pipelinesData.summary) ? backend.pipelinesData.summary : ({
        "total_pipelines": 0,
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

    readonly property var filteredPipelines: {
        var list = allPipelines || [];
        var res = [];
        var q = (searchQuery || "").trim().toLowerCase();
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (!p) continue;
            if (statusFilter === "problems" && !p.has_problem) continue;
            if (statusFilter === "failed" && p.status_key !== "failed") continue;
            if (statusFilter === "unstable" && p.status_key !== "unstable") continue;
            if (statusFilter === "healthy" && p.status_key !== "success") continue;

            if (q.length > 0) {
                var hay = ((p.name || "") + " " + (p.repo_name || "") + " " + (p.last_branch || "") + " " + (p.culprit_who || "") + " " + (p.culprit_what || "") + " " + (p.hint_text || "") + " " + (p.suspects_str || "")).toLowerCase();
                if (hay.indexOf(q) < 0) continue;
            }
            res.push(p);
        }
        return res;
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
        // Top Header & Actions Bar
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
                            text: "Klassische Jenkins-Ansicht (Status-Kugel S, Wetter-Stabilität W, Letzte 5 Läufe) inkl. automatischer Verursacher-Hinweise (Wer & Was)"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            color: "#8b949e"
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "⚡ Sync & Generate Report"
                        enabled: backend ? !backend.isBusy : false
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
                            implicitWidth: 185
                            radius: 6
                            color: parent.enabled ? (parent.hovered ? "#2ea043" : "#238636") : "#30363d"
                        }
                        onClicked: {
                            if (backend) backend.generate_pipelines_report_async();
                        }
                    }

                    Button {
                        text: "📑 Open BUILD_PIPELINES.md"
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
                            implicitWidth: 185
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (backend) backend.open_pipelines_report_file();
                        }
                    }

                    Button {
                        text: "📊 Open CSV"
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
                            implicitWidth: 105
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                        }
                        onClicked: {
                            if (backend) backend.open_pipelines_csv_file();
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

            // Card 3: Passing / Sunny
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

            // Card 4: Unstable
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

            // Card 5: Failed / Broken
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
        // Section 1: Problem-Analyse (Wer / Was ist der Verursacher?)
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
                        text: "🚨 Problem-Analyse: Wer / Was könnte der Verursacher sein? (" + (problemPipelines ? problemPipelines.length : 0) + ")"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: "#ff7b72"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Einfache Hinweise auf Commit-Autoren, Pull Requests und fehlgeschlagene Build-Tasks"
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

                            // Row 1: Pipeline Title, Weather & Failure Streak
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: (modelData.status_ball || "🔴") + " " + (modelData.weather_icon || "⛈️")
                                    font.pixelSize: 15
                                }

                                Text {
                                    text: modelData.name || "Unknown Pipeline"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
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
                                        text: modelData.consecutive_failures + "x fehlgeschlagen seit #" + (modelData.broken_since_build || "-")
                                        font.family: "Segoe UI, sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#ff7b72"
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
                                            visible: (modelData.suspects && modelData.suspects.length > 1)
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

        // ==========================================
        // Filter & Search Bar for Jenkins Table
        // ==========================================
        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { key: "all", label: "Alle (" + pipelinesTabRoot.sumVal("total_pipelines", 0) + ")" },
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
                        implicitHeight: 28
                        implicitWidth: contentItem.implicitWidth + 20
                        radius: 6
                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#161b22")
                        border.color: parent.checked ? "#388bfd" : "#30363d"
                    }
                    onClicked: pipelinesTabRoot.statusFilter = modelData.key
                }
            }

            TextField {
                id: pipelineSearchField
                width: 250
                placeholderText: "🔍 Pipeline, Repo, Verursacher (Wer/Was)..."
                text: pipelinesTabRoot.searchQuery
                onTextChanged: pipelinesTabRoot.searchQuery = text
                font.family: "Segoe UI, sans-serif"
                font.pixelSize: 12
                color: "#f0f6fc"
                placeholderTextColor: "#8b949e"
                background: Rectangle {
                    implicitHeight: 28
                    radius: 6
                    color: "#0d1117"
                    border.color: pipelineSearchField.activeFocus ? "#388bfd" : "#30363d"
                }
            }
        }

        // ==========================================
        // Section 2: Classic Jenkins Build Monitor Table
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
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

                // Table Header (Classic Jenkins Columns: S | W | Letzte 5 | Job/Pipeline | Last Success | Last Failure | Last Duration | Verursacher / Hinweis)
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

                        Text { text: "S"; Layout.preferredWidth: 28; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                        Text { text: "W (Health)"; Layout.preferredWidth: 85; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                        Text { text: "Letzte 5"; Layout.preferredWidth: 95; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                        Text { text: "Pipeline / Job & Branch"; Layout.preferredWidth: 210; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                        Text { text: "Last Success"; Layout.preferredWidth: 130; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                        Text { text: "Last Failure"; Layout.preferredWidth: 130; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                        Text { text: "Duration"; Layout.preferredWidth: 70; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                        Text { text: "Verursacher / Hinweis (Wer & Was)"; Layout.fillWidth: true; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                    }
                }

                // Empty State
                Rectangle {
                    Layout.fillWidth: true
                    height: 90
                    visible: (filteredPipelines ? filteredPipelines.length : 0) === 0
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: (allPipelines ? allPipelines.length : 0) === 0
                            ? "Noch keine Build-Pipelines im lokalen Cache gefunden. Klicke oben auf '⚡ Sync & Generate Report'."
                            : "Keine Pipelines für den gewählten Filter gefunden."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#8b949e"
                    }
                }

                // Rows
                Repeater {
                    model: filteredPipelines

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Math.max(44, rowLayout.implicitHeight + 14)
                        color: modelData.has_problem ? "#1c1417" : (index % 2 === 0 ? "#0d1117" : "#161b22")
                        radius: 4
                        border.color: modelData.has_problem ? (modelData.status_key === "failed" ? "#6e2226" : "#5a4315") : "#21262d"
                        border.width: 1

                        RowLayout {
                            id: rowLayout
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            spacing: 8

                            // S (Status Ball)
                            Text {
                                Layout.preferredWidth: 28
                                text: modelData.status_ball || "⚪"
                                font.pixelSize: 15
                            }

                            // W (Weather Icon + Score)
                            Text {
                                Layout.preferredWidth: 85
                                text: (modelData.weather_icon || "☀️") + " " + (modelData.weather_score !== undefined ? modelData.weather_score : 100) + "%"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: (modelData.weather_score !== undefined && modelData.weather_score < 60) ? "#f85149" : ((modelData.weather_score !== undefined && modelData.weather_score < 80) ? "#e3b341" : "#3fb950")
                            }

                            // Last 5 Balls
                            Text {
                                Layout.preferredWidth: 95
                                text: modelData.last_5_balls || "-"
                                font.pixelSize: 11
                                color: "#c9d1d9"
                                elide: Text.ElideRight
                            }

                            // Pipeline Name + Repo & Branch
                            ColumnLayout {
                                Layout.preferredWidth: 210
                                spacing: 2
                                Text {
                                    text: modelData.name || "Unknown"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
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

                            // Last Success
                            Text {
                                Layout.preferredWidth: 130
                                text: modelData.last_success_display || "Nie"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: "#3fb950"
                                elide: Text.ElideRight
                            }

                            // Last Failure
                            Text {
                                Layout.preferredWidth: 130
                                text: modelData.last_failure_display || "Nie"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 11
                                color: (modelData.last_failure_build && modelData.last_failure_build !== "-") ? "#ff7b72" : "#8b949e"
                                elide: Text.ElideRight
                            }

                            // Last Duration
                            Text {
                                Layout.preferredWidth: 70
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
                        }
                    }
                }
            }
        }
        }
    }
}

