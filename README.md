<h1 align="center">FORM // SYSTEM</h1>

<p align="center">
  <strong>Brutalist Macro, Hypertrophy & Adaptive Metabolism Engine</strong><br>
  iOS 26 Liquid Glass · Local-First (Zero Telemetry) · Atelier 85/10/5 Design System · Gemini 3 Flash Multimodal AI · Dynamic Island & WidgetKit
</p>

<p align="center">
  <a href="https://paradoxiicalie.github.io/form/">
    <img src="https://img.shields.io/badge/ЗАПУСК_PWA-ОНЛАЙН_ВЕРСИЯ-E6DFD3?style=for-the-badge&labelColor=18181B&logo=googlechrome&logoColor=E6DFD3" alt="Открыть PWA" />
  </a>
  <a href="#метод-a-сборка-из-исходников-в-xcode-эталонный-способ-для-ios">
    <img src="https://img.shields.io/badge/СБОРКА_В_XCODE-ЭТАЛОННЫЙ_СПОСОБ-E6DFD3?style=for-the-badge&labelColor=18181B&logo=xcode&logoColor=E6DFD3" alt="Сборка Xcode" />
  </a>
  <a href="#03--развёртывание-и-установка">
    <img src="https://img.shields.io/badge/ИНСТРУКЦИЯ-УСТАНОВКА-E6DFD3?style=for-the-badge&labelColor=18181B&logo=readme&logoColor=E6DFD3" alt="Инструкция" />
  </a>
  <a href="https://github.com/paradoxiicalie/form/releases/tag/v2.0.0">
    <img src="https://img.shields.io/badge/РЕЛИЗ-v2.0.0%20(iOS%2026)-73EC8B?style=for-the-badge&labelColor=18181B&logoColor=73EC8B" alt="Релиз v2.0.0" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/АРХИТЕКТУРА-LOCAL--FIRST%20(ZERO%20TELEMETRY)-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Архитектура" />
  <img src="https://img.shields.io/badge/ДИЗАЙН-ATELIER%2085%2F10%2F5%20(7%20THEMES)-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Дизайн" />
  <img src="https://img.shields.io/badge/НАВИГАЦИЯ-iOS%2026%20LIQUID%20GLASS-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Навигация" />
  <img src="https://img.shields.io/badge/AI_CORE-GEMINI%203%20FLASH%20(VISION%20%26%20NLP)-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="AI Core" />
  <img src="https://img.shields.io/badge/ПЛАТФОРМЫ-iOS%20(WIDGET%20%2B%20DYNAMIC%20ISLAND)%20%7C%20ANDROID%20%7C%20PWA-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Платформы" />
  <img src="https://img.shields.io/badge/ЛИЦЕНЗИЯ-MIT-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Лицензия" />
</p>

---

### 01 // КОНЦЕПЦИЯ И ДИЗАЙН-СИСТЕМА ATELIER

**FORM // SYSTEM** спроектирован как бескомпромиссная инженерная альтернатива перегруженным коммерческим фитнес-трекерам.

* **Local-First архитектура (0 собственных серверов и телеметрии):** Вся база данных рациона, тренировочный дневник, история веса и настройки хранятся исключительно на физическом устройстве пользователя. Приложение не требует регистрации, не использует внешние бэкенды и не собирает пользовательские данные.
* **Цветовая архитектура Atelier 85/10/5:**
  - **85% (Доминантный фон):** Глубочайшие обсидиановые и ониксовые плоскости (`#070708`, `#0A0A0C`), убирающие визуальную усталость при слабом освещении и гарантирующие экономию заряда на OLED-экранах.
  - **10% (Структура и карточки):** Нейтральные темно-серые и графитовые поверхности (`#111114`, `#16161A`, `border-white/10`), организующие контент без перегруженности.
  - **5% (Акцентные фокусы):** Высококонтрастные функциональные токены КБЖУ и статуса (`--accent-cal`, `--accent-p`, `--accent-f`, `--accent-c`), привлекающие взгляд строго к ключевым цифрам.
* **7 авторских цветовых тем:**
  1. `Obsidian Noir` — шелковистый песочный акцент (`#E6DFD3`), чистый швейцарский брутализм.
  2. `Cyber Lime` — неоновый лайм (`#73EC8B`), спортивная эстетика визора.
  3. `Neon Rust` — насыщенный теплый янтарь (`#FF8E53`), винтажное студийное свечение.
  4. `Velvet Berry` — глубокая шелковая слива (`#E879F9`), сдержанный ночной контраст.
  5. `Verdant Moss` — благородный изумрудный (`#4EBA6F`), природный баланс.
  6. `Azure Cobalt` — глубокий ультрамарин (`#3B82F6`), строгая цифровая точность.
  7. `Deep Teal` — бирюзово-циановый неоновый спектр (`#14B8A6`).
* **Типографика и стандарты WCAG:** Высококонтрастные моноширинные числовые шкалы с поддержкой нативных шрифтов (`ui-monospace`, `SF Mono`) и директивой `font-variant-numeric: tabular-nums` (исключает сдвиги верстки при динамическом изменении калорий и весов).

---

### 02 // АРХИТЕКТУРА И МОДУЛИ

```
┌────────────────────────────────────────────────────────────────────────┐
│                   FORM // SYSTEM ARCHITECTURE                          │
├────────────────────────────────────────────────────────────────────────┤
│  SWIFTUI NATIVE SHELL (iOS 26 Liquid Glass Navigation + Gestures)       │
│  ├── ContentView.swift: GlassEffectContainer & .glassEffect            │
│  ├── Floating Bar: [ Рацион (fork.knife) | Трени (dumbbell.fill) ]      │
│  └── Action Button: Circular 54pt (viewfinder / plus)                  │
├────────────────────────────────────────────────────────────────────────┤
│  SINGLE-PAGE APPLICATION WEB CORE (WebKit WKWebView Bridge)            │
│  ├── Track Navigation: 60fps gesture swipes with curve synchronization │
│  ├── Camera Segmented Controls: [ РАЦИОН // ДНЕВНИК // ПЛАН ]          │
│  ├── Broken Neon Totem: 4-tier voltage flicker tied to daily progress  │
│  ├── Multimodal Scanner: Realtime Quagga2 EAN-13 + Gemini 3 Flash AI   │
│  ├── Nutrition Engine: Rolling 14-day TDEE + Mifflin-St Jeor BMR       │
│  ├── Workout Engine: 4-day split, volume tracking & rest timer         │
│  └── Toast Notification System: 3-tier collision layout & touch guard  │
├────────────────────────────────────────────────────────────────────────┤
│  NATIVE SYSTEM EXTENSIONS                                              │
│  ├── ActivityKit: Dynamic Island & Lock Screen Live Activity           │
│  ├── WidgetKit: Dashboard Medium-Widget (form:// deep links)           │
│  ├── App Groups: Isolated UserDefaults replication                     │
│  └── UserNotifications: 14-day scheduled local motivational alerts      │
└────────────────────────────────────────────────────────────────────────┘
```

#### [ НАВИГАЦИЯ APPLE LIQUID GLASS (iOS 26) ]
* **Нативный Liquid Glass бар:** Реализован на SwiftUI с использованием системных контейнеров iOS 26 `GlassEffectContainer` и модификатора `.glassEffect(...)`. Капсула навигации и отдельная круглая кнопка действия (`54 pt`) расположены в одной горизонтальной линии по референсу системных приложений iOS.
* **Двусторонний мост синхронизации:** Изменение экранов в веб-слое мгновенно обновляет нативный Liquid Glass бар через `window.webkit.messageHandlers`, а нажатия на нативные кнопки гладко сдвигают веб-трек.
* **60fps жестовые свайпы:** Горизонтальное переключение между разделами «Рацион» и «Трени» с физикой TikTok/Instagram, защитой от рывков высоты (`prepareTracksForSwipe` / `lockInactiveTrackHeights`) и нулевым пустым скроллом.
* **Сегментные контролы в стиле Камеры iOS:** Минималистичные плавающие переключатели подвкладок (`segmented-slider-container`) на чистом графитовом фоне с плавной скользящей плашкой.

#### [ ТОТЕМ ДНЯ С ЭФФЕКТОМ «СЛОМАННОГО НЕОНА» ]
* **Симметричный статус-тотем (`#iosDailyTotemBtn`):** Расположен в шапке приложения напротив кнопки меню, оснащен внешним SVG-кольцом прогресса (`#iosDailyTotemProgressCircle`), плавно заполняющимся по мере выполнения суточных целей.
* **4-уровневый алгоритм электрических сбоев (`data-neon-tier="0..3"`):**
  - **Tier 0 (< 25% прогресса):** Тусклая лампа (`opacity: 0.52`), внезапные резкие провалы напряжения и короткие искры в цикле 4.8с.
  - **Tier 1 (25–60%):** Прогрев нити накала (`opacity: 0.78`), редкие микросбои в цикле 6.8с.
  - **Tier 2 (60–90%):** Почти стабильное горение (`opacity: 0.92`), единичные едва заметные колебания в цикле 9.6с.
  - **Tier 3 (≥ 90%):** Безупречное ровное неоновое свечение с двойным ореолом без мерцания.
* **Коллекция из 8 кибер-глифов:** Алмаз, Призма, Пульс, Щит, Песочные часы, Атом, Сверхновая, Кибер-руна. При нажатии значок циклически переключается с тактильной отдачей Taptic Engine и 3D-анимацией переворота монеты на `transform` (без конфликта со свойствами мерцания).

#### [ ОПТИЧЕСКИЙ МОДУЛЬ И AI-ЗРЕНИЕ (GEMINI 3 FLASH + QUAGGA2) ]
* **Двухконтурный сканер штрихкодов:** Аппаратное распознавание EAN-13 через камеру в реальном времени с мгновенным обращением к базе OpenFoodFacts. При отсутствии данных или нулевом КБЖУ автоматически подключается Gemini 3 Flash для обогащения макронутриентов.
* **Распознавание граммовок и массы нетто:** Автоматическое извлечение веса упаковки из штрихкода или этикетки с мгновенными чипами переключения «100 г» vs «Вся пачка».
* **Центрированный Dark-Glass лоадер:** Информативное окно ожидания (`#scannerLoading`, `z-40`) со спиннером в цвет темы, бейджем распознанного штрихкода в `.mono` и живым статусом («Ищем штрихкод в базе...», «Уточняем КБЖУ через ИИ...»).
* **Защищенная кнопка ручного ввода:** Фиксированная геометрия `min-w-[68px]` исключает сдвиги соседних элементов при смене текста «Найти» на вращающийся спиннер.
* **AI-анализ блюд на тарелке:** Визуальная оценка объема порции, детекция координат (`object_box`), определение веса и автоматическая раскладка по КБЖУ.

#### [ УМНАЯ СИСТЕМА УВЕДОМЛЕНИЙ (ТОСТЫ) ]
* **3-уровневый алгоритм позиционирования:**
  1. *При открытой модалке (`.sheet-backdrop.open`):* всегда внизу открытого листа (`+18px`), не перекрывая элементы управления.
  2. *При активном таймере отдыха:* строго над плавающим баром таймера (`window.innerHeight - rect.top + 12px` или `+226px`), не закрывая кнопки времени.
  3. *В стандартном режиме экрана:* зазор `12px` над нативным Liquid Glass баром (`+76px`).
* **100% защита от ghost-кликов:** В обычном состоянии блок тоста прозрачен для касаний (`pointer-events: none`). При появлении класс `.toast-visible` делает его интерактивным, а обработчик `touchend` с `e.preventDefault()` и `e.stopPropagation()` мгновенно закрывает уведомление и гарантирует, что тап не «прострелит» в нижележащие кнопки логгера подходов.

#### [ МАКРОНУТРИЕНТЫ И АДАПТИВНЫЙ МЕТАБОЛИЗМ ]
* **Адаптивный TDEE Engine:** Алгоритмический учет 14-дневного взвешивания и сопоставление с фактическим калоражем потребления для расчета индивидуального расхода энергии и защиты от метаболической адаптации.
* **Калькулятор целевого баланса:** Динамический расчет BMR / TDEE по формуле Миффлина-Сан Жеора с фиксацией целей или ручным управлением.
* **Тренер рациона и план питания:** Индивидуальные приемы пищи, чипы модификаторов блюд («Без жира», «Масло +5г», «Чистый белок»), трекер ежедневных полезных привычек и быстрый учет добавок в один тап.

#### [ ТРЕНИРОВОЧНЫЙ ДВИЖОК И ГИПЕРТРОФИЯ ]
* **Сплит-архитектура (Д1–Д4 + A/B/C варианты):** Гибкая привязка тренировок к дням недели с сохранением шаблонов и вариаций упражнений.
* **Учет рабочих подходов:** Фиксация весов и повторений с автоматическим выделением **лучшего рабочего подхода дня**.
* **Недельный мышечный объем:** Раздельный учет объема по **5 группам мышц** (Грудь, Спина, Ноги, Руки, Плечи) с визуальными шкалами недельного лимита.
* **Умный таймер отдыха:** Автоматический старт обратного отсчета между подходами с калибровкой времени, кнопками `+30с / -30с`, звуковым сигналом и интеграцией в Dynamic Island.

#### [ СИСТЕМНАЯ ИНТЕГРАЦИЯ С iOS ]
* **ActivityKit & Dynamic Island:** Живой таймер отдыха прямо в «динамическом острове» и на Always-On Display. Поддерживает компактные и расширенные режимы без расхода аккумулятора через нативный `Text(style: .timer)`.
* **WidgetKit Engine:** Нативный Medium-виджет в стиле приборной панели с глубокими ссылками (`form://diet` для питания и `form://split` для тренировок).
* **App Groups Sync:** Мгновенный обмен данными между веб-движком и нативными расширениями через `UserDefaults(suiteName: "group.com.macro.shared")`.
* **UserNotifications:** Локальные системные уведомления на 14 дней с генератором мотивационных фраз через Gemini.

---

### 03 // РАЗВЁРТЫВАНИЕ И УСТАНОВКА

#### [ СРАВНИТЕЛЬНАЯ ТАБЛИЦА МЕТОДОВ ]

| Метод | Требования | Срок действия | Liquid Glass (iOS 26) | Виджет iOS | Dynamic Island | Локальные пуши |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: |
| **A. Сборка в Xcode + Auto-Resign** | Mac + Xcode + Apple ID | **Бессрочно (Auto-Resign)** | **Да (100%)** | **Да (100%)** | **Да (Live Activity)** | **Да** |
| **B. Progressive Web App (PWA)** | Safari / Chrome (без ПК) | **Бессрочно** | Веб-фоллбэк | — | — | — |
| **C. Sideloadly / AltServer** | Mac / ПК + USB-кабель | 7 дней (авторефреш) | **Да** | Частично* | Частично* | **Да** |
| **D. SideStore / AltStore** | WireGuard VPN на устройстве | Бессрочно (рефреш по Wi-Fi) | **Да** | Частично* | Частично* | **Да** |

*\*Примечание: Для гарантированной работы системных расширений WidgetKit / ActivityKit и App Groups на бесплатных Apple ID рекомендуется Метод A (Xcode).*

---

#### Метод A: Сборка из исходников в Xcode (Рекомендуется для iOS)

1. Клонируйте репозиторий:
   ```bash
   git clone https://github.com/paradoxiicalie/form.git
   cd form
   open form.xcodeproj
   ```
2. В Xcode выберите схему `form`.
3. В настройках целей `form` и `FormWidgetExtension` перейдите во вкладку **Signing & Capabilities** и укажите свою команду разработчика (*Team*).
4. Подключите iPhone кабелем или по Wi-Fi (*Window → Devices and Simulators → Connect via network*).
5. Нажмите **Run** (`Cmd + R`) для компиляции и установки на устройство.

##### [ АВТОМАТИЧЕСКОЕ БЕСПРОВОДНОЕ ОБНОВЛЕНИЕ (AUTO-RESIGN DAEMON) ]
В проект встроен автономный фоновый сервис **FORM // KEEP-ALIVE DAEMON**, который раз в 4 дня незаметно переподписывает и обновляет приложение по воздуху через Wi-Fi мост CoreDevice (`xcrun devicectl`).

* **Установка и запуск фонового демона macOS (однократно):**
  ```bash
  ./scripts/install_daemon.sh
  ```
* **Проверка статуса сертификата и подключения устройства:**
  ```bash
  ./scripts/autoresign.sh --status
  ```
* **Принудительная сборка и деплой прямо сейчас:**
  ```bash
  ./scripts/autoresign.sh --force
  ```
* **Удаление фонового демона:**
  ```bash
  ./scripts/uninstall_daemon.sh
  ```

---

#### Метод B: Установка как Progressive Web App (PWA)

##### Для iOS (Safari):
1. Откройте в Safari: `https://paradoxiicalie.github.io/form/`
2. Нажмите системную кнопку **«Поделиться»** (квадрат со стрелкой вверх).
3. Выберите **«На экран "Домой"»** → **Добавить**.

##### Для Android (Google Chrome / Samsung Internet):
1. Перейдите по адресу `https://paradoxiicalie.github.io/form/`
2. Откройте меню браузера (**три точки**) → **«Установить приложение»** (или **«Добавить на главный экран»**).

---

#### Метод C: Установка готового IPA через Sideloadly
1. Подключите iPhone к компьютеру и запустите **Sideloadly**.
2. Перетащите файл `form.ipa`, введите Apple ID и нажмите **Start**.
3. На iPhone: *Настройки → Основные → VPN и управление устройством* → подтвердите доверие профилю.

---

### 04 // ТЕХНИЧЕСКИЙ СТЕК

```text
[ NATIVE iOS 26 ]      SwiftUI, GlassEffectContainer, .glassEffect, SF Symbols, WebKit WKWebView
[ SYSTEM EXTENSIONS ]  ActivityKit (Dynamic Island Live Activities), WidgetKit, App Groups
[ AI & MULTIMODAL ]    Google Gemini 3 Flash (gemini-3-flash-preview) Vision API & NLP Entity Parsing
[ COMPUTER VISION ]    Quagga2 Realtime Barcode Engine + OpenFoodFacts REST API
[ FRONTEND CORE ]      Vanilla JavaScript (ES6+), HTML5, Tailwind CSS, SVG Canvas
[ HARDWARE HAPTICS ]   Taptic Engine AudioContext + UIImpactFeedbackGenerator Bridge
[ AUTOMATION ]         CoreDevice Tunnel (xcrun devicectl), launchd Keep-Alive Daemon, Auto-Resign
[ METABOLIC ENGINE ]   Adaptive 14-day Rolling TDEE, Dynamic BMR (Mifflin-St Jeor), 1RM Formula
[ PERSISTENCE ]        W3C LocalStorage + Native UserDefaults Replication + JSON Snapshots
```

---

### 05 // ИСТОРИЯ РЕЛИЗОВ И ТЕГИ

* **[v2.0.0](https://github.com/paradoxiicalie/form/releases/tag/v2.0.0):**
  - Переход на нативный **Apple Liquid Glass (iOS 26)** в нижней навигации (`ContentView.swift`) с круглым Floating Action Button.
  - Полноценная цветовая система **Atelier 85/10/5** (7 авторских обсидиановых тем, строгий WCAG-контраст, табличные моноширинные числа).
  - Сбалансированный **Тотем дня** с 4-уровневым эффектом сломанного неона (`tier 0..3`), кольцом прогресса и 3D-анимацией флипа.
  - Высокоточный **сканер штрихкодов** с центрированным стеклянным лоадером, защитой кнопки от скачков верстки и обогащением КБЖУ через Gemini 3 Flash.
  - 3-уровневая адаптивная система **тостов** с изоляцией жестов и защитой от ghost-кликов на iOS.
* **[v1.0.0](https://github.com/paradoxiicalie/form/releases/tag/v1.0.0):**
  - Базовый стабильный релиз Local-First PWA и нативной оболочки iOS с интеграцией виджетов WidgetKit, Dynamic Island и фоновым демоном Auto-Resign.

---

### 06 // ЛИЦЕНЗИЯ

Проект распространяется под свободной лицензией **MIT**. Подробности приведены в файле [LICENSE](LICENSE).
