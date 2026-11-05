# REPLICA RECON: FatSecret (iOS) → FORM Deep Architectural Steal
**Target:** FatSecret Calorie Counter (iOS) vs FORM // ATELIER  
**Objective:** Reverse-engineer the core mechanics, data models, and premium features of FatSecret to upgrade FORM into an uncompromising, autonomous tracker.

---

## 1. Screen Inventory & Component Matrix

| ID | Screen | Route / Trigger | Key Mechanics & Components | States |
|---|---|---|---|---|
| **S01** | **Дневник питания (Daily Food Log)** | Главный таб «Рацион» | 4 приёма пищи (Завтрак, Обед, Ужин, Перекус/Снеки), суммарные калории и макросы по каждому приёму, прогресс-бары дефицита/профицита. | Empty, Partial, Complete, Exceeded |
| **S02** | **Поиск продуктов (Food Search & Recents)** | Тап на строку ввода / «+» | Список недавних продуктов (Recents), часто употребляемые (Favorites), поиск по локальной базе + OpenFoodFacts, сканер штрихкодов. | Idle, Suggestions, Zero-Result |
| **S03** | **Карточка выбора порции (Serving Multiplier)** | Тап на продукт из поиска | Селектор единиц: граммы (г), порция (250г), 1 шт (яйцо/банан), 1 упаковка/пачка, столовая ложка (15г). Пересчёт КБЖУ в реальном времени. | Default, Custom Weight |
| **S04** | **Быстрые калории (Quick Calorie Add)** | Кнопка «+ Калории без продукта» | Ручной ввод калорий и БЖУ (для обедов в ресторане, кафе, походов в гости) без дробления на ингредиенты. | Modal |
| **S05** | **Макро-баланс дня (% Ratio Bar)** | Блок под круговым счетчиком | Процентное соотношение калорий от макросов: `% Калорий от Белка`, `% от Жиров`, `% от Углеводов` (4 ккал/г для Б и У, 9 ккал/г для Ж). | Dynamic |
| **S06** | **Копирование дня / приёма пищи (Smart Copy)** | Кнопка в меню приёма пищи | «Повторить вчерашний завтрак» в 1 тап, «Копировать вчерашний рацион». | Action Sheet |
| **S07** | **Водный трекер (Water Balance)** | Виджет на главном экране | Тап по стакану (+250 мл) или бутылке (+500 мл), цель 2–3 л/день. | Counter |
| **S08** | **Трендовый вес и метаболизм** | Таб «Вес» | Скользящее среднее (7-day exponential moving average), реальный темп сброса/набора, коррекция калоража. | Chart |

---

## 2. Inferred Data Model

```typescript
// 1. Прием пищи (Meal Bucket)
type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack';

// 2. Запись продукта в рационе
interface FoodEntry {
  id: string;
  name: string;
  weight: number;            // вес в граммах
  cal: number;               // суммарные ккал
  p: number;                 // белки (г)
  f: number;                 // жиры (г)
  c: number;                 // углеводы (г)
  cal100: number;            // на 100г
  p100: number;
  f100: number;
  c100: number;
  meal: MealType;            // привязка к приёму пищи
  timestamp: number;
  source: 'База' | 'Этикетка' | 'Штрихкод' | 'Ручной' | 'OpenFoodFacts';
  standardUnitWeight?: number; // вес 1 шт / упаковки
}

// 3. Дневная сводка приемов пищи
interface DailyMealsSummary {
  breakfast: { cal: number; p: number; f: number; c: number; items: FoodEntry[] };
  lunch:     { cal: number; p: number; f: number; c: number; items: FoodEntry[] };
  dinner:    { cal: number; p: number; f: number; c: number; items: FoodEntry[] };
  snack:     { cal: number; p: number; f: number; c: number; items: FoodEntry[] };
  macroRatio: { pPct: number; fPct: number; cPct: number }; // % калорий
}
```

---

## 3. Топ Premium-фич FatSecret, которые мы забираем в FORM

1. **Группировка по 4 приёмам пищи (Завтрак / Обед / Ужин / Перекус)**:
   - Автоматическое определение приёма пищи по системному времени часов на iPhone:
     - `04:00 – 11:30` → 🌅 Завтрак
     - `11:30 – 16:30` → ☀️ Обед
     - `16:30 – 21:30` → 🌙 Ужин
     - `21:30 – 04:00` → 🍏 Перекус / Стек
   - Возможность ручного переключения в 1 тап и фильтрации списка «Сегодня».
2. **Процентный макро-баланс (% Macro Ratio)**:
   - Формула:
     $$E_{protein} = P \times 4, \quad E_{fat} = F \times 9, \quad E_{carb} = C \times 4$$
     $$\%P = \frac{E_{protein}}{E_{total}} \times 100\%, \quad \%F = \frac{E_{fat}}{E_{total}} \times 100\%, \quad \%C = \frac{E_{carb}}{E_{total}} \times 100\%$$
   - Выводится компактной эстетичной плашкой под суточными калориями.
3. **Быстрые калории (Quick Add Calorie Override)**:
   - Ввод калорий напрямую без поиска ингредиентов.
4. **Быстрый селектор порций (FatSecret Serving Multiplier)**:
   - Пресеты: `100г`, `Порция (250г)`, `1 штука / банка`, `Тарелка`.
