# Factory Modeller

**Визуальный планировщик производства прямо в Factorio — для тех, кому нравится Satisfactory Modeler.**

Вместо таблиц — граф на холсте: блоки рецептов, связи между ними, фабрики внутри фабрик. Интерфейс построен по образцу Satisfactory Modeler: вы собираете схему мышкой, а мод сам считает потоки, число машин, ленты, топливо и электричество.

> Мод не связан с авторами Satisfactory Modeler — это независимая реализация похожего подхода для Factorio.

---

## Возможности

### Граф производства
- Блоки рецептов, добычи, входов и выходов на холсте; перетаскивание мышью, масштаб колесом, сдвиг холста.
- Связи между портами; клик по порту и затем по пустому месту — меню рецептов, которые производят или потребляют этот предмет, новый блок сразу подключается.
- Цветовая подсветка: зелёный — хватает, красный — не хватает, жёлтый — излишек, серый — не подключено.
- На каждой связи — поток и **сколько нужно конвейеров** (тип ленты выбирается для связи отдельно).
- Скорости в минуту или в секунду — переключается одной кнопкой.

### Фабрики
- Любую часть схемы можно **сгруппировать в фабрику** — связи через границу сами превращаются во входы и выходы.
- Фабрики вкладываются друг в друга без ограничений; вход двойным кликом, навигация «хлебными крошками».
- Порядок входов и выходов на блоке фабрики меняется стрелками ▲▼ — внутри ничего не сдвигается.
- **Излишки — на выходы**: всё, что производится внутри сверх нужного, автоматически появляется на выходах фабрики.
- Излишки видны на выходе фабрики даже из глубоко вложенных блоков.

### Расчёт
- Режимы блоков: **Авто** (число машин подстраивается под потребность) и **Фикс.** (задаёте сами: числом машин или нужной скоростью продукта).
- Выбор машины для каждого блока, бонусы скорости и продуктивности (модули/маяки).
- **Исследование «Продуктивность добычи»** учитывается автоматически.
- **Топливо** для печей, бойлеров и твердотопливных буров — отдельный вход блока.
- Грубая оценка числа манипуляторов на машину.

### Электроэнергия
- Каждый рецепт показывает своё потребление.
- Блок **«Электростанция»**: внутри собираются паровые двигатели, турбины, бойлеры, солнечные панели, насосы — с подводом воды, топлива и пара.
- Станция питает свою фабрику и вложенные в неё; недостающее берётся у станций внешней фабрики. Видна загрузка каждой станции и дефицит.

### Разделители
- **Разделитель** — сводит и разводит поток одного предмета; на входящей связи видно общее число лент.
- **Приоритетный делитель** — сначала заполняет выход №1, потом №2 и т.д.; выход для излишка; приоритеты меняются стрелками без перекладки связей.

### Беспроводные связи

- **Беспроводной выход** и **беспроводной вход** с номером канала: предмет передаётся без провода между блоками с одинаковым каналом внутри одной фабрики.
- Несколько выходов на канале складываются, несколько входов делят поток по потребности.
- Снаружи фабрики к каналу не подключиться — схемы остаются чистыми, без длинных и закольцованных связей.

### Оформление схем
- **Якоря на связях**: колёсико мыши на связи добавляет точку, её можно тянуть; якоря прилипают, чтобы линия становилась прямой.
- Два вида связей: кривые или прямые (горизонтально, потом вертикально).
- Подписи связей можно двигать — свободно или вдоль связи.
- Цвет каждой связи задаётся отдельно.
- Блоки и порты выравниваются по сетке, поэтому связи между соседними блоками получаются ровными.

### Удобство
- Окно на весь экран: проекты, холст, свойства выбранного блока, итоги фабрики.
- Несколько проектов в одном сохранении.
- Пауза игры кнопкой и **авто-пауза** при открытии окна.
- Пока окно открыто, клавиши не двигают персонажа.
- Настройки по умолчанию: лента, манипулятор, топливо, машины для каждой категории рецептов.

---

## Как пользоваться

1. **Открыть модельер:** кнопка в левом верхнем углу, кнопка на панели быстрого доступа или **Ctrl+Shift+F**.
2. **Добавить блок:** в левой панели выберите рецепт, ресурс для добычи, вход или выход. Блок появится в центре холста.
3. **Соединить блоки:** кликните по порту (кружок на краю блока), затем по порту другого блока. Если кликнуть по порту, а потом по пустому месту, откроется список подходящих рецептов — выбранный блок подключится сам.
4. **Задать цель:** выделите блок «Выход» и укажите нужную скорость — все блоки в режиме «Авто» пересчитаются под неё.
5. **Настроить блок:** клик по блоку — справа откроются его свойства: машина, режим, количество, бонусы, топливо.
6. **Сгруппировать в фабрику:** выделите блоки (Shift+клик) и нажмите «В фабрику». Двойной клик — войти внутрь.
7. **Посмотреть итоги:** в левой панели — входы и выходы фабрики, неподключённые ингредиенты, излишки, число машин, электроэнергия.

### Управление
| Действие | Как |
|---|---|
| Двигать блок | тянуть мышью (выделенные блоки двигаются вместе) |
| Сдвинуть холст | тянуть пустое место или стрелки на клавиатуре |
| Масштаб | колесо мыши |
| Выделить несколько | Shift+клик |
| Перенести выделенное | Ctrl+клик по пустому месту или стрелки |
| Меню блока | ПКМ по блоку |
| Удалить связь | ПКМ по связи |
| Добавить якорь | колёсико мыши на связи |
| Удалить | Delete |
| Войти в фабрику | двойной клик |

> Если клики по холсту попадают мимо (бывает при нестандартном масштабе интерфейса), нажмите **«Калибровка»** в верхней панели и кликните по двум крестикам.

---

## Требования и ограничения
- Factorio **2.1**, базовая игра.
- **Space Age** не тестировался: новые рецепты и машины появятся, но качество, встроенная продуктивность машин, исследования продуктивности рецептов, ленты со стопками и механики планет не учитываются.
- Не поддерживаются ядерные реакторы и тепловые цепочки.
- Манипуляторы считаются приблизительно и в энергопотребление не входят.
- Интерфейс на русском и английском.

---
---

# Factory Modeller (English)

**A visual production planner right inside Factorio — for those who love Satisfactory Modeler.**

No tables: a graph on a canvas instead — recipe blocks, links between them, factories inside factories. The interface follows Satisfactory Modeler: you build the layout with the mouse, and the mod calculates flows, machine counts, belts, fuel and electricity.

> Not affiliated with the authors of Satisfactory Modeler — an independent take on the same idea for Factorio.

## Features
- **Graph canvas:** recipe, mining, input and output blocks; drag, zoom, pan; link ports; click a port and then empty space to get a list of matching recipes, auto-connected.
- **Live colours:** green = enough, red = short, yellow = surplus, grey = not connected.
- **Belts on every link** — how many belts the flow needs, belt type per link. Rates per minute or per second.
- **Factories:** group any part of the graph into a factory — crossing links become its inputs and outputs. Unlimited nesting, double-click to enter, reorder ports with ▲▼ arrows.
- **Surplus to outputs:** every surplus inside a factory automatically becomes one of its outputs, even from deeply nested blocks.
- **Auto / Fixed** blocks, machine choice, speed and productivity bonuses, **mining productivity research** applied automatically, **fuel** for burner machines, rough inserter estimate.
- **Electricity:** each recipe shows its draw; a **Power plant** block holds steam engines, turbines, boilers, solar panels and pumps. Plants feed their own factory and nested ones; the rest comes from the outer factory. Load and deficit are shown.
- **Wireless links:** wireless outputs and inputs with the same channel number inside one factory are connected without a link — no long or looping wires. Not reachable from outside the factory.
- **Splitter** and **priority splitter** (outputs filled in priority order, overflow output, reorder priorities without relinking).
- **Pretty layouts:** anchors on links (middle mouse button) that snap to straight lines, curved or straight-line links, movable link labels, link colours, grid snapping.
- **Comfort:** full-screen window, several projects per save, pause button and auto-pause, game controls blocked while the window is open, defaults for belts, inserters, fuel and machines.

## How to use
1. Open with the top-left button, the shortcut bar or **Ctrl+Shift+F**.
2. Add blocks from the left panel (recipe, mining, input, output).
3. Link ports: click a port, then another port. Click a port and then empty space to pick a matching recipe.
4. Set a target on an **Output** block — all **Auto** blocks follow.
5. Click a block to edit it on the right: machine, mode, count, bonuses, fuel.
6. Select blocks (Shift+click) and press **Group into factory**; double-click to enter.
7. The left panel shows the factory summary: inputs, outputs, missing ingredients, surplus, machines, electricity.

**Controls:** drag blocks / empty space, wheel to zoom, Shift+click to multi-select, right-click for block menu or to delete a link, middle mouse on a link to add an anchor, Delete to remove. If clicks miss on the canvas, use **Calibrate** in the top bar.

## Requirements and limitations
- Factorio **2.1**, base game.
- **Space Age** is untested: new recipes and machines show up, but quality, built-in machine productivity, recipe productivity research, stacked belts and planet mechanics are not taken into account.
- No nuclear reactors / heat pipes yet. Inserters are estimated and not included in power use.
- Russian and English UI.
