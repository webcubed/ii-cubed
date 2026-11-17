import "periodic_table.js" as PTable
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Periodic table page of the cheat sheet.
 *
 * Type anywhere to search: letters match a symbol or name, digits match an
 * atomic number. Backspace edits, Escape clears the query (a second Escape
 * closes the cheat sheet), Enter selects the best match. Clicking a tile shows
 * it in the readout; colours follow the five element categories with a legend
 * underneath.
 */
Item {
    id: root
    readonly property var elements: PTable.elements
    readonly property var series: PTable.series
    property real spacing: 6

    property string query: ""
    property var selected: null

    focus: true
    implicitWidth: mainLayout.implicitWidth
    implicitHeight: mainLayout.implicitHeight

    readonly property var categories: [
        { "type": "metal", "name": Translation.tr("Metal") },
        { "type": "nonmetal", "name": Translation.tr("Nonmetal") },
        { "type": "noblegas", "name": Translation.tr("Noble gas") },
        { "type": "lanthanum", "name": Translation.tr("Lanthanide") },
        { "type": "actinium", "name": Translation.tr("Actinide") }
    ]

    /// Every element with the period/group its slot implies, for the readout.
    readonly property var flatElements: {
        const list = [];
        for (let row = 0; row < root.elements.length; row += 1) {
            const cells = root.elements[row];
            for (let column = 0; column < cells.length; column += 1) {
                const element = cells[column];
                if (element.type === "empty")
                    continue;
                list.push(Object.assign({}, element, { "period": row + 1, "group": column + 1, "series": false }));
            }
        }
        for (let index = 0; index < root.series.length; index += 1) {
            const cells = root.series[index];
            for (let column = 0; column < cells.length; column += 1) {
                const element = cells[column];
                if (element.type === "empty")
                    continue;
                list.push(Object.assign({}, element, { "period": index === 0 ? 6 : 7, "group": 0, "series": true }));
            }
        }
        return list;
    }

    /// Numbers of the elements the query matches, or null when the query is empty.
    readonly property var matchingNumbers: {
        if (root.query.length === 0)
            return null;
        const numbers = {};
        for (const element of root.flatElements) {
            if (root.score(element) > 0)
                numbers[element.number] = true;
        }
        return numbers;
    }
    readonly property int matchCount: root.matchingNumbers === null ? 0 : Object.keys(root.matchingNumbers).length

    function score(element) {
        const query = root.query.toLowerCase();
        if (query.length === 0)
            return 0;
        const symbol = String(element.symbol ?? "").toLowerCase();
        const name = String(element.name ?? "").toLowerCase();
        if (String(element.number) === query)
            return 100;
        if (symbol === query)
            return 90;
        if (symbol.startsWith(query))
            return 80;
        if (name.startsWith(query))
            return 70;
        if (name.includes(query))
            return 50;
        return 0;
    }

    function bestMatch() {
        let best = null;
        let bestScore = 0;
        for (const element of root.flatElements) {
            const value = root.score(element);
            if (value > bestScore) {
                best = element;
                bestScore = value;
            }
        }
        return best;
    }

    function typeName(type) {
        const category = root.categories.find(item => item.type === type);
        return category ? category.name : type;
    }

    function categoryColor(type) {
        switch (type) {
        case "metal": return Appearance.colors.colPrimary;
        case "nonmetal": return Appearance.colors.colSecondary;
        case "noblegas": return Appearance.colors.colTertiary;
        case "lanthanum": return Appearance.colors.colError;
        case "actinium": return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colTertiary, 0.45);
        default: return Appearance.colors.colSubtext;
        }
    }

    function typeCharacter(character) {
        root.query += character;
        root.selected = root.bestMatch();
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Backspace) {
            if (root.query.length > 0) {
                root.query = root.query.slice(0, -1);
                root.selected = root.bestMatch();
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Escape) {
            if (root.query.length > 0) {
                root.query = "";
                root.selected = null;
                event.accepted = true;
            }
            return; // otherwise let the cheat sheet close
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const match = root.bestMatch();
            if (match) {
                root.selected = match;
                event.accepted = true;
            }
            return;
        }
        const text = String(event.text ?? "");
        const blocked = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) !== 0;
        if (!blocked && text.length === 1 && text.trim().length === 1) {
            root.typeCharacter(text);
            event.accepted = true;
        }
    }

    ColumnLayout {
        id: mainLayout
        anchors.centerIn: parent
        spacing: root.spacing

        // Search chip + selected element readout
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: searchRow.implicitWidth + 20
                implicitHeight: 34
                radius: Appearance.rounding.full
                color: root.query.length > 0
                    ? Appearance.colors.colPrimaryContainer
                    : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.25)

                RowLayout {
                    id: searchRow
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "search"
                        iconSize: 18
                        color: root.query.length > 0
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        color: root.query.length > 0
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: {
                            if (root.query.length === 0)
                                return Translation.tr("Type to search — name, symbol or number");
                            const count = root.matchCount;
                            return `${root.query}  ·  ${count} ${count === 1 ? Translation.tr("match") : Translation.tr("matches")}`;
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: root.selected !== null
                implicitWidth: readoutRow.implicitWidth + 20
                implicitHeight: 34
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize(root.selected ? root.categoryColor(root.selected.type) : Appearance.colors.colPrimary, 0.82)

                RowLayout {
                    id: readoutRow
                    anchors.centerIn: parent
                    spacing: 8

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        color: root.selected ? root.categoryColor(root.selected.type) : Appearance.colors.colPrimary
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.monospace
                        text: root.selected ? `${root.selected.number}  ${root.selected.symbol}` : ""
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: root.selected
                            ? root.selected.name + " · " + root.typeName(root.selected.type)
                                + " · " + root.selected.weight + " u · "
                                + (root.selected.series
                                    ? Translation.tr("f-block")
                                    : Translation.tr("period %1, group %2").arg(root.selected.period).arg(root.selected.group))
                            : ""
                    }
                }
            }
        }

        // Main table
        Repeater {
            model: root.elements

            delegate: Row {
                id: tableRow
                spacing: root.spacing
                required property var modelData

                Repeater {
                    model: tableRow.modelData

                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                        dimmed: root.matchingNumbers !== null && !root.matchingNumbers[modelData.number]
                        isSelected: root.selected !== null && root.selected.number === modelData.number
                        onPicked: (element) => { root.selected = element }
                    }
                }
            }
        }

        Item {
            id: gap
            implicitHeight: 20
        }

        // Lanthanides and actinides
        Repeater {
            model: root.series

            delegate: Row {
                id: seriesTableRow
                spacing: root.spacing
                required property var modelData

                Repeater {
                    model: seriesTableRow.modelData

                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                        dimmed: root.matchingNumbers !== null && !root.matchingNumbers[modelData.number]
                        isSelected: root.selected !== null && root.selected.number === modelData.number
                        onPicked: (element) => { root.selected = element }
                    }
                }
            }
        }

        // Legend
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 16

            Repeater {
                model: root.categories

                delegate: RowLayout {
                    required property var modelData
                    spacing: 6

                    Rectangle {
                        implicitWidth: 10
                        implicitHeight: 10
                        radius: Appearance.rounding.full
                        color: root.categoryColor(modelData.type)
                    }

                    StyledText {
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: modelData.name
                    }
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Enter selects the best match · Esc clears")
            }
        }
    }
}
