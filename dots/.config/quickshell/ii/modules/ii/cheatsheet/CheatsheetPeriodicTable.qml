import "palette.js" as Mac
import "periodic_table.js" as PTable
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Periodic table page of the cheat sheet, built for AP Chemistry.
 *
 * Type anywhere to search: letters match a symbol or name, digits match an
 * atomic number, and the query shows in the search bar above the table. "/"
 * puts the caret in that bar, so a search can start with a letter that is also
 * a layer key. Arrow keys walk the table square by square, Backspace edits the
 * query, Escape clears it (a second Escape closes the cheat sheet) and Enter
 * jumps to the best match. Clicking a tile works too.
 *
 * Layers: c = category, e = electronegativity, r = atomic radius, i = first
 * ionization energy, b = block, p = phase at STP. A numeric layer recolours
 * the table as a heat map and puts the value on every tile, so the trends are
 * visible at a glance. Pressing the same key again goes back to categories.
 *
 * The card under the table spells out the selected element: Pauling
 * electronegativity, radius, first ionization energy, phase, every oxidation
 * state (the common ones filled in) and the electron configuration as
 * noble-gas shorthand plus the full expansion.
 */
Item {
    id: root
    readonly property var elements: PTable.elements
    readonly property var series: PTable.series

    property real tileSize: 62
    property real spacing: 5
    readonly property int columnCount: root.elements.length > 0 ? root.elements[0].length : 18
    readonly property real tableWidth: root.columnCount * root.tileSize + Math.max(0, root.columnCount - 1) * root.spacing

    /// Set by Cheatsheet.qml when this page is instantiated.
    property int tabIndex: -1
    readonly property bool isCurrentPage: root.tabIndex >= 0 && root.tabIndex === Persistent.states.cheatsheet.tabIndex

    /// The search text. The bar above the table mirrors it, so what has been
    /// typed is always on screen, and typing in the bar updates it back.
    property string query: ""
    // Started in Component.onCompleted: the merged grid is built from two
    // derived bindings, so reading it from here could see an empty grid and
    // leave the detail card blank until something was clicked.
    property var selected: null

    /// "category" | "en" | "radius" | "ionization" | "block" | "phase"
    property string overlay: "category"

    // Oxidation states of the selection, already merged with its reference data.
    readonly property var selectedStates: root.selected && root.selected.ox ? root.selected.ox : []
    readonly property var selectedCommonStates: root.selected && root.selected.common ? root.selected.common : []

    Component.onCompleted: {
        if (!root.selected && root.flatElements.length > 0)
            root.selected = root.flatElements[0];
    }

    focus: true
    implicitWidth: root.tableWidth + 14
    implicitHeight: mainLayout.implicitHeight + 8

    readonly property var categories: [
        { "type": "metal", "name": Translation.tr("Metal") },
        { "type": "nonmetal", "name": Translation.tr("Nonmetal") },
        { "type": "noblegas", "name": Translation.tr("Noble gas") },
        { "type": "lanthanum", "name": Translation.tr("Lanthanide") },
        { "type": "actinium", "name": Translation.tr("Actinide") }
    ]

    readonly property var overlayModes: [
        { "id": "category", "key": "c", "title": Translation.tr("Category") },
        { "id": "en", "key": "e", "title": Translation.tr("Electronegativity") },
        { "id": "radius", "key": "r", "title": Translation.tr("Atomic radius") },
        { "id": "ionization", "key": "i", "title": Translation.tr("Ionization energy") },
        { "id": "block", "key": "b", "title": Translation.tr("Block") },
        { "id": "phase", "key": "p", "title": Translation.tr("Phase at STP") }
    ]

    readonly property bool numericOverlay: root.overlay === "en" || root.overlay === "radius" || root.overlay === "ionization"

    /**
     * One tile's worth of data: the raw cell plus its reference data
     * (electronegativity, radius, ionisation, phase, configuration) and the
     * slot it sits in. The tiles are built from these copies, so the trend
     * colours and the bottom labels have something to read.
     */
    function mergedCell(element, row, column, seriesIndex) {
        if (!element || element.type === "empty")
            return element;
        return Object.assign({}, element, PTable.detailFor(element.number), {
            "period": seriesIndex >= 0 ? (seriesIndex === 0 ? 6 : 7) : row + 1,
            "group": seriesIndex >= 0 ? 0 : column + 1,
            "row": row,
            "column": column,
            "series": seriesIndex >= 0
        });
    }

    /// Period rows as drawn, with the reference data merged in.
    readonly property var tableRows: {
        const rows = [];
        for (let row = 0; row < root.elements.length; row += 1) {
            const cells = [];
            const source = root.elements[row];
            for (let column = 0; column < source.length; column += 1)
                cells.push(root.mergedCell(source[column], row, column, -1));
            rows.push(cells);
        }
        return rows;
    }

    /// The two f-block rows as drawn, with the reference data merged in.
    readonly property var seriesTableRows: {
        const rows = [];
        for (let index = 0; index < root.series.length; index += 1) {
            const cells = [];
            const row = root.elements.length + index;
            const source = root.series[index];
            for (let column = 0; column < source.length; column += 1)
                cells.push(root.mergedCell(source[column], row, column, index));
            rows.push(cells);
        }
        return rows;
    }

    /**
     * Every element with its slot on one grid (period rows first, then the two
     * f-block rows) so arrow keys can move by geometry instead of by index.
     * These are the very objects the tiles draw, so a selection made with the
     * keyboard, a tile click or the search always carries the reference data.
     */
    readonly property var flatElements: {
        const list = [];
        for (const cells of root.tableRows.concat(root.seriesTableRows)) {
            for (const element of cells) {
                if (element && element.type !== "empty")
                    list.push(element);
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
        case "metal": return Mac.colors.blue;
        case "nonmetal": return Mac.colors.green;
        case "noblegas": return Mac.colors.mauve;
        case "lanthanum": return Mac.colors.peach;
        case "actinium": return Mac.colors.pink;
        default: return Mac.colors.subtext0;
        }
    }

    /// s/p/d/f, derived from the slot (He is the one s-block element on the right).
    function blockOf(element) {
        if (element.series || element.group === 0)
            return "f";
        if (element.number === 2 || element.group <= 2)
            return "s";
        return element.group >= 13 ? "p" : "d";
    }

    // Block and phase colours are Macchiato hues instead of theme roles: the
    // theme's primary/secondary/tertiary are close pastels, which made the
    // four blocks and the three phases impossible to tell apart.
    function blockColor(block) {
        switch (block) {
        case "s": return Mac.colors.red;
        case "p": return Mac.colors.blue;
        case "d": return Mac.colors.peach;
        default: return Mac.colors.green; // f
        }
    }

    function phaseColor(phase) {
        switch (phase) {
        case "solid": return Mac.colors.overlay2; // grey
        case "liquid": return Mac.colors.blue; // blue
        case "gas": return Mac.colors.text; // white
        default: return Mac.colors.subtext0;
        }
    }

    readonly property bool blockOrPhase: root.overlay === "block" || root.overlay === "phase"

    /// How much of the layer colour goes into a tile's fill. Blocks and phases
    /// need a stronger tint than categories to be read across the table, and a
    /// thin accent ring on top of that tint keeps the tiles from blurring into
    /// one another.
    // 0.42 is not arbitrary: at that transparency the block and phase colours
    // paint the tile light enough that the measured contrast in ElementTile
    // picks its dark glyph, which is what a pale gas tile needs. The numeric
    // layers stay darker so their heat colours keep the accent glyph.
    function tileFillStrength() {
        if (root.blockOrPhase)
            return 0.42;
        return root.numericOverlay ? 0.70 : 0.86;
    }

    function overlayMode(id) {
        return root.overlayModes.find(mode => mode.id === id) ?? root.overlayModes[0];
    }

    function toggleOverlay(id) {
        root.overlay = root.overlay === id ? "category" : id;
    }

    /// The number behind a numeric layer, or null.
    function overlayNumber(element) {
        if (root.overlay === "en")
            return element.en;
        if (root.overlay === "radius")
            return element.radius;
        if (root.overlay === "ionization")
            return element.ionization;
        return null;
    }

    readonly property var overlayRange: {
        let low = Infinity;
        let high = -Infinity;
        for (const element of root.flatElements) {
            const value = root.overlayNumber(element);
            if (value === null || value === undefined)
                continue;
            low = Math.min(low, value);
            high = Math.max(high, value);
        }
        if (!isFinite(low) || high <= low)
            return { "low": 0, "high": 1 };
        return { "low": low, "high": high };
    }

    readonly property color trendLowColor: Mac.colors.blue
    readonly property color trendHighColor: Mac.colors.red

    function trendColor(element) {
        switch (root.overlay) {
        case "block":
            return root.blockColor(root.blockOf(element));
        case "phase":
            return root.phaseColor(element.phase);
        case "en":
        case "radius":
        case "ionization": {
            const value = root.overlayNumber(element);
            if (value === null || value === undefined)
                return Appearance.colors.colSubtext;
            const span = root.overlayRange.high - root.overlayRange.low;
            const proportion = span > 0 ? (value - root.overlayRange.low) / span : 0.5;
            // ColorUtils.mix(a, b, p) is all b at p = 0 and all a at p = 1, so
            // the high colour comes first: biggest value = hottest = red.
            return ColorUtils.mix(root.trendHighColor, root.trendLowColor, proportion);
        }
        default:
            return root.categoryColor(element.type);
        }
    }

    /// Bottom line of a tile: whatever the active layer is about.
    function tileLabel(element) {
        switch (root.overlay) {
        case "en":
            return element.en === null || element.en === undefined ? "—" : element.en.toFixed(2);
        case "radius":
            return element.radius === null || element.radius === undefined ? "—" : element.radius + " pm";
        case "ionization":
            return element.ionization === null || element.ionization === undefined ? "—" : Math.round(element.ionization) + " kJ";
        case "block":
            return root.blockOf(element) + "-block";
        case "phase":
            return element.phase ?? "—";
        default:
            return element.name;
        }
    }

    readonly property var legendEntries: {
        switch (root.overlay) {
        case "block":
            return [
                { "label": "s", "color": root.blockColor("s") },
                { "label": "p", "color": root.blockColor("p") },
                { "label": "d", "color": root.blockColor("d") },
                { "label": "f", "color": root.blockColor("f") }
            ];
        case "phase":
            return [
                { "label": Translation.tr("Solid"), "color": root.phaseColor("solid") },
                { "label": Translation.tr("Liquid"), "color": root.phaseColor("liquid") },
                { "label": Translation.tr("Gas"), "color": root.phaseColor("gas") }
            ];
        default:
            return root.categories.map(category => ({ "label": category.name, "color": root.categoryColor(category.type) }));
        }
    }

    function rangeLabel(value) {
        if (root.overlay === "en")
            return value.toFixed(2);
        return String(Math.round(value));
    }

    function overlayUnit() {
        if (root.overlay === "radius")
            return " pm";
        if (root.overlay === "ionization")
            return " kJ";
        return "";
    }

    function positionLabel(element) {
        if (element.series)
            return Translation.tr("period %1 · f-block").arg(element.period);
        return Translation.tr("period %1 · group %2 · %3-block").arg(element.period).arg(element.group).arg(root.blockOf(element));
    }

    function subtitle(element) {
        return element.number + " · " + root.typeName(element.type) + " · " + root.positionLabel(element)
            + " · " + (element.phase ?? "—") + " at STP";
    }

    function electronegativityLabel(element) {
        if (!element || element.en === null || element.en === undefined)
            return "—";
        return element.en.toFixed(2);
    }

    function radiusLabel(element) {
        if (!element || element.radius === null || element.radius === undefined)
            return "—";
        return element.radius + " pm";
    }

    function ionizationLabel(element) {
        if (!element || element.ionization === null || element.ionization === undefined)
            return "—";
        return Math.round(element.ionization) + " kJ/mol";
    }

    function configurationLabel(element) {
        return element ? PTable.superscript(element.config) : "";
    }

    function fullConfigurationLabel(element) {
        return element ? PTable.superscript(element.full) : "";
    }

    /**
     * Walk the grid one step in a direction. Same row/column wins, so up and
     * down stay in their group and left and right stay in their period.
     */
    function moveSelection(direction) {
        if (root.flatElements.length === 0)
            return;
        const current = root.selected;
        if (!current) {
            root.select(root.flatElements[0]);
            return;
        }
        const stepX = direction === "left" ? -1 : (direction === "right" ? 1 : 0);
        const stepY = direction === "up" ? -1 : (direction === "down" ? 1 : 0);
        let best = null;
        let bestScore = Infinity;
        for (const candidate of root.flatElements) {
            if (candidate.number === current.number)
                continue;
            const offsetX = candidate.column - current.column;
            const offsetY = candidate.row - current.row;
            const forward = stepX !== 0 ? offsetX * stepX : offsetY * stepY;
            if (forward <= 0)
                continue;
            const drift = Math.abs(stepX !== 0 ? offsetY : offsetX);
            // Sideways drift costs far more than distance, so a neighbour in
            // the same row/column always beats a diagonal one.
            const score = drift * 100 + forward;
            if (score < bestScore) {
                bestScore = score;
                best = candidate;
            }
        }
        if (best)
            root.select(best);
    }

    function typeCharacter(character) {
        root.query += character;
        root.select(root.bestMatch());
    }

    /// Select by atomic number, so the reference data comes along.
    function selectNumber(number) {
        const match = root.flatElements.find(element => element.number === number);
        if (match)
            root.select(match);
    }

    function select(element) {
        root.selected = element;
        Qt.callLater(root.ensureSelectionVisible);
    }

    /// Keep the selected row inside the viewport when the table is taller than it.
    function ensureSelectionVisible() {
        if (!root.selected || !viewport)
            return;
        const element = root.selected;
        const repeater = element.series ? seriesRows : mainRows;
        const rowIndex = element.series ? (element.period === 6 ? 0 : 1) : element.row;
        const rowItem = repeater.itemAt(rowIndex);
        if (!rowItem)
            return;
        const top = rowItem.mapToItem(viewport.contentItem, 0, 0).y;
        const bottom = top + rowItem.height;
        const margin = 24;
        const maxY = Math.max(0, viewport.contentHeight - viewport.height);
        if (top - margin < viewport.contentY)
            viewport.contentY = Math.max(0, Math.min(maxY, top - margin));
        else if (bottom + margin > viewport.contentY + viewport.height)
            viewport.contentY = Math.max(0, Math.min(maxY, bottom + margin - viewport.height));
    }

    /**
     * One place for every key this page understands. The cheat sheet calls it
     * as well, because a tab button usually owns the active focus and the
     * arrows would otherwise never reach this page. Returns true when the key
     * was used up.
     */
    function handleKey(event) {
        const modified = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0;
        if (!modified) {
            let direction = "";
            if (event.key === Qt.Key_Left)
                direction = "left";
            else if (event.key === Qt.Key_Right)
                direction = "right";
            else if (event.key === Qt.Key_Up)
                direction = "up";
            else if (event.key === Qt.Key_Down)
                direction = "down";
            if (direction.length > 0) {
                root.moveSelection(direction);
                return true;
            }
        }
        if (event.key === Qt.Key_Backspace) {
            if (root.query.length > 0) {
                root.query = root.query.slice(0, -1);
                root.select(root.bestMatch());
            }
            return true;
        }
        if (event.key === Qt.Key_Escape) {
            if (root.query.length > 0) {
                root.query = "";
                root.selected = null;
                return true;
            }
            return false; // otherwise let the cheat sheet close
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const match = root.bestMatch();
            if (match) {
                root.select(match);
                return true;
            }
            return false;
        }
        const text = String(event.text ?? "");
        if (!modified && text.length === 1 && text.trim().length === 1) {
            // "/" puts the caret in the search bar; from then on the field
            // takes the letters, so "carbon" can start with a layer key.
            if (text === "/") {
                searchField.forceActiveFocus();
                return true;
            }
            const lower = text.toLowerCase();
            const mode = root.overlayModes.find(item => item.key === lower);
            // A layer key only switches layers while nothing is being searched
            // and the caret is not in the search bar.
            if (mode && root.query.length === 0 && !searchField.activeFocus) {
                root.toggleOverlay(mode.id);
                return true;
            }
            root.typeCharacter(text);
            return true;
        }
        return false;
    }

    Keys.onPressed: (event) => {
        if (root.handleKey(event))
            event.accepted = true;
    }

    // The window's shortcut map runs before key delivery, so the arrows work
    // even when a tab button (not this page) owns keyboard focus.
    Shortcut {
        sequence: "Up"
        enabled: root.isCurrentPage
        onActivated: root.moveSelection("up")
    }
    Shortcut {
        sequence: "Down"
        enabled: root.isCurrentPage
        onActivated: root.moveSelection("down")
    }
    Shortcut {
        sequence: "Left"
        enabled: root.isCurrentPage
        onActivated: root.moveSelection("left")
    }
    Shortcut {
        sequence: "Right"
        enabled: root.isCurrentPage
        onActivated: root.moveSelection("right")
    }

    // Escape inside the search bar belongs to the bar. The window shortcut map
    // runs before key delivery, so the bar clears (and then hands the keyboard
    // back) without depending on the TextField letting the key bubble out. The
    // table's own Escape handling only sees Escape when the bar is not focused.
    Shortcut {
        sequence: "Escape"
        enabled: root.isCurrentPage && searchField.activeFocus
        onActivated: {
            if (searchField.text.length > 0) {
                root.query = "";
                root.selected = null;
            } else {
                root.forceActiveFocus(); // back to the table's keys
            }
        }
    }

    StyledFlickable {
        id: viewport
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(mainLayout.implicitHeight + 8, height)
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainLayout
            width: root.tableWidth
            x: Math.max(0, (viewport.width - width) / 2)
            y: Math.max(4, (viewport.height - implicitHeight) / 2)
            spacing: root.spacing

            // Search bar. The page owns the query and the field mirrors it, so
            // typed text is always visible; "/" puts the caret in the field.
            RowLayout {
                Layout.preferredWidth: root.tableWidth
                spacing: 10

                ToolbarTextField {
                    id: searchField
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillHeight: false
                    Layout.preferredWidth: 330
                    implicitHeight: 34
                    clip: true
                    placeholderText: Translation.tr("Hit \"/\" to search — name, symbol or number")
                    colBackground: Appearance.colors.colSecondaryContainer

                    // Text goes both ways: typing here updates the page, and
                    // anything the page does to the query lands back in the field.
                    Binding {
                        target: searchField
                        property: "text"
                        value: root.query
                        restoreMode: Binding.RestoreNone
                    }
                    onTextChanged: {
                        if (root.query !== text)
                            root.query = text;
                    }
                    onAccepted: {
                        const match = root.bestMatch();
                        if (match)
                            root.select(match);
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.query.length > 0
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: `${root.matchCount} ${root.matchCount === 1 ? Translation.tr("match") : Translation.tr("matches")}`
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("↑ ↓ ← → move  ·  Enter picks  ·  / searches")
                }
            }

            // Layer keys, spelled out: the badge is the key, the label is the
            // trend it puts on the table. A chip does the same as its key.
            RowLayout {
                Layout.preferredWidth: root.tableWidth
                spacing: 6

                Repeater {
                    model: root.overlayModes

                    delegate: RippleButton {
                        id: layerChip
                        required property var modelData
                        readonly property bool active: root.overlay === modelData.id

                        focusPolicy: Qt.NoFocus
                        implicitWidth: chipRow.implicitWidth + 18
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.full
                        colBackground: layerChip.active
                            ? Appearance.colors.colPrimaryContainer
                            : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
                        colBackgroundHover: layerChip.active
                            ? Appearance.colors.colPrimaryContainer
                            : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.05)
                        onClicked: root.toggleOverlay(layerChip.modelData.id)

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                implicitWidth: 16
                                implicitHeight: 16
                                radius: Appearance.rounding.full
                                color: layerChip.active
                                    ? Appearance.colors.colPrimary
                                    : ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)

                                StyledText {
                                    anchors.centerIn: parent
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: layerChip.active
                                        ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnLayer1
                                    text: layerChip.modelData.key
                                }
                            }

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: layerChip.active
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext
                                text: layerChip.modelData.title
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Main table
            Repeater {
                id: mainRows
                model: root.tableRows

                delegate: Row {
                    id: tableRow
                    spacing: root.spacing
                    required property var modelData

                    Repeater {
                        model: tableRow.modelData

                        delegate: ElementTile {
                            required property var modelData
                            element: modelData
                            tileSize: root.tileSize
                            accent: root.trendColor(modelData)
                            fillStrength: root.tileFillStrength()
                            emphasised: root.blockOrPhase
                            bottomLabel: root.tileLabel(modelData)
                            dimmed: root.matchingNumbers !== null && !root.matchingNumbers[modelData.number]
                            isSelected: root.selected !== null && root.selected.number === modelData.number
                            onPicked: (element) => { root.selectNumber(element.number) }
                        }
                    }
                }
            }

            Item {
                id: gap
                implicitHeight: 12
            }

            // Lanthanides and actinides
            Repeater {
                id: seriesRows
                model: root.seriesTableRows

                delegate: Row {
                    id: seriesTableRow
                    spacing: root.spacing
                    required property var modelData

                    Repeater {
                        model: seriesTableRow.modelData

                        delegate: ElementTile {
                            required property var modelData
                            element: modelData
                            tileSize: root.tileSize
                            accent: root.trendColor(modelData)
                            fillStrength: root.tileFillStrength()
                            emphasised: root.blockOrPhase
                            bottomLabel: root.tileLabel(modelData)
                            dimmed: root.matchingNumbers !== null && !root.matchingNumbers[modelData.number]
                            isSelected: root.selected !== null && root.selected.number === modelData.number
                            onPicked: (element) => { root.selectNumber(element.number) }
                        }
                    }
                }
            }

            // Selected element
            Rectangle {
                id: detailCard
                Layout.preferredWidth: root.tableWidth
                implicitWidth: root.tableWidth
                implicitHeight: detailRow.implicitHeight + 22
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.4)
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    id: detailRow
                    anchors.fill: parent
                    anchors.margins: 11
                    spacing: 14

                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.maximumWidth: 250
                        spacing: 10

                        Rectangle {
                            implicitWidth: 42
                            implicitHeight: 42
                            radius: Appearance.rounding.small
                            color: ColorUtils.transparentize(
                                root.selected ? root.categoryColor(root.selected.type) : Appearance.colors.colPrimary, 0.82)

                            StyledText {
                                anchors.centerIn: parent
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: root.selected ? root.categoryColor(root.selected.type) : Appearance.colors.colSubtext
                                text: root.selected ? root.selected.symbol : "·"
                            }
                        }

                        ColumnLayout {
                            spacing: 1

                            StyledText {
                                Layout.preferredWidth: 185
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                                text: root.selected
                                    ? root.selected.name
                                    : (root.query.length > 0 ? Translation.tr("No match") : Translation.tr("Select an element"))
                            }

                            StyledText {
                                Layout.preferredWidth: 185
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: root.selected
                                    ? root.subtitle(root.selected)
                                    : Translation.tr("Type a name, symbol or number")
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.topMargin: 3
                        Layout.bottomMargin: 3
                        implicitWidth: 1
                        color: Appearance.colors.colLayer0Border
                    }

                    // Trends
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 18

                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Electronegativity")
                            }
                            StyledText {
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                                text: root.electronegativityLabel(root.selected)
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Radius (vdW)")
                            }
                            StyledText {
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                                text: root.radiusLabel(root.selected)
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("1st ionization")
                            }
                            StyledText {
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                                text: root.ionizationLabel(root.selected)
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.topMargin: 3
                        Layout.bottomMargin: 3
                        implicitWidth: 1
                        color: Appearance.colors.colLayer0Border
                    }

                    ColumnLayout { // Oxidation states
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4

                        RowLayout {
                            spacing: 6

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Oxidation states")
                            }

                            StyledText {
                                visible: root.selectedCommonStates.length > 0
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                opacity: 0.7
                                text: Translation.tr("filled = common")
                            }
                        }

                        RowLayout {
                            spacing: 4

                            Repeater {
                                model: root.selectedStates

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool isCommon: root.selectedCommonStates.indexOf(modelData) !== -1

                                    implicitWidth: oxidationText.implicitWidth + 10
                                    implicitHeight: 18
                                    radius: Appearance.rounding.full
                                    color: isCommon ? Appearance.colors.colPrimaryContainer : "transparent"
                                    border.width: isCommon ? 0 : 1
                                    border.color: Appearance.colors.colOutline

                                    StyledText {
                                        id: oxidationText
                                        anchors.centerIn: parent
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: isCommon ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                        text: PTable.oxidationLabel(modelData)
                                    }
                                }
                            }

                            StyledText {
                                visible: root.selected !== null && root.selectedStates.length === 0
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: "—"
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.topMargin: 3
                        Layout.bottomMargin: 3
                        implicitWidth: 1
                        color: Appearance.colors.colLayer0Border
                    }

                    ColumnLayout { // Electron configuration
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Electron configuration")
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                            text: root.configurationLabel(root.selected)
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            text: root.fullConfigurationLabel(root.selected)
                        }
                    }
                }
            }

            // Legend for the active layer
            RowLayout {
                Layout.preferredWidth: root.tableWidth
                Layout.topMargin: 2
                spacing: 16

                Repeater {
                    model: root.numericOverlay ? [] : root.legendEntries

                    delegate: RowLayout {
                        required property var modelData
                        spacing: 6

                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: Appearance.rounding.full
                            color: modelData.color
                        }

                        StyledText {
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: modelData.label
                        }
                    }
                }

                RowLayout {
                    visible: root.numericOverlay
                    spacing: 8

                    StyledText {
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: root.overlayMode(root.overlay).title + ":"
                    }

                    StyledText {
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        text: root.rangeLabel(root.overlayRange.low) + root.overlayUnit()
                    }

                    Rectangle {
                        implicitWidth: 140
                        implicitHeight: 8
                        radius: Appearance.rounding.full
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.trendLowColor }
                            GradientStop { position: 1.0; color: root.trendHighColor }
                        }
                    }

                    StyledText {
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        text: root.rangeLabel(root.overlayRange.high) + root.overlayUnit()
                    }
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: root.overlay === "category"
                        ? Translation.tr("press a layer key, or click a chip above")
                        : Translation.tr("%1 — same key or c for categories").arg(root.overlayMode(root.overlay).key)
                }
            }
        }
    }
}
