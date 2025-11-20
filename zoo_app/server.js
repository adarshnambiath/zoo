// server.js
const express = require("express");
const mysql = require("mysql2/promise");
const path = require("path");
const bodyParser = require("body-parser");
const cors = require("cors");

const app = express();
app.use(cors());
app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, "public")));

//config
const pool = mysql.createPool({
  host: "localhost",
  user: "zoo_user",
  password: "Zoozoo@123",
  database: "zoo_db",
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// selects
const predefinedQueries = {
  animals: "SELECT * FROM animal ORDER BY a_id",
  species: "SELECT * FROM species ORDER BY s_id",
  enclosures: "SELECT * FROM enclosure ORDER BY e_id",
  food: "SELECT * FROM food ORDER BY f_id",
  medrecs: "SELECT * FROM medrec ORDER BY mr_id",
  feed_log: "SELECT * FROM feed_log ORDER BY fl_id DESC",
  eats: "SELECT * FROM eats ORDER BY eats_id",
  employee_enclosure: "SELECT * FROM employee_enclosure ORDER BY ee_id",
  animal_enclosure: "SELECT * FROM animal_enclosure ORDER BY ae_id",
  visitors: "SELECT * FROM visitor ORDER BY v_id",
  tickets: "SELECT * FROM ticket ORDER BY t_id",
  employees: "SELECT * FROM employee ORDER BY emp_id",
  infra: "SELECT * FROM infra ORDER BY i_id",
  events: "SELECT * FROM event ORDER BY ev_id",
  event_infra: "SELECT ei_id, ev_id, i_id FROM event_infra ORDER BY ei_id",
  vw_enclosure_status: "SELECT * FROM vw_enclosure_status",
  notifications: "SELECT * FROM notifications ORDER BY created_at DESC",
  inner_animal_species: `
  SELECT
    a.a_id,
    a.name AS animal_name,
    a.birth_date,
    a.gender,
    s.s_id AS species_id,
    s.common_name AS species_name,
    s.scientific_name,
    s.conservation_status
  FROM animal a
  INNER JOIN species s ON a.species_id = s.s_id
  ORDER BY a.a_id
`,
  inner_event_infra: `
  SELECT
    ev.ev_id,
    ev.title AS event_title,
    ev.e_date,
    ev.location AS event_location,
    ei.ei_id,
    i.i_id AS infra_id,
    i.name AS infra_name,
    ei.quantity
  FROM event ev
  INNER JOIN event_infra ei ON ev.ev_id = ei.ev_id
  INNER JOIN infra i ON ei.i_id = i.i_id
  ORDER BY ev.ev_id, i.i_id
`,
  left_enclosure_animals: `
  SELECT
    enc.e_id,
    enc.name AS enclosure_name,
    enc.capacity,
    ae.ae_id,
    a.a_id AS animal_id,
    a.name AS animal_name,
    ae.assigned_from,
    ae.assigned_to
  FROM enclosure enc
  LEFT JOIN animal_enclosure ae ON enc.e_id = ae.e_id
  LEFT JOIN animal a ON ae.a_id = a.a_id
  ORDER BY enc.e_id, ae.ae_id
`,
  right_animal_medrec: `
  SELECT
    a.a_id,
    a.name AS animal_name,
    mr.mr_id,
    mr.last_checked,
    mr.next_check,
    mr.diseases,
    mr.notes
FROM medrec mr
RIGHT JOIN animal a ON mr.a_id = a.a_id
ORDER BY a.a_id, mr.mr_id;

`,
};

app.get("/api/query", async (req, res) => {
  try {
    const v = req.query.v;
    if (!v || !predefinedQueries[v])
      return res.status(400).json({ error: "Bad query" });
    const [rows] = await pool.query(predefinedQueries[v]);
    res.json(rows);
  } catch (err) {
    console.error("query error", err);
    res.status(500).json({ error: String(err) });
  }
});

// functions
app.get("/api/animal_age/:id", async (req, res) => {
  try {
    const a_id = parseInt(req.params.id, 10);
    const [rows] = await pool.query("SELECT animal_age(?) AS age", [a_id]);
    res.json(rows[0]);
  } catch (err) {
    console.error("animal_age error", err);
    res.status(500).json({ error: String(err) });
  }
});

app.get("/api/enclosure_remaining/:id", async (req, res) => {
  try {
    const e_id = parseInt(req.params.id, 10);
    const [
      rows,
    ] = await pool.query(
      "SELECT enclosure_remaining_capacity(?) AS remaining",
      [e_id]
    );
    res.json(rows[0]);
  } catch (err) {
    console.error("enclosure_remaining error", err);
    res.status(500).json({ error: String(err) });
  }
});

// Stored procedures
app.post("/api/schedule_event", async (req, res) => {
  try {
    const { title, e_date, e_id, capacity, infra_ids } = req.body;
    const conn = await pool.getConnection();
    try {
      await conn.query("CALL schedule_event(?,?,?,?, @out_ev_id)", [
        title,
        e_date,
        e_id,
        capacity,
      ]);
      const [rows] = await conn.query("SELECT @out_ev_id AS ev_id");
      const ev_id = rows[0].ev_id;
      if (infra_ids && Array.isArray(infra_ids) && infra_ids.length > 0) {
        for (const iid of infra_ids) {
          await conn.query(
            `INSERT INTO event_infra (ev_id, i_id, quantity)
   VALUES (?, ?, 1)
   ON DUPLICATE KEY UPDATE quantity = quantity`,
            [ev_id, iid]
          );
        }
        await conn.query(
          'INSERT INTO notifications(level, message) VALUES ("INFO", CONCAT("Infra assigned manually for event ", ?))',
          [ev_id]
        );
      }

      res.json({ ev_id, assigned_infra: infra_ids || [] });
    } finally {
      conn.release();
    }
  } catch (err) {
    console.error("schedule_event error", err);
    res.status(500).json({ error: String(err) });
  }
});

app.post("/api/assign_employee", async (req, res) => {
  try {
    const { emp_id, e_id, role_desc } = req.body;
    const conn = await pool.getConnection();
    try {
      await conn.query("SET @p_success = 0");
      await conn.query("CALL assign_employee(?,?,?, @p_success)", [
        emp_id,
        e_id,
        role_desc,
      ]);
      const [r] = await conn.query("SELECT @p_success AS success");
      res.json(r[0]); // { success: 1 } or { success: 0 }
    } finally {
      conn.release();
    }
  } catch (err) {
    console.error("assign_employee error", err);
    res.status(500).json({ error: String(err) });
  }
});

// -----------------------------
// feed_log insertion
// -----------------------------
app.post("/api/feed_log", async (req, res) => {
  try {
    const { a_id, f_id, amount, unit, fed_by } = req.body;
    const [
      result,
    ] = await pool.query(
      "INSERT INTO feed_log (a_id, f_id, amount, unit, fed_by) VALUES (?,?,?,?,?)",
      [a_id, f_id, amount || 0, unit || "kg", fed_by || null]
    );
    res.json({ insertId: result.insertId });
  } catch (err) {
    console.error("feed_log insert error", err);
    res.status(500).json({ error: String(err) });
  }
});

// Modular inserts for all tables
const insertSchemas = {
  animal: {
    fields: ["name", "species_id", "birth_date", "gender", "arrival_date"],
    sql:
      "INSERT INTO animal (name, species_id, birth_date, gender, arrival_date) VALUES (?,?,?,?,?)",
  },
  species: {
    fields: ["scientific_name", "common_name", "conservation_status", "size"],
    sql:
      "INSERT INTO species (scientific_name, common_name, conservation_status, size) VALUES (?,?,?,?)",
  },
  enclosure: {
    fields: ["name", "location", "capacity", "size"],
    sql:
      "INSERT INTO enclosure (name, location, capacity, size) VALUES (?,?,?,?)",
  },
  medrec: {
    fields: ["a_id", "last_checked", "next_check", "diseases", "notes"],
    sql:
      "INSERT INTO medrec (a_id, last_checked, next_check, diseases, notes) VALUES (?,?,?,?,?)",
  },
  eats: {
    fields: ["a_id", "species_id", "f_id", "preference"],
    sql:
      "INSERT INTO eats (a_id, species_id, f_id, preference) VALUES (?,?,?,?)",
  },
  visitor: {
    fields: ["name", "age", "contact"],
    sql: "INSERT INTO visitor (name, age, contact) VALUES (?,?,?)",
  },
  ticket: {
    fields: ["type", "price", "visitor_id"],
    sql: "INSERT INTO ticket (type, price, visitor_id) VALUES (?,?,?)",
    preHandler: async (poolConn, body) => {
      if (!body.visitor_id) {
        const [
          v,
        ] = await poolConn.query(
          "INSERT INTO visitor (name, age, contact) VALUES (?, ?, ?)",
          ["Child Visitor", 12, null]
        );
        body.visitor_id = v.insertId;
      }
    },
  },
  food: {
    fields: ["name", "type", "quantity", "unit", "price_per_unit"],
    sql:
      "INSERT INTO food (name, type, quantity, unit, price_per_unit) VALUES (?,?,?,?,?)",
  },
  employee: {
    fields: ["name", "role", "salary", "hire_date"],
    sql:
      "INSERT INTO employee (name, role, salary, hire_date) VALUES (?,?,?,?)",
  },
  infra: {
    fields: ["name", "type", "size"],
    sql: "INSERT INTO infra (name, type, size) VALUES (?,?,?)",
  },
  event: {
    fields: ["title", "e_date", "e_id", "location", "capacity"],
    sql:
      "INSERT INTO event (title, e_date, e_id, location, capacity) VALUES (?,?,?,?,?)",
  },
  event_infra: {
    fields: ["ev_id", "i_id", "quantity"],
    sql: "INSERT INTO event_infra (ev_id, i_id, quantity) VALUES (?,?,?)",
  },
  employee_enclosure: {
    fields: ["emp_id", "e_id", "assigned_from", "assigned_to", "role_desc"],
    sql:
      "INSERT INTO employee_enclosure (emp_id, e_id, assigned_from, assigned_to, role_desc) VALUES (?,?,?,?,?)",
  },
  animal_enclosure: {
    fields: ["a_id", "e_id", "assigned_from", "assigned_to"],
    sql:
      "INSERT INTO animal_enclosure (a_id, e_id, assigned_from, assigned_to) VALUES (?,?,?,?)",
  },
};

app.post("/api/insert/:table", async (req, res) => {
  const table = req.params.table;
  const schema = insertSchemas[table];
  if (!schema)
    return res.status(400).json({ error: "Unknown table: " + table });

  const body = req.body || {};
  const conn = await pool.getConnection();
  try {
    if (schema.preHandler) await schema.preHandler(conn, body);
    const values = schema.fields.map((f) => {
      // if user passed empty string, treat as NULL
      if (body[f] === "") return null;
      return body[f] ?? null;
    });
    const [result] = await conn.query(schema.sql, values);
    res.json({ inserted_id: result.insertId });
  } catch (err) {
    console.error(`insert ${table} error`, err);
    res.status(500).json({ error: String(err) });
  } finally {
    conn.release();
  }
});

// -----------------------------
// Notifications and misc
// -----------------------------
app.get("/api/notifications", async (req, res) => {
  try {
    const [rows] = await pool.query(
      "SELECT * FROM notifications ORDER BY created_at DESC LIMIT 50"
    );
    res.json(rows);
  } catch (err) {
    console.error("notifications error", err);
    res.status(500).json({ error: String(err) });
  }
});
// Generic DELETE endpoint
app.delete("/api/delete/:table/:id", async (req, res) => {
  const { table, id } = req.params;

  const primaryKeys = {
    animal: "a_id",
    species: "s_id",
    enclosure: "e_id",
    medrec: "mr_id",
    eats: "eats_id",
    employee: "emp_id",
    employee_enclosure: "ee_id",
    animal_enclosure: "ae_id",
    food: "f_id",
    visitor: "v_id",
    ticket: "t_id",
    event: "ev_id",
    event_infra: "ei_id",
    infra: "i_id",
    feed_log: "fl_id",
    notifications: "n_id",
  };

  const pk = primaryKeys[table];
  if (!pk) return res.status(400).json({ error: "Unknown table: " + table });

  try {
    const [
      result,
    ] = await pool.query(`DELETE FROM \`${table}\` WHERE \`${pk}\` = ?`, [id]);
    res.json({ deleted: result.affectedRows > 0, id, table });
  } catch (err) {
    console.error(`delete ${table} error`, err);
    res.status(500).json({ error: String(err) });
  }
});

// simple health endpoint
app.get("/api/health", (req, res) => res.json({ ok: true }));

// serve front-end index.html
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

// start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log("Server listening on port", PORT));
