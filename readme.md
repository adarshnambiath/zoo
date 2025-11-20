# Zoo Management Database — README

This document contains a markdown-ready explanation for your project (tables, triggers, procedures, functions, GUI mapping) and a careful cross-check against your ER diagram. Use this directly in your README or report.

---

## 1. Table-by-table explanation (concise)

> **Goal:** present each table, meaning, important columns, and cardinality with neighbours.

### `species` (PK: `s_id`)

Stores species-level metadata: scientific/common names, conservation status, size.
**Relationships:**

* `animal.species_id` → `species.s_id` (Many animals → One species)
* `eats.species_id` → `species.s_id` (Optional link: species-level food preferences)

**Cardinality:** 1 `species` : N `animal`.

---

### `animal` (PK: `a_id`)

Represents individual animals (name, birth_date, gender, arrival_date).
**Relationships:**

* `animal.species_id` → `species.s_id` (M:1)
* `medrec.a_id` → `animal.a_id` (1 animal : N medrec)
* `animal_enclosure.a_id` → `animal.a_id` (N occupancy records per animal over time)
* `feed_log.a_id` → `animal.a_id` (N feed entries)
* `eats.a_id` → `animal.a_id` (optional animal-level preferences)

**Cardinality:** `species` 1 → N `animal`; `animal` 1 → N `medrec`.

---

### `medrec` (PK: `mr_id`)

Medical records per animal with `last_checked`, `next_check` and notes.
**Relationships:** `medrec.a_id` → `animal.a_id` (N records per animal)

**Business rule:** `next_check` auto-set by triggers if NULL (last_checked + 30 days).

---

### `food` (PK: `f_id`)

Food inventory: name, type, `quantity`, `unit`, `price_per_unit`.
**Relationships:**

* `eats.f_id` → `food.f_id`
* `feed_log.f_id` → `food.f_id`

**Cardinality:** `food` 1 → N `feed_log`, `food` 1 → N `eats`.

---

### `eats` (PK: `eats_id`)

Associative table representing which `food` is appropriate for a given `animal` OR `species`.
**Columns:** `a_id` (nullable), `species_id` (nullable), `f_id` (FK), `preference`.

**Design notes / cardinality:**

* This models a many-to-many relationship between (animal or species) and food.
* **Constraint recommended:** enforce that **exactly one** of `(a_id, species_id)` is non-null; otherwise rows ambiguous.

  * Implementable with a `CHECK` in MySQL 8+: `CHECK ((a_id IS NULL) XOR (species_id IS NULL))`.

---

### `enclosure` (PK: `e_id`)

Physical enclosure meta (name, location, capacity).
**Relationships:**

* `animal_enclosure.e_id` → `enclosure.e_id` (N occupancy records)
* `event.e_id` → `enclosure.e_id` (optional: events hosted in an enclosure)
* `employee_enclosure.e_id` → `enclosure.e_id`

**Cardinality:** `enclosure` 1 → N `animal_enclosure`, 1 → N `event`.

---

### `animal_enclosure` (PK: `ae_id`)

Records assignment history of animals to enclosures with time windows (`assigned_from`, `assigned_to`).
**Relationships:** FK to `animal` and `enclosure`.

**Business rule:** application enforces only one "current" assignment (where `assigned_to IS NULL`) per animal. Consider DB-side enforcement: unique partial index or trigger to prevent more than one current row per `a_id`.

---

### `employee` (PK: `emp_id`)

Employee directory.
**Relationships:** `employee_enclosure`, `feed_log.fed_by`.

---

### `employee_enclosure` (PK: `ee_id`)

Assigns employees to enclosures (role, dates). Unique key on (`emp_id`, `e_id`).
**Cardinality:** `employee` N ↔ N `enclosure`.

---

### `infra` (PK: `i_id`)

Infrastructure/equipment items. Linked to `event_infra`.

---

### `event` (PK: `ev_id`)

Events table with date, optional enclosure, capacity.
**Relationships:** `event_infra.ev_id` and optional FK `e_id` → `enclosure.e_id`.

**Business rule:** `schedule_event` stored procedure validates event capacity vs enclosure capacity (when enclosure provided).

---

### `event_infra` (PK: `ei_id`)

Associative table: `event` ↔ `infra` (many-to-many) with `quantity`.

---

### `visitor` (PK: `v_id`) & `ticket` (PK: `t_id`)

Visitor master; ticket links visitor to purchases/registrations. `ticket.visitor_id` may be NULL for walk-ins.

---

### `feed_log` (PK: `fl_id`)

Log of actual feed instances. On `INSERT`, trigger reduces `food.quantity` and inserts `notifications` if low.

---

### `notifications` (PK: `n_id`)

Audit/alert messages (low stock, seed message, etc.). Populated by triggers.

---

### `vw_enclosure_status` (VIEW)

Summarizes enclosure occupancy and remaining capacity (derived from `animal_enclosure`).

---

## 2. Triggers, Functions, Stored Procedures — Expanded

(See full descriptions in the main README; below is a compact repeat so your README table is self-contained.)

### Triggers

* **`trg_medrec_nextcheck_before_insert` / `_before_update`**

  * *When:* BEFORE INSERT/UPDATE on `medrec`.
  * *Action:* If `NEW.next_check IS NULL` then `SET NEW.next_check = DATE_ADD(NEW.last_checked, INTERVAL 30 DAY)`.
  * *Implication:* Ensures next check is scheduled automatically.

* **`trg_feedlog_after_insert`**

  * *When:* AFTER INSERT on `feed_log`.
  * *Action:* `UPDATE food SET quantity = GREATEST(quantity - NEW.amount, 0) WHERE f_id = NEW.f_id;` then if quantity < 10, insert a `notifications` warning.
  * *Implication:* Keeps inventory in sync with feed actions and raises low-stock alerts.

### Functions

* **`animal_age(p_aid INT)`** — returns int years; uses `TIMESTAMPDIFF(YEAR, birth_date, CURDATE())`.
* **`enclosure_remaining_capacity(p_eid INT)`** — returns remaining slots (capacity - occupied), counts rows in `animal_enclosure` where `assigned_to IS NULL OR assigned_to > CURDATE()`.

### Stored Procedures

* **`schedule_event(p_title, p_date, p_enclosure, p_capacity, OUT p_ev_id)`**

  * Validates event capacity vs enclosure capacity (if enclosure provided). If invalid, returns `p_ev_id = 0`.
  * Else inserts into `event` and returns inserted id.

* **`assign_employee(p_emp_id, p_e_id, p_role, OUT p_success)`**

  * Checks for existing `(emp_id, e_id)` assignment; inserts if not present returning `1`, else `0`.

## 3. GUI Feature Map (what each control does & what SQL it calls)

* **Predefined lists** — `/api/query?v=<name>` → runs `SELECT` on the requested view/table (e.g., `species`, `food`, `vw_enclosure_status`). Renders as table.

* **Animal Age** — `/api/animal_age/:id` → runs `SELECT animal_age(?)`; shows `{ age }` object.

* **Enclosure Remaining** — `/api/enclosure_remaining/:id` → `SELECT enclosure_remaining_capacity(?)`.

* **Schedule Event** — POST `/api/schedule_event` → calls `CALL schedule_event(...)` procedure and returns `ev_id`.

* **Assign Employee** — POST `/api/assign_employee` → `CALL assign_employee(...)`

* **Insert Animal** — POST `/api/animal` → `INSERT INTO animal (...)`.

* **Feed Log** — POST `/api/feed_log` → `INSERT INTO feed_log (...)` which triggers `trg_feedlog_after_insert` to update `food.quantity` and possibly insert a notification.

* **Notifications** — GET `/api/notifications` → `SELECT * FROM notifications ORDER BY created_at DESC LIMIT 50`.