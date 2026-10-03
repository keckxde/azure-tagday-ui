import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

ColumnLayout {
    id: tabRoot
    Layout.fillWidth: true
    spacing: 16

    property var categoriesList: (backend && backend.repoCategories) ? backend.repoCategories : []
    property var prefixRulesList: (backend && backend.repoPrefixRules) ? backend.repoPrefixRules : []
    property var overridesList: (backend && backend.repoCategoryOverrides) ? backend.repoCategoryOverrides : []
    property var reposList: (backend && backend.repositories) ? backend.repositories : []
    property int currentSection: 0 // 0: Categories, 1: Prefix Rules, 2: Explicit Repo Mappings

    // Editing state for Category
    property string editingCatName: ""
    property string originalCatName: ""
    property string editingCatColor: "#1f6feb"
    property string editingCatBg: "#0d2344"
    property int editingCatSortOrder: categoriesList.length + 1
    property bool editingCatIsDefault: false

    // Editing state for Prefix Rule
    property string editingRulePrefix: ""
    property string originalRulePrefix: ""
    property string editingRuleCategory: categoriesList.length > 0 ? categoriesList[0].name : "GENERIC"

    // Search filter for Repository Mapping Tab
    property string repoSearchQuery: ""

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

    // ==========================================
    // Repository Categories & Classification Header Card
    // ==========================================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: headerCol.implicitHeight + 36
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

        ColumnLayout {
            id: headerCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text { text: "🏷️"; font.pixelSize: 22 }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Repository Category Settings & Classification"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Configure repository categories, badge colors, prefix pattern rules, and per-repository classification overrides stored directly in SQLite."
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Item { Layout.fillWidth: true }

                // Actions: Re-run Matching, Export, Import
                RowLayout {
                    spacing: 8

                    Button {
                        text: "🔄 Re-run Matching"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: "Re-applies all category rules (prefix rules + overrides) to every repository"
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#58a6ff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 30
                            implicitWidth: 140
                            radius: 6
                            color: parent.hovered ? "#0d2844" : "#16243b"
                            border.color: "#1f6feb"
                            border.width: 1
                        }
                        onClicked: {
                            if (!backend) return;
                            var res = backend.rematch_repo_categories();
                            if (res && res.success) {
                                if (root) {
                                    root.bannerMsg = "✓ Rematched " + res.total + " repositories — " + res.updated + " updated.";
                                    root.bannerType = "success";
                                }
                            } else if (root) {
                                root.bannerMsg = (res && res.error) ? res.error : "Rematch failed.";
                                root.bannerType = "error";
                            }
                        }
                    }

                    Button {
                        text: "📤 Export"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: "Export category definitions, prefix rules, and repository mappings to JSON / YAML"
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#c9d1d9"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 30
                            implicitWidth: 85
                            radius: 6
                            color: parent.hovered ? "#30363d" : "#21262d"
                            border.color: "#30363d"
                            border.width: 1
                        }
                        onClicked: {
                            if (!backend) return;
                            var res = backend.export_repo_categories("");
                            if (res && res.success && root) {
                                root.bannerMsg = "✓ Exported categories configuration to " + res.file_path;
                                root.bannerType = "success";
                            } else if (res && !res.cancelled && root) {
                                root.bannerMsg = (res && res.error) ? res.error : "Export failed.";
                                root.bannerType = "error";
                            }
                        }
                    }

                    Button {
                        text: "📥 Import"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        ToolTip.visible: hovered
                        ToolTip.text: "Import categories, prefix rules, and repository mappings from JSON / YAML"
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#3fb950"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 30
                            implicitWidth: 85
                            radius: 6
                            color: parent.hovered ? "#163c20" : "#162b20"
                            border.color: "#238636"
                            border.width: 1
                        }
                        onClicked: {
                            if (!backend) return;
                            var res = backend.import_repo_categories("", false);
                            if (res && res.success && root) {
                                root.bannerMsg = "✓ Imported " + res.categories_count + " categories, " + res.prefix_rules_count + " prefix rules, " + res.overrides_count + " mappings.";
                                root.bannerType = "success";
                            } else if (res && !res.cancelled && root) {
                                root.bannerMsg = (res && res.error) ? res.error : "Import failed.";
                                root.bannerType = "error";
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262d" }

            // Sub-Section Tab Selector Buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: "🏷️ Defined Categories (" + tabRoot.categoriesList.length + ")"
                    checkable: true
                    checked: tabRoot.currentSection === 0
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
                        implicitHeight: 32
                        implicitWidth: 165
                        radius: 6
                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                        border.color: parent.checked ? "#388bfd" : "#30363d"
                    }
                    onClicked: tabRoot.currentSection = 0
                }

                Button {
                    text: "⚡ Classification Prefix Rules (" + tabRoot.prefixRulesList.length + ")"
                    checkable: true
                    checked: tabRoot.currentSection === 1
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
                        implicitHeight: 32
                        implicitWidth: 220
                        radius: 6
                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                        border.color: parent.checked ? "#388bfd" : "#30363d"
                    }
                    onClicked: tabRoot.currentSection = 1
                }

                Button {
                    text: "📁 Repository Mappings (" + tabRoot.reposList.length + ")"
                    checkable: true
                    checked: tabRoot.currentSection === 2
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
                        implicitHeight: 32
                        implicitWidth: 185
                        radius: 6
                        color: parent.checked ? "#1f6feb" : (parent.hovered ? "#21262d" : "#0d1117")
                        border.color: parent.checked ? "#388bfd" : "#30363d"
                    }
                    onClicked: tabRoot.currentSection = 2
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // ==========================================
    // Section 0: Categories Manager (List + Editor)
    // ==========================================
    Rectangle {
        visible: tabRoot.currentSection === 0
        Layout.fillWidth: true
        implicitHeight: 520
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

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
                            text: "Defined Categories (" + tabRoot.categoriesList.length + ")"
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
                            onClicked: tabRoot.resetCategoryForm()
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: tabRoot.categoriesList

                        delegate: Rectangle {
                            width: parent ? parent.width : 350
                            height: 44
                            radius: 6
                            color: (tabRoot.originalCatName === modelData.name) ? "#1f242c" : (catMa.containsMouse ? "#161b22" : "#0d1117")
                            border.color: (tabRoot.originalCatName === modelData.name) ? "#388bfd" : "#21262d"
                            border.width: 1

                            MouseArea {
                                id: catMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: tabRoot.setCategoryForEdit(modelData)
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
                                            if (root) {
                                                root.bannerMsg = "Deleted category '" + modelData.name + "'.";
                                                root.bannerType = "info";
                                            }
                                            tabRoot.resetCategoryForm();
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
                            text: tabRoot.originalCatName !== "" ? ("Edit Category: " + tabRoot.originalCatName) : "Add New Repository Category"
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
                                text: tabRoot.editingCatName
                                placeholderText: "e.g. CORE, GENERIC, PLATFORM..."
                                placeholderTextColor: "#484f58"
                                Layout.fillWidth: true
                                color: "#f0f6fc"
                                font.pixelSize: 12
                                background: Rectangle {
                                    implicitHeight: 34
                                    radius: 6
                                    color: "#161b22"
                                    border.color: catNameInput.activeFocus ? "#388bfd" : "#30363d"
                                }
                                onTextChanged: tabRoot.editingCatName = text
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
                                        border.color: tabRoot.editingCatColor === modelData ? "#ffffff" : "#30363d"
                                        border.width: tabRoot.editingCatColor === modelData ? 2 : 1

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: tabRoot.editingCatColor = modelData
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 8
                                TextField {
                                    id: catColorInput
                                    text: tabRoot.editingCatColor
                                    placeholderText: "#1f6feb"
                                    placeholderTextColor: "#484f58"
                                    Layout.preferredWidth: 120
                                    color: "#f0f6fc"
                                    font.pixelSize: 12
                                    background: Rectangle {
                                        implicitHeight: 32
                                        radius: 4
                                        color: "#161b22"
                                        border.color: "#30363d"
                                    }
                                    onTextChanged: tabRoot.editingCatColor = text
                                }

                                // Preview Badge
                                Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: Math.max(90, catPreviewText.implicitWidth + 16)
                                    radius: 12
                                    color: tabRoot.editingCatColor
                                    Text {
                                        id: catPreviewText
                                        anchors.centerIn: parent
                                        text: tabRoot.editingCatName || "PREVIEW"
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
                                    value: tabRoot.editingCatSortOrder
                                    editable: true
                                    onValueChanged: tabRoot.editingCatSortOrder = value
                                }
                            }

                            CheckBox {
                                id: isDefaultCb
                                text: "Set as Default Category Fallback"
                                checked: tabRoot.editingCatIsDefault
                                onCheckedChanged: tabRoot.editingCatIsDefault = checked
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
                                        tabRoot.editingCatName,
                                        tabRoot.editingCatColor,
                                        tabRoot.editingCatBg,
                                        tabRoot.editingCatSortOrder,
                                        tabRoot.editingCatIsDefault
                                    );
                                    if (res && res.success) {
                                        if (root) {
                                            root.bannerMsg = "Category '" + tabRoot.editingCatName + "' saved successfully in database!";
                                            root.bannerType = "success";
                                        }
                                        tabRoot.resetCategoryForm();
                                    } else if (root) {
                                        root.bannerMsg = (res && res.error) ? res.error : "Failed to save category.";
                                        root.bannerType = "error";
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
                                onClicked: tabRoot.resetCategoryForm()
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // Section 1: Prefix Classification Rules
    // ==========================================
    Rectangle {
        visible: tabRoot.currentSection === 1
        Layout.fillWidth: true
        implicitHeight: 520
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

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
                            text: "Classification Prefix Rules (" + tabRoot.prefixRulesList.length + ")"
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
                            onClicked: tabRoot.resetRuleForm()
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: tabRoot.prefixRulesList

                        delegate: Rectangle {
                            width: parent ? parent.width : 350
                            height: 40
                            radius: 6
                            color: (tabRoot.originalRulePrefix === modelData.prefix) ? "#1f242c" : (ruleMa.containsMouse ? "#161b22" : "#0d1117")
                            border.color: (tabRoot.originalRulePrefix === modelData.prefix) ? "#388bfd" : "#21262d"
                            border.width: 1

                            MouseArea {
                                id: ruleMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: tabRoot.setRuleForEdit(modelData)
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
                                            if (root) {
                                                root.bannerMsg = "Deleted prefix rule '" + modelData.prefix + "'.";
                                                root.bannerType = "info";
                                            }
                                            tabRoot.resetRuleForm();
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
                        text: tabRoot.originalRulePrefix !== "" ? ("Edit Prefix Rule: " + tabRoot.originalRulePrefix) : "Add New Prefix Classification Rule"
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
                            text: tabRoot.editingRulePrefix
                            placeholderText: "e.g. generic-, 3rdparty-, app-..."
                            placeholderTextColor: "#484f58"
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
                            onTextChanged: tabRoot.editingRulePrefix = text
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
                                for (var i = 0; i < tabRoot.categoriesList.length; i++) {
                                    names.push(tabRoot.categoriesList[i].name);
                                }
                                return names;
                            }
                            currentIndex: {
                                for (var i = 0; i < tabRoot.categoriesList.length; i++) {
                                    if (tabRoot.categoriesList[i].name === tabRoot.editingRuleCategory)
                                        return i;
                                }
                                return 0;
                            }
                            onActivated: {
                                if (currentIndex >= 0 && currentIndex < tabRoot.categoriesList.length) {
                                    tabRoot.editingRuleCategory = tabRoot.categoriesList[currentIndex].name;
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
                                    tabRoot.editingRulePrefix,
                                    tabRoot.editingRuleCategory
                                );
                                if (res && res.success) {
                                    if (root) {
                                        root.bannerMsg = "Prefix rule '" + tabRoot.editingRulePrefix + "' saved successfully!";
                                        root.bannerType = "success";
                                    }
                                    tabRoot.resetRuleForm();
                                } else if (root) {
                                    root.bannerMsg = (res && res.error) ? res.error : "Failed to save rule.";
                                    root.bannerType = "error";
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
                            onClicked: tabRoot.resetRuleForm()
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // Section 2: Explicit Repository Mappings
    // ==========================================
    Rectangle {
        visible: tabRoot.currentSection === 2
        Layout.fillWidth: true
        implicitHeight: 520
        color: "#161b22"
        radius: 8
        border.color: "#30363d"
        border.width: 1

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
                    placeholderText: "Search repository to assign or view category..."
                    placeholderTextColor: "#484f58"
                    Layout.fillWidth: true
                    color: "#f0f6fc"
                    font.pixelSize: 12
                    background: Rectangle {
                        implicitHeight: 34
                        radius: 6
                        color: "#0d1117"
                        border.color: repoFilterInput.activeFocus ? "#388bfd" : "#30363d"
                    }
                    onTextChanged: tabRoot.repoSearchQuery = text
                }

                Text {
                    text: "(" + tabRoot.reposList.length + " total repositories)"
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
                    var q = (tabRoot.repoSearchQuery || "").toLowerCase();
                    var all = tabRoot.reposList || [];
                    if (!q) return all;
                    var filtered = [];
                    for (var i = 0; i < all.length; i++) {
                        if (all[i].name && all[i].name.toLowerCase().indexOf(q) !== -1) {
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
                            text: modelData.name || ""
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
                                for (var i = 0; i < tabRoot.categoriesList.length; i++) {
                                    names.push(tabRoot.categoriesList[i].name);
                                }
                                return names;
                            }
                            currentIndex: {
                                for (var i = 0; i < tabRoot.categoriesList.length; i++) {
                                    if (tabRoot.categoriesList[i].name === modelData.category)
                                        return i;
                                }
                                return 0;
                            }
                            onActivated: {
                                if (backend && currentIndex >= 0 && currentIndex < tabRoot.categoriesList.length) {
                                    var targetCat = tabRoot.categoriesList[currentIndex].name;
                                    backend.set_repo_category(modelData.name, targetCat);
                                    if (root) {
                                        root.bannerMsg = "Set repository '" + modelData.name + "' category to '" + targetCat + "'.";
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
}
