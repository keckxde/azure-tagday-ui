import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root

    title: ""
    modal: true
    dim: true
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 40 : 1100, 1200)
    height: Math.min(parent ? parent.height - 40 : 860, 900)
    padding: 0

    background: Rectangle {
        color: "#161b22"
        radius: 10
        border.color: "#30363d"
        border.width: 1
    }

    property var categoriesList: (backend && backend.repoCategories) ? backend.repoCategories : []
    property var prefixRulesList: (backend && backend.repoPrefixRules) ? backend.repoPrefixRules : []
    property var overridesList: (backend && backend.repoCategoryOverrides) ? backend.repoCategoryOverrides : []
    property var reposList: (backend && backend.repositories) ? backend.repositories : []
    property int currentTab: 0 // 0: Categories, 1: Prefix Rules, 2: Explicit Repo Mappings

    // Editing state for Category
    property string editingCatName: ""
    property string originalCatName: ""
    property string editingCatColor: "#1f6feb"
    property string editingCatBg: "#0d2344"
    property int editingCatSortOrder: 0
    property bool editingCatIsDefault: false

    // Editing state for Prefix Rule
    property string editingRulePrefix: ""
    property string originalRulePrefix: ""
    property string editingRuleCategory: "GENERIC"

    // Search filter for Repository Mapping Tab
    property string repoSearchQuery: ""

    property string feedbackMsg: ""
    property string feedbackType: "success"

    function openDialog() {
        feedbackMsg = "";
        resetCategoryForm();
        resetRuleForm();
        open();
    }

    function resetCategoryForm() {
        editingCatName = "";
        originalCatName = "";
        editingCatColor = "#1f6feb";
        editingCatBg = "#0d2344";
        editingCatSortOrder = categoriesList.length + 1;
        editingCatIsDefault = false;
    }

    function resetRuleForm() {
        editingRulePrefix = "";
        originalRulePrefix = "";
        editingRuleCategory = categoriesList.length > 0 ? categoriesList[0].name : "GENERIC";
    }

    function setCategoryForEdit(cat) {
        if (!cat) return;
        originalCatName = cat.name || "";
        editingCatName = cat.name || "";
        editingCatColor = cat.color || "#1f6feb";
        editingCatBg = cat.bg_color || "#0d2344";
        editingCatSortOrder = cat.sort_order || 0;
        editingCatIsDefault = !!cat.is_default;
    }

    function setRuleForEdit(rule) {
        if (!rule) return;
        originalRulePrefix = rule.prefix || "";
        editingRulePrefix = rule.prefix || "";
        editingRuleCategory = rule.category || "GENERIC";
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Dialog Header
        Rectangle {
            Layout.fillWidth: true
            height: 64
            color: "#0d1117"
            radius: 10

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#30363d"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: "🏷️"
                    font.pixelSize: 22
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Repository Category Settings"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Configure category badge colors, prefix classification rules, and per-repo overrides stored directly in SQLite"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }

                Item { Layout.fillWidth: true }

                // Tab Switcher
                Row {
                    spacing: 4

                    Button {
                        text: "🏷️ Categories (" + root.categoriesList.length + ")"
                        checkable: true
                        checked: root.currentTab === 0
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
                            implicitWidth: 125
                            radius: 6
                            color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                            border.color: parent.checked ? "#388bfd" : "#30363d"
                        }
                        onClicked: {
                            root.currentTab = 0;
                            root.feedbackMsg = "";
                        }
                    }

                    Button {
                        text: "⚡ Prefix Rules (" + root.prefixRulesList.length + ")"
                        checkable: true
                        checked: root.currentTab === 1
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
                            implicitWidth: 125
                            radius: 6
                            color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                            border.color: parent.checked ? "#388bfd" : "#30363d"
                        }
                        onClicked: {
                            root.currentTab = 1;
                            root.feedbackMsg = "";
                        }
                    }

                    Button {
                        text: "📁 Repositories (" + root.reposList.length + ")"
                        checkable: true
                        checked: root.currentTab === 2
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
                            implicitWidth: 130
                            radius: 6
                            color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "transparent")
                            border.color: parent.checked ? "#388bfd" : "#30363d"
                        }
                        onClicked: {
                            root.currentTab = 2;
                            root.feedbackMsg = "";
                        }
                    }
                }

                Button {
                    text: "🔄 Re-run Matching"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    ToolTip.visible: hovered
                    ToolTip.text: "Re-applies all category rules (prefix rules + overrides) to every repository in memory"
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#58a6ff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 30
                        implicitWidth: 150
                        radius: 6
                        color: parent.hovered ? "#0d2844" : "transparent"
                        border.color: "#1f6feb"
                        border.width: 1
                    }
                    onClicked: {
                        if (!backend) return;
                        var res = backend.rematch_repo_categories();
                        if (res && res.success) {
                            root.feedbackMsg = "✓ Rematched " + res.total + " repos — " + res.updated + " updated";
                            root.feedbackType = "success";
                        } else {
                            root.feedbackMsg = (res && res.error) ? res.error : "Matching failed";
                            root.feedbackType = "error";
                        }
                    }
                }

                Button {
                    text: "✕"
                    font.pixelSize: 13
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "#8b949e"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 28
                        implicitWidth: 28
                        radius: 4
                        color: parent.hovered ? "#21262d" : "transparent"
                    }
                    onClicked: root.close()
                }
            }
        }

        // Feedback Banner
        Rectangle {
            Layout.fillWidth: true
            height: root.feedbackMsg !== "" ? 34 : 0
            visible: root.feedbackMsg !== ""
            color: root.feedbackType === "error" ? "#3d1418" : "#122a1e"
            border.color: root.feedbackType === "error" ? "#f85149" : "#2ea043"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8

                Text {
                    text: root.feedbackType === "error" ? "⚠️" : "✅"
                    font.pixelSize: 12
                }

                Text {
                    text: root.feedbackMsg
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 11
                    color: root.feedbackType === "error" ? "#ff7b72" : "#56d364"
                    Layout.fillWidth: true
                }
            }
        }

        // Body Content
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab

            // -------------------------------------------------------------
            // TAB 0: CATEGORIES MANAGER
            // -------------------------------------------------------------
            Item {
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Left Side: Categories List
                    Rectangle {
                        Layout.preferredWidth: 380
                        Layout.fillHeight: true
                        color: "#0d1117"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Defined Categories"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: "+ New Category"
                                    font.pixelSize: 11
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: 105
                                        radius: 4
                                        color: parent.hovered ? "#21262d" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        root.resetCategoryForm();
                                        root.feedbackMsg = "";
                                    }
                                }
                            }

                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 4
                                model: root.categoriesList

                                delegate: Rectangle {
                                    width: parent ? parent.width : 350
                                    height: 44
                                    radius: 6
                                    color: (root.originalCatName === modelData.name) ? "#1f242c" : (catMa.containsMouse ? "#161b22" : "#0d1117")
                                    border.color: (root.originalCatName === modelData.name) ? "#388bfd" : "#21262d"
                                    border.width: 1

                                    MouseArea {
                                        id: catMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.setCategoryForEdit(modelData)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Rectangle {
                                            width: 12
                                            height: 12
                                            radius: 6
                                            color: modelData.color || "#6e7681"
                                            border.color: "#ffffff"
                                            border.width: 1
                                        }

                                        Text {
                                            text: modelData.name
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#f0f6fc"
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            visible: !!modelData.is_default
                                            implicitHeight: 18
                                            implicitWidth: 54
                                            radius: 9
                                            color: "#21262d"
                                            border.color: "#30363d"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "DEFAULT"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#8b949e"
                                            }
                                        }

                                        Button {
                                            text: "🗑"
                                            font.pixelSize: 11
                                            visible: !modelData.is_default
                                            contentItem: Text {
                                                text: parent.text
                                                font: parent.font
                                                color: "#ff7b72"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                implicitHeight: 24
                                                implicitWidth: 24
                                                radius: 4
                                                color: parent.hovered ? "#3d1418" : "transparent"
                                            }
                                            onClicked: {
                                                if (backend) {
                                                    backend.delete_repo_category(modelData.name);
                                                    root.feedbackMsg = "Deleted category '" + modelData.name + "'";
                                                    root.feedbackType = "success";
                                                    root.resetCategoryForm();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Right Side: Category Editor Form
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#0d1117"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 16
                            clip: true

                            ColumnLayout {
                                width: parent.width - 16
                                spacing: 14

                                Text {
                                    text: root.originalCatName !== "" ? ("Edit Category: " + root.originalCatName) : "Add New Repository Category"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }

                                // Category Name
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text {
                                        text: "Category Name *"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                    }
                                    TextField {
                                        id: catNameInput
                                        text: root.editingCatName
                                        placeholderText: "e.g. CORE, GENERIC, PLATFORM..."
                                        Layout.fillWidth: true
                                        color: "#f0f6fc"
                                        font.pixelSize: 12
                                        background: Rectangle {
                                            implicitHeight: 34
                                            radius: 6
                                            color: "#161b22"
                                            border.color: catNameInput.activeFocus ? "#388bfd" : "#30363d"
                                        }
                                        onTextChanged: root.editingCatName = text
                                    }
                                }

                                // Color Chooser
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: "Badge Color *"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#8b949e"
                                    }

                                    // Palette presets
                                    Row {
                                        spacing: 8
                                        Repeater {
                                            model: ["#1f6feb", "#238636", "#6e40c9", "#d29922", "#da3633", "#f0883e", "#58a6ff", "#6e7681", "#3fb950", "#bc8cff"]
                                            Rectangle {
                                                width: 26
                                                height: 26
                                                radius: 13
                                                color: modelData
                                                border.color: root.editingCatColor === modelData ? "#ffffff" : "#30363d"
                                                border.width: root.editingCatColor === modelData ? 2 : 1

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.editingCatColor = modelData
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        spacing: 8
                                        TextField {
                                            id: catColorInput
                                            text: root.editingCatColor
                                            placeholderText: "#1f6feb"
                                            Layout.preferredWidth: 120
                                            color: "#f0f6fc"
                                            font.pixelSize: 12
                                            background: Rectangle {
                                                implicitHeight: 32
                                                radius: 4
                                                color: "#161b22"
                                                border.color: "#30363d"
                                            }
                                            onTextChanged: root.editingCatColor = text
                                        }

                                        // Preview Badge
                                        Rectangle {
                                            implicitHeight: 24
                                            implicitWidth: 90
                                            radius: 12
                                            color: root.editingCatColor
                                            Text {
                                                anchors.centerIn: parent
                                                text: root.editingCatName || "PREVIEW"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: "#ffffff"
                                            }
                                        }
                                    }
                                }

                                // Sort Order & Default checkbox
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20

                                    ColumnLayout {
                                        spacing: 4
                                        Text {
                                            text: "Sort Order"
                                            font.pixelSize: 11
                                            color: "#8b949e"
                                        }
                                        SpinBox {
                                            from: 1
                                            to: 99
                                            value: root.editingCatSortOrder
                                            editable: true
                                            onValueChanged: root.editingCatSortOrder = value
                                        }
                                    }

                                    CheckBox {
                                        id: isDefaultCb
                                        text: "Set as Default Category Fallback"
                                        checked: root.editingCatIsDefault
                                        onCheckedChanged: root.editingCatIsDefault = checked
                                    }
                                }

                                Item { height: 10 }

                                // Action Buttons
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Button {
                                        text: "💾 Save Category"
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
                                            implicitHeight: 34
                                            implicitWidth: 130
                                            radius: 6
                                            color: parent.hovered ? "#2ea043" : "#238636"
                                        }
                                        onClicked: {
                                            if (!backend) return;
                                            var res = backend.save_repo_category(
                                                root.editingCatName,
                                                root.editingCatColor,
                                                root.editingCatBg,
                                                root.editingCatSortOrder,
                                                root.editingCatIsDefault
                                            );
                                            if (res && res.success) {
                                                root.feedbackMsg = "Category '" + root.editingCatName + "' saved successfully in database!";
                                                root.feedbackType = "success";
                                                root.resetCategoryForm();
                                            } else {
                                                root.feedbackMsg = (res && res.error) ? res.error : "Failed to save category";
                                                root.feedbackType = "error";
                                            }
                                        }
                                    }

                                    Button {
                                        text: "Clear"
                                        font.pixelSize: 12
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            color: "#8b949e"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitHeight: 34
                                            implicitWidth: 70
                                            radius: 6
                                            color: parent.hovered ? "#21262d" : "#161b22"
                                            border.color: "#30363d"
                                        }
                                        onClicked: {
                                            root.resetCategoryForm();
                                            root.feedbackMsg = "";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------------
            // TAB 1: PREFIX RULES
            // -------------------------------------------------------------
            Item {
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Left Side: Prefix Rules List
                    Rectangle {
                        Layout.preferredWidth: 380
                        Layout.fillHeight: true
                        color: "#0d1117"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Classification Prefix Rules"
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#f0f6fc"
                                }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: "+ New Rule"
                                    font.pixelSize: 11
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#58a6ff"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: 85
                                        radius: 4
                                        color: parent.hovered ? "#21262d" : "transparent"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        root.resetRuleForm();
                                        root.feedbackMsg = "";
                                    }
                                }
                            }

                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 4
                                model: root.prefixRulesList

                                delegate: Rectangle {
                                    width: parent ? parent.width : 350
                                    height: 40
                                    radius: 6
                                    color: (root.originalRulePrefix === modelData.prefix) ? "#1f242c" : (ruleMa.containsMouse ? "#161b22" : "#0d1117")
                                    border.color: (root.originalRulePrefix === modelData.prefix) ? "#388bfd" : "#21262d"
                                    border.width: 1

                                    MouseArea {
                                        id: ruleMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.setRuleForEdit(modelData)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: modelData.prefix + "*"
                                            font.family: "Consolas, monospace"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: "#58a6ff"
                                        }

                                        Text {
                                            text: "→"
                                            font.pixelSize: 12
                                            color: "#8b949e"
                                        }

                                        Rectangle {
                                            implicitHeight: 20
                                            implicitWidth: 70
                                            radius: 10
                                            color: backend ? backend.get_category_color(modelData.category) : "#6e7681"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.category
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: "#ffffff"
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        Button {
                                            text: "🗑"
                                            font.pixelSize: 11
                                            contentItem: Text {
                                                text: parent.text
                                                font: parent.font
                                                color: "#ff7b72"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                implicitHeight: 24
                                                implicitWidth: 24
                                                radius: 4
                                                color: parent.hovered ? "#3d1418" : "transparent"
                                            }
                                            onClicked: {
                                                if (backend) {
                                                    backend.delete_repo_prefix_rule(modelData.prefix);
                                                    root.feedbackMsg = "Deleted prefix rule '" + modelData.prefix + "'";
                                                    root.feedbackType = "success";
                                                    root.resetRuleForm();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Right Side: Prefix Rule Editor Form
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#0d1117"
                        radius: 8
                        border.color: "#30363d"
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 14

                            Text {
                                text: root.originalRulePrefix !== "" ? ("Edit Prefix Rule: " + root.originalRulePrefix) : "Add New Prefix Classification Rule"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: "#f0f6fc"
                            }

                            // Prefix Pattern
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: "Repository Name Prefix Pattern *"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                }
                                TextField {
                                    id: rulePrefixInput
                                    text: root.editingRulePrefix
                                    placeholderText: "e.g. generic-, 3rdparty-, app-..."
                                    Layout.fillWidth: true
                                    color: "#f0f6fc"
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 12
                                    background: Rectangle {
                                        implicitHeight: 34
                                        radius: 6
                                        color: "#161b22"
                                        border.color: rulePrefixInput.activeFocus ? "#388bfd" : "#30363d"
                                    }
                                    onTextChanged: root.editingRulePrefix = text
                                }
                            }

                            // Target Category Selector
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: "Assign To Category *"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#8b949e"
                                }

                                ComboBox {
                                    id: ruleCatCombo
                                    Layout.fillWidth: true
                                    model: {
                                        var names = [];
                                        for (var i = 0; i < root.categoriesList.length; i++) {
                                            names.push(root.categoriesList[i].name);
                                        }
                                        return names;
                                    }
                                    currentIndex: {
                                        for (var i = 0; i < root.categoriesList.length; i++) {
                                            if (root.categoriesList[i].name === root.editingRuleCategory)
                                                return i;
                                        }
                                        return 0;
                                    }
                                    onActivated: {
                                        if (currentIndex >= 0 && currentIndex < root.categoriesList.length) {
                                            root.editingRuleCategory = root.categoriesList[currentIndex].name;
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }

                            // Action Buttons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    text: "💾 Save Prefix Rule"
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
                                        implicitHeight: 34
                                        implicitWidth: 140
                                        radius: 6
                                        color: parent.hovered ? "#2ea043" : "#238636"
                                    }
                                    onClicked: {
                                        if (!backend) return;
                                        var res = backend.save_repo_prefix_rule(
                                            root.editingRulePrefix,
                                            root.editingRuleCategory
                                        );
                                        if (res && res.success) {
                                            root.feedbackMsg = "Prefix rule '" + root.editingRulePrefix + "' saved successfully!";
                                            root.feedbackType = "success";
                                            root.resetRuleForm();
                                        } else {
                                            root.feedbackMsg = (res && res.error) ? res.error : "Failed to save rule";
                                            root.feedbackType = "error";
                                        }
                                    }
                                }

                                Button {
                                    text: "Clear"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: "#8b949e"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 34
                                        implicitWidth: 70
                                        radius: 6
                                        color: parent.hovered ? "#21262d" : "#161b22"
                                        border.color: "#30363d"
                                    }
                                    onClicked: {
                                        root.resetRuleForm();
                                        root.feedbackMsg = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------------
            // TAB 2: EXPLICIT REPOSITORY MAPPINGS
            // -------------------------------------------------------------
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Filter search bar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        TextField {
                            id: repoFilterInput
                            placeholderText: "Search repository to assign category..."
                            Layout.fillWidth: true
                            color: "#f0f6fc"
                            font.pixelSize: 12
                            background: Rectangle {
                                implicitHeight: 34
                                radius: 6
                                color: "#0d1117"
                                border.color: repoFilterInput.activeFocus ? "#388bfd" : "#30363d"
                            }
                            onTextChanged: root.repoSearchQuery = text
                        }

                        Text {
                            text: "(" + root.reposList.length + " total repositories)"
                            font.pixelSize: 12
                            color: "#8b949e"
                        }
                    }

                    // Table Header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 32
                        color: "#0d1117"
                        radius: 4
                        border.color: "#30363d"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            Text {
                                text: "REPOSITORY NAME"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#8b949e"
                                Layout.preferredWidth: 320
                            }

                            Text {
                                text: "CURRENT CATEGORY"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#8b949e"
                                Layout.preferredWidth: 160
                            }

                            Text {
                                text: "EXPLICIT OVERRIDE SELECTOR"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#8b949e"
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Repositories List
                    ListView {
                        id: repoOverrideView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4

                        model: {
                            var q = (root.repoSearchQuery || "").toLowerCase();
                            var all = root.reposList || [];
                            if (!q) return all;
                            var filtered = [];
                            for (var i = 0; i < all.length; i++) {
                                if (all[i].name.toLowerCase().indexOf(q) !== -1) {
                                    filtered.push(all[i]);
                                }
                            }
                            return filtered;
                        }

                        delegate: Rectangle {
                            width: repoOverrideView.width
                            height: 42
                            radius: 4
                            color: rowMa.containsMouse ? "#1c2128" : "#0d1117"
                            border.color: "#21262d"
                            border.width: 1

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Text {
                                    text: modelData.name
                                    font.family: "Segoe UI, sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: "#f0f6fc"
                                    Layout.preferredWidth: 320
                                    elide: Text.ElideRight
                                }

                                // Current badge
                                Rectangle {
                                    Layout.preferredWidth: 160
                                    height: 22
                                    radius: 11
                                    color: backend ? backend.get_category_color(modelData.category) : "#6e7681"

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.category || "OTHERS"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                    }
                                }

                                // Category Dropdown Selector
                                ComboBox {
                                    Layout.fillWidth: true
                                    model: {
                                        var names = [];
                                        for (var i = 0; i < root.categoriesList.length; i++) {
                                            names.push(root.categoriesList[i].name);
                                        }
                                        return names;
                                    }
                                    currentIndex: {
                                        for (var i = 0; i < root.categoriesList.length; i++) {
                                            if (root.categoriesList[i].name === modelData.category)
                                                return i;
                                        }
                                        return 0;
                                    }
                                    onActivated: {
                                        if (backend && currentIndex >= 0 && currentIndex < root.categoriesList.length) {
                                            var targetCat = root.categoriesList[currentIndex].name;
                                            backend.set_repo_category(modelData.name, targetCat);
                                            root.feedbackMsg = "Set repository '" + modelData.name + "' category to '" + targetCat + "'";
                                            root.feedbackType = "success";
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
}
