import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root

    title: ""
    modal: true
    dim: true
    anchors.centerIn: parent
    width: Math.min(980, parent ? parent.width - 32 : 980)
    height: Math.min(780, parent ? parent.height - 32 : 780)
    padding: 0

    background: Rectangle {
        color: "#161b22"
        radius: 10
        border.color: "#30363d"
        border.width: 1
    }

    property var milestonesList: (backend && backend.milestones) ? backend.milestones : []
    property var categoriesList: (backend && backend.milestoneCategories) ? backend.milestoneCategories : []
    property int currentTab: 0 // 0: Milestones, 1: Categories

    // Editing state for milestone
    property int editingMilestoneId: 0
    property string editingMilestoneName: ""
    property string editingMilestoneDate: ""
    property string editingMilestoneCat: "ddqs"
    property string editingMilestoneDesc: ""

    // Editing state for category
    property string editingCatId: ""
    property string editingCatName: ""
    property string editingCatColor: "#58a6ff"
    property string editingCatBg: "#0d2344"
    property string editingCatIcon: "🔷"

    property string feedbackMsg: ""
    property string feedbackType: "success"

    // Date Chooser Properties
    property int pickerYear: (new Date()).getFullYear()
    property int pickerMonth: (new Date()).getMonth()
    property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    function syncPickerWithDateString(dateStr) {
        if (dateStr && dateStr.trim() !== "") {
            var parts = dateStr.trim().split("-");
            if (parts.length === 3) {
                var y = parseInt(parts[0], 10);
                var m = parseInt(parts[1], 10) - 1;
                if (!isNaN(y) && !isNaN(m) && y > 2000 && m >= 0 && m <= 11) {
                    pickerYear = y;
                    pickerMonth = m;
                    return;
                }
            }
        }
        var now = new Date();
        pickerYear = now.getFullYear();
        pickerMonth = now.getMonth();
    }

    function getCalendarCells(year, month, selectedDate) {
        var cells = [];
        var daysInCurrentMonth = new Date(year, month + 1, 0).getDate();
        var daysInPrevMonth = new Date(year, month, 0).getDate();
        var startOffset = (new Date(year, month, 1).getDay() + 6) % 7; // Monday = 0

        var today = new Date();
        var tY = today.getFullYear();
        var tM = (today.getMonth() + 1 < 10 ? "0" : "") + (today.getMonth() + 1);
        var tD = (today.getDate() < 10 ? "0" : "") + today.getDate();
        var todayStr = tY + "-" + tM + "-" + tD;

        // Previous month trailing days
        for (var p = startOffset - 1; p >= 0; p--) {
            var pDay = daysInPrevMonth - p;
            var pM = month - 1;
            var pY = year;
            if (pM < 0) { pM = 11; pY--; }
            var pMStr = (pM + 1 < 10 ? "0" : "") + (pM + 1);
            var pDStr = (pDay < 10 ? "0" : "") + pDay;
            var pDateStr = pY + "-" + pMStr + "-" + pDStr;
            cells.push({
                day: pDay,
                dateStr: pDateStr,
                isCurrentMonth: false,
                isToday: (pDateStr === todayStr),
                isSelected: (pDateStr === selectedDate)
            });
        }

        // Current month days
        for (var d = 1; d <= daysInCurrentMonth; d++) {
            var cMStr = (month + 1 < 10 ? "0" : "") + (month + 1);
            var cDStr = (d < 10 ? "0" : "") + d;
            var cDateStr = year + "-" + cMStr + "-" + cDStr;
            cells.push({
                day: d,
                dateStr: cDateStr,
                isCurrentMonth: true,
                isToday: (cDateStr === todayStr),
                isSelected: (cDateStr === selectedDate)
            });
        }

        // Next month leading days (fill up to 42 cells = 6 weeks)
        var totalCells = 42;
        var remaining = totalCells - cells.length;
        for (var n = 1; n <= remaining; n++) {
            var nM = month + 1;
            var nY = year;
            if (nM > 11) { nM = 0; nY++; }
            var nMStr = (nM + 1 < 10 ? "0" : "") + (nM + 1);
            var nDStr = (n < 10 ? "0" : "") + n;
            var nDateStr = nY + "-" + nMStr + "-" + nDStr;
            cells.push({
                day: n,
                dateStr: nDateStr,
                isCurrentMonth: false,
                isToday: (nDateStr === todayStr),
                isSelected: (nDateStr === selectedDate)
            });
        }

        return cells;
    }

    onAboutToShow: {
        refreshData();
    }

    function openDialog() {
        refreshData();
        resetMilestoneForm();
        resetCategoryForm();
        feedbackMsg = "";
        root.open();
    }

    function refreshData() {
        if (backend) {
            milestonesList = backend.get_milestones() || [];
            categoriesList = backend.get_milestone_categories() || [];
        }
    }

    function resetMilestoneForm() {
        editingMilestoneId = 0;
        editingMilestoneName = "";
        editingMilestoneDate = "";
        editingMilestoneCat = categoriesList.length > 0 ? categoriesList[0].id : "ddqs";
        editingMilestoneDesc = "";
        mNameInput.text = "";
        mDateInput.text = "";
        mDescInput.text = "";
        if (categoriesList.length > 0) mCatCombo.currentIndex = 0;
    }

    function editMilestone(m) {
        editingMilestoneId = m.id;
        editingMilestoneName = m.name;
        editingMilestoneDate = m.target_date;
        editingMilestoneCat = m.category_id;
        editingMilestoneDesc = m.description || "";
        mNameInput.text = m.name;
        mDateInput.text = m.target_date;
        mDescInput.text = m.description || "";
        for (var i = 0; i < categoriesList.length; i++) {
            if (categoriesList[i].id === m.category_id) {
                mCatCombo.currentIndex = i;
                break;
            }
        }
    }

    function resetCategoryForm() {
        editingCatId = "";
        editingCatName = "";
        editingCatColor = "#58a6ff";
        editingCatBg = "#0d2344";
        editingCatIcon = "🔷";
        cNameInput.text = "";
        cColorInput.text = "#58a6ff";
        cBgInput.text = "#0d2344";
        cIconInput.text = "🔷";
    }

    function editCategory(c) {
        editingCatId = c.id;
        editingCatName = c.name;
        editingCatColor = c.color;
        editingCatBg = c.bg_color;
        editingCatIcon = c.icon;
        cNameInput.text = c.name;
        cColorInput.text = c.color;
        cBgInput.text = c.bg_color;
        cIconInput.text = c.icon;
    }

    onOpened: {
        refreshData();
        resetMilestoneForm();
        resetCategoryForm();
        feedbackMsg = "";
    }

    Connections {
        target: backend
        function onMilestonesChanged() { root.refreshData(); }
        function onMilestoneCategoriesChanged() { root.refreshData(); }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Header ----
        Rectangle {
            Layout.fillWidth: true
            height: 54
            color: "#0d1117"
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 12

                Text { text: "🚩"; font.pixelSize: 18 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Major Milestones & Process Gateways"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "#f0f6fc"
                    }
                    Text {
                        text: "Manage project milestones (DDQS, QIAV, Scenarios) and customize category appearances"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 11
                        color: "#8b949e"
                    }
                }

                // Close Button
                Rectangle {
                    width: 28; height: 28; radius: 4
                    color: closeMa.containsMouse ? "#30363d" : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 12; color: "#8b949e" }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }
        }

        // ---- Tabs Bar ----
        Rectangle {
            Layout.fillWidth: true
            height: 42
            color: "#161b22"
            border.color: "#30363d"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                spacing: 12

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: tab1Text.implicitWidth + 24
                    radius: 6
                    color: root.currentTab === 0 ? "#21262d" : "transparent"
                    border.color: root.currentTab === 0 ? "#388bfd" : "transparent"

                    Text {
                        id: tab1Text
                        anchors.centerIn: parent
                        text: "🎯 Major Milestones (" + root.milestonesList.length + ")"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: root.currentTab === 0 ? Font.Bold : Font.Normal
                        color: root.currentTab === 0 ? "#58a6ff" : "#8b949e"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = 0
                    }
                }

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: tab2Text.implicitWidth + 24
                    radius: 6
                    color: root.currentTab === 1 ? "#21262d" : "transparent"
                    border.color: root.currentTab === 1 ? "#388bfd" : "transparent"

                    Text {
                        id: tab2Text
                        anchors.centerIn: parent
                        text: "🎨 Category Appearances (" + root.categoriesList.length + ")"
                        font.family: "Segoe UI, sans-serif"
                        font.pixelSize: 12
                        font.weight: root.currentTab === 1 ? Font.Bold : Font.Normal
                        color: root.currentTab === 1 ? "#58a6ff" : "#8b949e"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = 1
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ---- Body / Tab Content ----
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ==========================================
            // TAB 0: Milestones List & Form
            // ==========================================
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                visible: root.currentTab === 0

                // Left: Milestones List
                Rectangle {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    color: "#0d1117"
                    radius: 8
                    border.color: "#30363d"
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // List Header
                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            color: "#161b22"
                            border.color: "#30363d"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                Text { text: "PROJECT MILESTONES"; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: "➕ New"
                                    font.pixelSize: 11
                                    contentItem: Text { text: parent.text; font: parent.font; color: "#3fb950" }
                                    background: Rectangle { implicitHeight: 22; implicitWidth: 60; radius: 4; color: parent.hovered ? "#162b20" : "transparent"; border.color: "#238636" }
                                    onClicked: root.resetMilestoneForm()
                                }
                            }
                        }

                        // List of Milestones
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ListView {
                                width: parent.width
                                model: root.milestonesList
                                spacing: 4
                                delegate: Rectangle {
                                    width: parent.width - 16
                                    height: 52
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    radius: 6
                                    color: (root.editingMilestoneId === modelData.id) ? "#1f242c" : (mItemMa.containsMouse ? "#161b22" : "#0d1117")
                                    border.color: (root.editingMilestoneId === modelData.id) ? "#58a6ff" : "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 10

                                        // Category Icon Pill
                                        Rectangle {
                                            implicitWidth: 32; implicitHeight: 32; radius: 6
                                            color: modelData.category_bg_color || "#16243b"
                                            border.color: modelData.category_color || "#388bfd"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.category_icon || "🚩"
                                                font.pixelSize: 15
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            RowLayout {
                                                spacing: 6
                                                Text {
                                                    text: modelData.name
                                                    font.family: "Segoe UI, sans-serif"
                                                    font.pixelSize: 12
                                                    font.weight: Font.Bold
                                                    color: "#f0f6fc"
                                                }
                                                // Category Badge
                                                Rectangle {
                                                    implicitHeight: 16
                                                    implicitWidth: catLabel.implicitWidth + 8
                                                    radius: 8
                                                    color: modelData.category_bg_color || "#16243b"
                                                    border.color: modelData.category_color || "#388bfd"
                                                    Text {
                                                        id: catLabel
                                                        anchors.centerIn: parent
                                                        text: modelData.category_name || "General"
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        color: modelData.category_color || "#79c0ff"
                                                    }
                                                }
                                            }
                                            Text {
                                                text: "📅 " + modelData.target_date + (modelData.description ? (" · " + modelData.description) : "")
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 11
                                                color: "#8b949e"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        // Edit Button
                                        Button {
                                            text: "✏️"
                                            font.pixelSize: 11
                                            background: Rectangle { implicitWidth: 26; implicitHeight: 26; radius: 4; color: parent.hovered ? "#30363d" : "transparent" }
                                            onClicked: root.editMilestone(modelData)
                                        }

                                        // Delete Button
                                        Button {
                                            text: "🗑️"
                                            font.pixelSize: 11
                                            background: Rectangle { implicitWidth: 26; implicitHeight: 26; radius: 4; color: parent.hovered ? "#3c1e1e" : "transparent" }
                                            onClicked: {
                                                if (backend) {
                                                    backend.delete_milestone(modelData.id);
                                                    if (root.editingMilestoneId === modelData.id) root.resetMilestoneForm();
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: mItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        propagateComposedEvents: true
                                        onClicked: root.editMilestone(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // Right: Milestone Editor Form
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 380
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        Text {
                            text: root.editingMilestoneId > 0 ? "Edit Milestone" : "Add New Milestone"
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: "#58a6ff"
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#30363d" }

                        // Name
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4
                            Text { text: "MILESTONE NAME"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                            TextField {
                                id: mNameInput
                                Layout.fillWidth: true
                                implicitHeight: 32
                                font.pixelSize: 12
                                color: "#f0f6fc"
                                placeholderText: "e.g. DDQS M1 Gate, QIAV Gateway A"
                                placeholderTextColor: "#484f58"
                                background: Rectangle { color: "#0d1117"; radius: 4; border.color: mNameInput.activeFocus ? "#58a6ff" : "#30363d" }
                            }
                        }

                        // Target Date with Interactive Date Chooser
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "TARGET DATE (YYYY-MM-DD)"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "📅 Open Calendar"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: "#58a6ff"
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: datePickerPopup.openOrToggle()
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                TextField {
                                    id: mDateInput
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 12
                                    color: "#f0f6fc"
                                    placeholderText: "YYYY-MM-DD (e.g. 2026-06-15)"
                                    placeholderTextColor: "#484f58"
                                    background: Rectangle {
                                        color: "#0d1117"
                                        radius: 4
                                        border.color: mDateInput.activeFocus ? "#58a6ff" : "#30363d"
                                    }
                                    onTextChanged: {
                                        root.editingMilestoneDate = text;
                                    }
                                }

                                Button {
                                    id: datePickerBtn
                                    implicitHeight: 32
                                    implicitWidth: 36
                                    contentItem: Text {
                                        text: "📅"
                                        font.pixelSize: 14
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        radius: 4
                                        color: (datePickerPopup.visible || parent.hovered) ? "#21262d" : "#0d1117"
                                        border.color: (datePickerPopup.visible || parent.hovered) ? "#58a6ff" : "#30363d"
                                    }
                                    onClicked: {
                                        datePickerPopup.openOrToggle();
                                    }
                                }
                            }

                            // Quick Preset Chips below input
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: [
                                        { label: "Today", days: 0 },
                                        { label: "+1 Wk", days: 7 },
                                        { label: "+2 Wks", days: 14 },
                                        { label: "+1 Mo", days: 30 },
                                        { label: "+1 Qtr", days: 90 }
                                    ]

                                    Rectangle {
                                        implicitHeight: 20
                                        implicitWidth: qTxt.implicitWidth + 10
                                        radius: 10
                                        color: qMa.containsMouse ? "#21262d" : "#0d1117"
                                        border.color: qMa.containsMouse ? "#58a6ff" : "#30363d"

                                        Text {
                                            id: qTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.pixelSize: 9
                                            font.weight: Font.DemiBold
                                            color: qMa.containsMouse ? "#58a6ff" : "#8b949e"
                                        }

                                        MouseArea {
                                            id: qMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var d = new Date();
                                                d.setDate(d.getDate() + modelData.days);
                                                var y = d.getFullYear();
                                                var m = (d.getMonth() + 1 < 10 ? "0" : "") + (d.getMonth() + 1);
                                                var dd = (d.getDate() < 10 ? "0" : "") + d.getDate();
                                                mDateInput.text = y + "-" + m + "-" + dd;
                                                root.editingMilestoneDate = mDateInput.text;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Category Dropdown
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4
                            Text { text: "CATEGORY"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                            ComboBox {
                                id: mCatCombo
                                Layout.fillWidth: true
                                implicitHeight: 32
                                font.pixelSize: 12
                                model: root.categoriesList
                                textRole: "name"
                                background: Rectangle { color: "#0d1117"; radius: 4; border.color: "#30363d" }
                                contentItem: RowLayout {
                                    spacing: 6
                                    Text {
                                        text: mCatCombo.currentIndex >= 0 && root.categoriesList[mCatCombo.currentIndex] ? root.categoriesList[mCatCombo.currentIndex].icon : "🚩"
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        text: mCatCombo.currentText
                                        font: mCatCombo.font
                                        color: "#f0f6fc"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }

                        // Description
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4
                            Text { text: "DESCRIPTION (OPTIONAL)"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                            TextField {
                                id: mDescInput
                                Layout.fillWidth: true
                                implicitHeight: 32
                                font.pixelSize: 12
                                color: "#f0f6fc"
                                placeholderText: "Short description / scope..."
                                placeholderTextColor: "#484f58"
                                background: Rectangle { color: "#0d1117"; radius: 4; border.color: mDescInput.activeFocus ? "#58a6ff" : "#30363d" }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // Form Buttons
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Button {
                                text: "Reset"
                                Layout.fillWidth: true
                                implicitHeight: 32
                                font.pixelSize: 11
                                contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter }
                                background: Rectangle { radius: 6; color: parent.hovered ? "#30363d" : "#21262d" }
                                onClicked: root.resetMilestoneForm()
                            }

                            Button {
                                text: root.editingMilestoneId > 0 ? "💾 Update" : "➕ Save"
                                Layout.fillWidth: true
                                implicitHeight: 32
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                contentItem: Text { text: parent.text; font: parent.font; color: "#ffffff"; horizontalAlignment: Text.AlignHCenter }
                                background: Rectangle { radius: 6; color: parent.hovered ? "#2ea043" : "#238636"; border.color: "#3fb950" }
                                onClicked: {
                                    var n = mNameInput.text.trim();
                                    var d = mDateInput.text.trim();
                                    var catObj = root.categoriesList[mCatCombo.currentIndex];
                                    var catId = catObj ? catObj.id : "general";
                                    var desc = mDescInput.text.trim();

                                    if (!n || !d) return;

                                    if (backend) {
                                        var res = backend.save_milestone(n, d, catId, desc, root.editingMilestoneId);
                                        if (res && res.success) {
                                            root.resetMilestoneForm();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // TAB 1: Category Appearances Customizer
            // ==========================================
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                visible: root.currentTab === 1

                // Left: Categories List
                Rectangle {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    color: "#0d1117"
                    radius: 8
                    border.color: "#30363d"
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            color: "#161b22"
                            border.color: "#30363d"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                Text { text: "MILESTONE CATEGORIES"; font.pixelSize: 11; font.weight: Font.Bold; color: "#8b949e" }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: "➕ New Category"
                                    font.pixelSize: 11
                                    contentItem: Text { text: parent.text; font: parent.font; color: "#3fb950" }
                                    background: Rectangle { implicitHeight: 22; implicitWidth: 105; radius: 4; color: parent.hovered ? "#162b20" : "transparent"; border.color: "#238636" }
                                    onClicked: root.resetCategoryForm()
                                }
                            }
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ListView {
                                width: parent.width
                                model: root.categoriesList
                                spacing: 6
                                delegate: Rectangle {
                                    width: parent.width - 16
                                    height: 50
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    radius: 6
                                    color: (root.editingCatId === modelData.id) ? "#1f242c" : (cItemMa.containsMouse ? "#161b22" : "#0d1117")
                                    border.color: (root.editingCatId === modelData.id) ? modelData.color : "#30363d"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 10

                                        // Badge Preview
                                        Rectangle {
                                            implicitWidth: 32; implicitHeight: 32; radius: 6
                                            color: modelData.bg_color || "#16243b"
                                            border.color: modelData.color || "#388bfd"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.icon || "🚩"
                                                font.pixelSize: 15
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                text: modelData.name
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                color: modelData.color || "#f0f6fc"
                                            }
                                            Text {
                                                text: "Key: " + modelData.id + " · Accent: " + modelData.color + " · BG: " + modelData.bg_color
                                                font.family: "Segoe UI, sans-serif"
                                                font.pixelSize: 10
                                                color: "#8b949e"
                                            }
                                        }

                                        Button {
                                            text: "✏️"
                                            font.pixelSize: 11
                                            background: Rectangle { implicitWidth: 26; implicitHeight: 26; radius: 4; color: parent.hovered ? "#30363d" : "transparent" }
                                            onClicked: root.editCategory(modelData)
                                        }

                                        Button {
                                            visible: modelData.id !== "general"
                                            text: "🗑️"
                                            font.pixelSize: 11
                                            background: Rectangle { implicitWidth: 26; implicitHeight: 26; radius: 4; color: parent.hovered ? "#3c1e1e" : "transparent" }
                                            onClicked: {
                                                if (backend) {
                                                    backend.delete_milestone_category(modelData.id);
                                                    if (root.editingCatId === modelData.id) root.resetCategoryForm();
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: cItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        propagateComposedEvents: true
                                        onClicked: root.editCategory(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // Right: Category Customizer Form
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 420
                    color: "#161b22"
                    radius: 8
                    border.color: "#30363d"
                    clip: true

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 14
                        clip: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 12

                            Text {
                                text: root.editingCatId !== "" ? ("Edit Category: " + root.editingCatName) : "Add Category"
                                font.family: "Segoe UI, sans-serif"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#58a6ff"
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#30363d" }

                            // Display Name
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Text { text: "CATEGORY DISPLAY NAME"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                TextField {
                                    id: cNameInput
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    font.pixelSize: 12
                                    color: "#f0f6fc"
                                    placeholderText: "e.g. Internal Process (DDQS)"
                                    placeholderTextColor: "#484f58"
                                    background: Rectangle { color: "#0d1117"; radius: 4; border.color: cNameInput.activeFocus ? "#58a6ff" : "#30363d" }
                                }
                            }

                            // Icon / Emoji
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Text { text: "ICON / EMOJI"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    TextField {
                                        id: cIconInput
                                        Layout.preferredWidth: 50
                                        implicitHeight: 32
                                        font.pixelSize: 14
                                        color: "#f0f6fc"
                                        text: "🔷"
                                        horizontalAlignment: Text.AlignHCenter
                                        background: Rectangle { color: "#0d1117"; radius: 4; border.color: "#30363d" }
                                    }
                                    // Quick emoji choices
                                    Row {
                                        spacing: 4
                                        Repeater {
                                            model: ["⚙️", "🔷", "🚀", "🏁", "🚩", "⭐", "🔒", "🧪", "📦", "🎯"]
                                            Button {
                                                text: modelData
                                                font.pixelSize: 13
                                                background: Rectangle { implicitWidth: 26; implicitHeight: 26; radius: 4; color: parent.hovered ? "#30363d" : "#21262d" }
                                                onClicked: cIconInput.text = modelData
                                            }
                                        }
                                    }
                                }
                            }

                            // Accent Color
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Text { text: "TEXT / BORDER COLOR (#HEX)"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        width: 26; height: 26; radius: 4
                                        color: cColorInput.text || "#58a6ff"
                                        border.color: "#30363d"
                                    }
                                    TextField {
                                        id: cColorInput
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 12
                                        color: "#f0f6fc"
                                        text: "#58a6ff"
                                        background: Rectangle { color: "#0d1117"; radius: 4; border.color: "#30363d" }
                                    }
                                }
                                // Quick accent color presets
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: ["#58a6ff", "#3fb950", "#d29922", "#f85149", "#bc8cff", "#f0883e", "#79c0ff", "#ff7b72"]
                                        Rectangle {
                                            width: 22; height: 22; radius: 4
                                            color: modelData
                                            border.color: cColorInput.text === modelData ? "#ffffff" : "#30363d"
                                            border.width: cColorInput.text === modelData ? 2 : 1
                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: cColorInput.text = modelData
                                            }
                                        }
                                    }
                                }
                            }

                            // Background Color
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Text { text: "BACKGROUND COLOR (#HEX)"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        width: 26; height: 26; radius: 4
                                        color: cBgInput.text || "#0d2344"
                                        border.color: "#30363d"
                                    }
                                    TextField {
                                        id: cBgInput
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        font.family: "Consolas, monospace"
                                        font.pixelSize: 12
                                        color: "#f0f6fc"
                                        text: "#0d2344"
                                        background: Rectangle { color: "#0d1117"; radius: 4; border.color: "#30363d" }
                                    }
                                }
                                // Quick background color presets
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: ["#0d2344", "#16243b", "#162b20", "#2d2006", "#3d1417", "#271d38", "#161b22", "#0d1117"]
                                        Rectangle {
                                            width: 22; height: 22; radius: 4
                                            color: modelData
                                            border.color: cBgInput.text === modelData ? "#58a6ff" : "#30363d"
                                            border.width: cBgInput.text === modelData ? 2 : 1
                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: cBgInput.text = modelData
                                            }
                                        }
                                    }
                                }
                            }

                            // Live Badge Preview
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "LIVE PREVIEW"; font.pixelSize: 10; font.weight: Font.Bold; color: "#8b949e" }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: 8
                                    color: cBgInput.text || "#0d2344"
                                    border.color: cColorInput.text || "#58a6ff"
                                    border.width: 1.5

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { text: cIconInput.text || "🚩"; font.pixelSize: 18 }
                                        Text {
                                            text: cNameInput.text || "Preview Category Badge"
                                            font.family: "Segoe UI, sans-serif"
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            color: cColorInput.text || "#58a6ff"
                                        }
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 4 }

                            // Buttons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    text: "Reset"
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    font.pixelSize: 11
                                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter }
                                    background: Rectangle { radius: 6; color: parent.hovered ? "#30363d" : "#21262d" }
                                    onClicked: root.resetCategoryForm()
                                }

                                Button {
                                    text: root.editingCatId !== "" ? "💾 Save Appearance" : "➕ Add Category"
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    contentItem: Text { text: parent.text; font: parent.font; color: "#ffffff"; horizontalAlignment: Text.AlignHCenter }
                                    background: Rectangle { radius: 6; color: parent.hovered ? "#2ea043" : "#238636"; border.color: "#3fb950" }
                                    onClicked: {
                                        var n = cNameInput.text.trim();
                                        var col = cColorInput.text.trim();
                                        var bg = cBgInput.text.trim();
                                        var ico = cIconInput.text.trim();
                                        if (!n) return;

                                        if (backend) {
                                            var res = backend.save_milestone_category(root.editingCatId, n, col, bg, ico, 0);
                                            if (res && res.success) {
                                                root.resetCategoryForm();
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

    // ==========================================
    // Interactive Calendar Date Picker Popover
    // ==========================================
    Popup {
        id: datePickerPopup
        parent: Overlay.overlay
        x: Math.min(Overlay.overlay ? Overlay.overlay.width - width - 20 : 0, Math.max(20, (mDateInput.mapToItem(Overlay.overlay, 0, 0).x - 120)))
        y: Math.min(Overlay.overlay ? Overlay.overlay.height - height - 20 : 0, mDateInput.mapToItem(Overlay.overlay, 0, 0).y + mDateInput.height + 6)
        width: 320
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 12

        background: Rectangle {
            color: "#161b22"
            radius: 8
            border.color: "#30363d"
            border.width: 1
            // Subtle glow border
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                border.color: "#58a6ff"
                border.width: 1
                opacity: 0.25
            }
        }

        function openOrToggle() {
            if (visible) {
                close();
            } else {
                root.syncPickerWithDateString(mDateInput.text);
                open();
            }
        }

        contentItem: ColumnLayout {
            spacing: 8

            // Calendar Navigation Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Button {
                    text: "◀"
                    implicitWidth: 28
                    implicitHeight: 28
                    font.pixelSize: 11
                    contentItem: Text { text: parent.text; font: parent.font; color: "#f0f6fc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 4; color: parent.hovered ? "#30363d" : "#21262d" }
                    onClicked: {
                        if (root.pickerMonth === 0) {
                            root.pickerMonth = 11;
                            root.pickerYear--;
                        } else {
                            root.pickerMonth--;
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.monthNames[root.pickerMonth] + " " + root.pickerYear
                    font.family: "Segoe UI, sans-serif"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: "#f0f6fc"
                    horizontalAlignment: Text.AlignHCenter
                }

                Button {
                    text: "▶"
                    implicitWidth: 28
                    implicitHeight: 28
                    font.pixelSize: 11
                    contentItem: Text { text: parent.text; font: parent.font; color: "#f0f6fc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 4; color: parent.hovered ? "#30363d" : "#21262d" }
                    onClicked: {
                        if (root.pickerMonth === 11) {
                            root.pickerMonth = 0;
                            root.pickerYear++;
                        } else {
                            root.pickerMonth++;
                        }
                    }
                }
            }

            // Year Jump Controls
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Button {
                    text: "−1 Year"
                    Layout.fillWidth: true
                    implicitHeight: 22
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 3; color: parent.hovered ? "#21262d" : "#0d1117"; border.color: "#30363d" }
                    onClicked: root.pickerYear--
                }

                Button {
                    text: "+1 Year"
                    Layout.fillWidth: true
                    implicitHeight: 22
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 3; color: parent.hovered ? "#21262d" : "#0d1117"; border.color: "#30363d" }
                    onClicked: root.pickerYear++
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#30363d" }

            // Weekday Column Headers (Mo, Tu, We, Th, Fr, Sa, Su)
            RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Item {
                        Layout.fillWidth: true
                        height: 20
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: (modelData === "Sa" || modelData === "Su") ? "#f85149" : "#8b949e"
                        }
                    }
                }
            }

            // Days Grid (6 rows x 7 cols = 42 cells)
            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: 3
                columnSpacing: 2

                Repeater {
                    model: root.getCalendarCells(root.pickerYear, root.pickerMonth, mDateInput.text)

                    Rectangle {
                        Layout.fillWidth: true
                        height: 28
                        radius: 4
                        color: {
                            if (modelData.isSelected) return "#1f6feb";
                            if (dayMa.containsMouse) return "#30363d";
                            if (modelData.isToday) return "#162b20";
                            return "transparent";
                        }
                        border.color: {
                            if (modelData.isSelected) return "#58a6ff";
                            if (modelData.isToday) return "#3fb950";
                            return "transparent";
                        }
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.day.toString()
                            font.family: "Segoe UI, sans-serif"
                            font.pixelSize: 11
                            font.weight: (modelData.isSelected || modelData.isToday) ? Font.Bold : Font.Normal
                            color: {
                                if (modelData.isSelected) return "#ffffff";
                                if (modelData.isToday) return "#3fb950";
                                if (!modelData.isCurrentMonth) return "#484f58";
                                return "#f0f6fc";
                            }
                        }

                        MouseArea {
                            id: dayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                mDateInput.text = modelData.dateStr;
                                root.editingMilestoneDate = modelData.dateStr;
                                datePickerPopup.close();
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#30363d" }

            // Footer Quick Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Button {
                    text: "Today"
                    Layout.fillWidth: true
                    implicitHeight: 26
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#58a6ff"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 4; color: parent.hovered ? "#21262d" : "#0d1117"; border.color: "#30363d" }
                    onClicked: {
                        var now = new Date();
                        var y = now.getFullYear();
                        var m = (now.getMonth() + 1 < 10 ? "0" : "") + (now.getMonth() + 1);
                        var d = (now.getDate() < 10 ? "0" : "") + now.getDate();
                        mDateInput.text = y + "-" + m + "-" + d;
                        root.editingMilestoneDate = mDateInput.text;
                        datePickerPopup.close();
                    }
                }

                Button {
                    text: "Clear"
                    Layout.fillWidth: true
                    implicitHeight: 26
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#8b949e"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 4; color: parent.hovered ? "#21262d" : "#0d1117"; border.color: "#30363d" }
                    onClicked: {
                        mDateInput.text = "";
                        root.editingMilestoneDate = "";
                        datePickerPopup.close();
                    }
                }

                Button {
                    text: "Close"
                    Layout.fillWidth: true
                    implicitHeight: 26
                    font.pixelSize: 10
                    contentItem: Text { text: parent.text; font: parent.font; color: "#f0f6fc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 4; color: parent.hovered ? "#30363d" : "#21262d" }
                    onClicked: datePickerPopup.close()
                }
            }
        }
    }
}
