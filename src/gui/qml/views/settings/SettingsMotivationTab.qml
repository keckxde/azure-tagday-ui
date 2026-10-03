import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: motivationTabRoot
    spacing: 20
    Layout.fillWidth: true

    // ==========================================
    // TEAM MOTIVATION & SCORE SYSTEM SETTINGS
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: motivCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: motivCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 18

            // Header & Intro
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 44
                    height: 44
                    radius: 8
                    color: "#272115"
                    border.color: "#d29922"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "🏆"
                        font.pixelSize: 22
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: "Team Motivation & Score Engine Configuration"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Configure points awarded or deducted for PRs, commits, work item deliveries, CI builds, streaks, and hygiene penalties."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#8b949e"
                    }
                }

                // Jump to Motivation View
                Button {
                    text: "🏆 View Hall of Fame"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#f0883e"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 34
                        implicitWidth: 160
                        radius: 6
                        color: parent.hovered ? "#2d2218" : "#1f1a14"
                        border.color: "#f0883e"
                        border.width: 1
                    }
                    onClicked: {
                        if (typeof window !== "undefined" && typeof window.openTeamMotivationPage === "function") {
                            window.openTeamMotivationPage();
                        } else if (typeof window !== "undefined") {
                            window.currentTabIndex = 7;
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Quick Preset Selection Bar
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Quick Scoring Presets"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: "#c9d1d9"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // 1. Balanced (Default)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 46
                        radius: 6
                        color: bPresetMa.containsMouse ? "#21262d" : "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            Text { text: "⚖️"; font.pixelSize: 16 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Balanced (Default)"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Harmonious balance across all roles"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            id: bPresetMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyScorePreset("balanced")
                        }
                    }

                    // 2. Code & PR Focused
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 46
                        radius: 6
                        color: cPresetMa.containsMouse ? "#21262d" : "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            Text { text: "💻"; font.pixelSize: 16 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Code & PR Focused"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "High rewards for PRs, commits & reviews"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            id: cPresetMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyScorePreset("code_pr_focused")
                        }
                    }

                    // 3. Agile & Quality Focused
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 46
                        radius: 6
                        color: aPresetMa.containsMouse ? "#21262d" : "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            Text { text: "🎯"; font.pixelSize: 16 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Agile & Quality"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Bugs, stories, syntax & gatekeeping"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            id: aPresetMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyScorePreset("agile_quality_focused")
                        }
                    }

                    // 4. High Velocity
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 46
                        radius: 6
                        color: vPresetMa.containsMouse ? "#21262d" : "#0d1117"
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            Text { text: "🚀"; font.pixelSize: 16 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "High Velocity"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Fast turnarounds & delivery streaks"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                        }
                        MouseArea {
                            id: vPresetMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyScorePreset("high_velocity")
                        }
                    }
                }
            }

            // Live Simulation Pill
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 6
                color: "#0d1b2a"
                border.color: "#1f6feb"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text { text: "⚡"; font.pixelSize: 14 }
                    Text {
                        text: "Live Formula Preview: (2 PRs × " + root.scorePrsClosed + ") + (5 Commits × " + root.scoreCommitsCount + ") + (3 Tasks × " + root.scoreTasksCompleted + ") + (1 Bug × " + root.scoreBugsResolved + ") − (1 Delay Week × " + root.scoreDelayWeekPenalty + ") ="
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        color: "#79c0ff"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Math.max(0, ((2 * root.scorePrsClosed) + (5 * root.scoreCommitsCount) + (3 * root.scoreTasksCompleted) + (1 * root.scoreBugsResolved) - (1 * root.scoreDelayWeekPenalty))) + " pts"
                        font.family: "Consolas, Segoe UI, monospace"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: "#ffd700"
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // 4 Main Category Cards Grid
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 16
                columnSpacing: 16

                // ==========================================
                // Card 1: Pull Requests & Git Collaboration
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: prCol.implicitHeight + 28
                    radius: 8
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: prCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            spacing: 8
                            Text { text: "🔀"; font.pixelSize: 16 }
                            Text {
                                text: "Pull Requests & Git Activities"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#58a6ff"
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                        // PR Closed / Merged
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "PR Merged / Closed"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Successfully completed pull request"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scorePrsClosed > 0) root.scorePrsClosed -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#58a6ff88"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scorePrsClosed + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scorePrsClosed < 100) root.scorePrsClosed += 1 } }
                            }
                        }

                        // PR Created
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "PR Created"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Initiated proposed code review"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scorePrsCreated > 0) root.scorePrsCreated -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#58a6ff88"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scorePrsCreated + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scorePrsCreated < 100) root.scorePrsCreated += 1 } }
                            }
                        }

                        // PR Approved
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "PR Approved (Reviewer)"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Approved peer code contribution"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scorePrsApproved > 0) root.scorePrsApproved -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#58a6ff88"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scorePrsApproved + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scorePrsApproved < 100) root.scorePrsApproved += 1 } }
                            }
                        }

                        // PR Reviewed
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "PR Reviewed"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Participated in peer code review"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scorePrsReviewed > 0) root.scorePrsReviewed -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#58a6ff88"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scorePrsReviewed + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scorePrsReviewed < 100) root.scorePrsReviewed += 1 } }
                            }
                        }

                        // Repository Commits
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Git Commits"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Authored / committed code changes"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreCommitsCount > 0) root.scoreCommitsCount -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#58a6ff88"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreCommitsCount + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreCommitsCount < 100) root.scoreCommitsCount += 1 } }
                            }
                        }

                        // Feature Branches Merged
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Branches Merged / Closed"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Completed topic feature branch integration"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBranchesClosed > 0) root.scoreBranchesClosed -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#58a6ff88"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreBranchesClosed + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBranchesClosed < 100) root.scoreBranchesClosed += 1 } }
                            }
                        }

                        // Tags Pushed
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Release Tags Pushed"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Published repository version release tag"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTagsPushed > 0) root.scoreTagsPushed -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#58a6ff88"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreTagsPushed + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTagsPushed < 100) root.scoreTagsPushed += 1 } }
                            }
                        }
                    }
                }

                // ==========================================
                // Card 2: Agile Tasks & Work Items
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: wiCol.implicitHeight + 28
                    radius: 8
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: wiCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            spacing: 8
                            Text { text: "📋"; font.pixelSize: 16 }
                            Text {
                                text: "Agile Tasks & Work Items"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#7ee787"
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                        // Tasks Completed
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Tasks Completed / Closed"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Closed agile sprint task item"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTasksCompleted > 0) root.scoreTasksCompleted -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#3fb95088"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreTasksCompleted + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTasksCompleted < 100) root.scoreTasksCompleted += 1 } }
                            }
                        }

                        // Tasks Created
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Tasks Created / Planned"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Scoped and created new backlog task"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTasksCreated > 0) root.scoreTasksCreated -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#3fb95088"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreTasksCreated + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTasksCreated < 100) root.scoreTasksCreated += 1 } }
                            }
                        }

                        // Bugs Resolved
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Bugs Fixed / Resolved"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Resolved defect or bug work item"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBugsResolved > 0) root.scoreBugsResolved -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#3fb95088"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreBugsResolved + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBugsResolved < 100) root.scoreBugsResolved += 1 } }
                            }
                        }

                        // Stories Completed
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "User Stories Delivered"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Completed user story or requirement"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreStoriesCompleted > 0) root.scoreStoriesCompleted -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#3fb95088"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreStoriesCompleted + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreStoriesCompleted < 100) root.scoreStoriesCompleted += 1 } }
                            }
                        }

                        // Fast Turnaround Closes
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Fast Turnaround Closes (<24h)"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Rapid completion within 24 hours of creation"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTasksFastClosed > 0) root.scoreTasksFastClosed -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#3fb95088"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreTasksFastClosed + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTasksFastClosed < 100) root.scoreTasksFastClosed += 1 } }
                            }
                        }

                        // Structured Syntax [<NR>]
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Structured Syntax [<NR>] Delivery"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Deliveries adhering to PBS numbering convention"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreStructuredSyntaxCompleted > 0) root.scoreStructuredSyntaxCompleted -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#3fb95088"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreStructuredSyntaxCompleted + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreStructuredSyntaxCompleted < 100) root.scoreStructuredSyntaxCompleted += 1 } }
                            }
                        }

                        // Evidences Attached
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Traceability Evidences Attached"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Linked commits, PRs, relations & URL proofs"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTaskEvidencesCount > 0) root.scoreTaskEvidencesCount -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#3fb95088"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreTaskEvidencesCount + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTaskEvidencesCount < 100) root.scoreTaskEvidencesCount += 1 } }
                            }
                        }

                        // State Cleanups & Pushbacks
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Backlog State Cleanups"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Cleaning states & managing lifecycle transitions"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTasksCleaned > 0) root.scoreTasksCleaned -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#3fb95088"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreTasksCleaned + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreTasksCleaned < 100) root.scoreTasksCleaned += 1 } }
                            }
                        }
                    }
                }

                // ==========================================
                // Card 3: CI/CD Builds & Streaks
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: cicdCol.implicitHeight + 28
                    radius: 8
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: cicdCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            spacing: 8
                            Text { text: "⚡"; font.pixelSize: 16 }
                            Text {
                                text: "CI/CD Stability & Streaks"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#e3b341"
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                        // Successful Build
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Successful CI Build"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Green automated pipeline execution"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBuildsSucceeded > 0) root.scoreBuildsSucceeded -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#e3b34188"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreBuildsSucceeded + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBuildsSucceeded < 100) root.scoreBuildsSucceeded += 1 } }
                            }
                        }

                        // Badge Tier Earned
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Badge Earned Bonus"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Bonus points for each unlocked badge tier"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBadgeBonus > 0) root.scoreBadgeBonus -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#e3b34188"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreBadgeBonus + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBadgeBonus < 100) root.scoreBadgeBonus += 1 } }
                            }
                        }

                        // Streak Week Bonus
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Streak Week Multiplier"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Reward per consecutive active sprint week"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreStreakWeekBonus > 0) root.scoreStreakWeekBonus -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#e3b34188"; border.width: 1; Text { anchors.centerIn: parent; text: "+" + root.scoreStreakWeekBonus + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#3fb950" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreStreakWeekBonus < 100) root.scoreStreakWeekBonus += 1 } }
                            }
                        }
                    }
                }

                // ==========================================
                // Card 4: Penalties & Hygiene Deductions
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: penCol.implicitHeight + 28
                    radius: 8
                    color: "#0d1117"
                    border.color: "#30363d"
                    border.width: 1

                    ColumnLayout {
                        id: penCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            spacing: 8
                            Text { text: "⚠️"; font.pixelSize: 16 }
                            Text {
                                text: "Penalties & Hygiene Deductions"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#f85149"
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

                        // Delay Week Penalty
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Sprint Delay / Rescheduling Shift"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Deduction per postponed week of delay"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreDelayWeekPenalty > 0) root.scoreDelayWeekPenalty -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#f8514988"; border.width: 1; Text { anchors.centerIn: parent; text: "−" + root.scoreDelayWeekPenalty + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#f85149" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreDelayWeekPenalty < 50) root.scoreDelayWeekPenalty += 1 } }
                            }
                        }

                        // Build Failed Penalty
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Broken CI Build"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Failed pipeline execution triggered"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBuildFailedPenalty > 0) root.scoreBuildFailedPenalty -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#f8514988"; border.width: 1; Text { anchors.centerIn: parent; text: "−" + root.scoreBuildFailedPenalty + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#f85149" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreBuildFailedPenalty < 50) root.scoreBuildFailedPenalty += 1 } }
                            }
                        }

                        // Stale Task Penalty
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: "Stale Inactive Task (>30d)"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#f0f6fc" }
                                Text { text: "Unfinished items left untouched on board"; font.family: "Segoe UI, sans-serif"; font.pixelSize: 10; color: "#8b949e" }
                            }
                            RowLayout {
                                spacing: 4
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreStaleTaskPenalty > 0) root.scoreStaleTaskPenalty -= 1 } }
                                Rectangle { width: 50; height: 26; radius: 4; color: "#161b22"; border.color: "#f8514988"; border.width: 1; Text { anchors.centerIn: parent; text: "−" + root.scoreStaleTaskPenalty + " pts"; font.family: "Consolas, monospace"; font.pixelSize: 11; font.weight: Font.Bold; color: "#f85149" } }
                                Rectangle { width: 26; height: 26; radius: 4; color: "#21262d"; border.color: "#30363d"; border.width: 1; Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.weight: Font.Bold; color: "#c9d1d9" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.scoreStaleTaskPenalty < 50) root.scoreStaleTaskPenalty += 1 } }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Action Buttons Footer
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Button {
                    text: "💾 Save Score Weights"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 38
                        implicitWidth: 190
                        radius: 6
                        color: parent.hovered ? "#2ea043" : "#238636"
                        border.color: "#3fb950"
                        border.width: 1
                    }
                    onClicked: root.saveScoreConfig()
                }

                Button {
                    text: "🔄 Reset Defaults"
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#c9d1d9"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 38
                        implicitWidth: 150
                        radius: 6
                        color: parent.hovered ? "#30363d" : "#21262d"
                        border.color: "#30363d"
                        border.width: 1
                    }
                    onClicked: root.resetScoreDefaults()
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
