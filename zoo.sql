-- zoo.sql
DROP DATABASE IF EXISTS zoo_db;
CREATE DATABASE zoo_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE zoo_db;

-- Tables

-- SPECIES
CREATE TABLE species (
  s_id INT AUTO_INCREMENT PRIMARY KEY,
  scientific_name VARCHAR(150) NOT NULL UNIQUE,
  common_name VARCHAR(100) NOT NULL,
  conservation_status VARCHAR(50),
  size VARCHAR(50)
);

-- FOOD
CREATE TABLE food (
  f_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE,
  type VARCHAR(50),         
  quantity INT DEFAULT 0,        
  unit VARCHAR(20) DEFAULT 'kg',
  price_per_unit DECIMAL(8,2) DEFAULT 0.00
);

-- ENCLOSURE
CREATE TABLE enclosure (
  e_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE,
  location VARCHAR(100),
  capacity INT NOT NULL DEFAULT 1, 
  size VARCHAR(50)
);

-- ANIMAL
CREATE TABLE animal (
  a_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100),
  species_id INT NOT NULL,
  birth_date DATE,
  gender ENUM('M','F','U') DEFAULT 'U',
  arrival_date DATE,
  FOREIGN KEY (species_id) REFERENCES species(s_id) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- MEDICAL RECORD 
CREATE TABLE medrec (
  mr_id INT AUTO_INCREMENT PRIMARY KEY,
  a_id INT NOT NULL,
  last_checked DATE NOT NULL,
  next_check DATE, 
  diseases TEXT,
  notes TEXT,
  FOREIGN KEY (a_id) REFERENCES animal(a_id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- EATS 
CREATE TABLE eats (
  eats_id INT AUTO_INCREMENT PRIMARY KEY,
  a_id INT NULL,
  species_id INT NULL,
  f_id INT NOT NULL,
  preference ENUM('primary','occasional','supplement') DEFAULT 'primary',
  FOREIGN KEY (a_id) REFERENCES animal(a_id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (species_id) REFERENCES species(s_id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (f_id) REFERENCES food(f_id) ON DELETE RESTRICT ON UPDATE CASCADE
);


-- EMPLOYEE
CREATE TABLE employee (
  emp_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  role VARCHAR(50),
  salary DECIMAL(10,2) DEFAULT 0,
  hire_date DATE
);

-- EMPLOYEE_ENCLOSURE 
CREATE TABLE employee_enclosure (
  ee_id INT AUTO_INCREMENT PRIMARY KEY,
  emp_id INT NOT NULL,
  e_id INT NOT NULL,
  assigned_from DATETIME DEFAULT CURRENT_TIMESTAMP,
  assigned_to DATE NULL,
  role_desc VARCHAR(100),
  FOREIGN KEY (emp_id) REFERENCES employee(emp_id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (e_id) REFERENCES enclosure(e_id) ON DELETE CASCADE ON UPDATE CASCADE,
  UNIQUE KEY uq_emp_enc (emp_id, e_id)
);


-- INFRASTRUCTURE
CREATE TABLE infra (
  i_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  type VARCHAR(50),
  size VARCHAR(50)
);

-- EVENT
CREATE TABLE event (
  ev_id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(150) NOT NULL,
  e_date DATE NOT NULL,
  e_id INT NULL,       
  location VARCHAR(150),
  capacity INT DEFAULT 0,
  FOREIGN KEY (e_id) REFERENCES enclosure(e_id) ON DELETE SET NULL ON UPDATE CASCADE
);

-- EVENT_INFRA 
CREATE TABLE event_infra (
  ei_id INT AUTO_INCREMENT PRIMARY KEY,
  ev_id INT NOT NULL,
  i_id INT NOT NULL,
  quantity INT DEFAULT 1,
  FOREIGN KEY (ev_id) REFERENCES event(ev_id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (i_id) REFERENCES infra(i_id) ON DELETE CASCADE ON UPDATE CASCADE,
  UNIQUE KEY uq_event_infra (ev_id, i_id)
);

-- VISITOR
CREATE TABLE visitor (
  v_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120),
  age INT,
  contact VARCHAR(100)
);

-- TICKET
CREATE TABLE ticket (
  t_id INT AUTO_INCREMENT PRIMARY KEY,
  type VARCHAR(50),
  price DECIMAL(8,2) DEFAULT 0.00,
  sold_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  visitor_id INT,
  FOREIGN KEY (visitor_id) REFERENCES visitor(v_id) ON DELETE SET NULL ON UPDATE CASCADE
);

-- FEED_LOG 
CREATE TABLE feed_log (
  fl_id INT AUTO_INCREMENT PRIMARY KEY,
  a_id INT NOT NULL,
  f_id INT NOT NULL,
  fed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  amount DECIMAL(8,2) DEFAULT 0,
  unit VARCHAR(20) DEFAULT 'kg',
  fed_by INT NULL, -- employee id
  FOREIGN KEY (a_id) REFERENCES animal(a_id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (f_id) REFERENCES food(f_id) ON DELETE RESTRICT ON UPDATE CASCADE,
  FOREIGN KEY (fed_by) REFERENCES employee(emp_id) ON DELETE SET NULL ON UPDATE CASCADE
);

-- ANIMAL_ENCLOSURE
CREATE TABLE animal_enclosure (
  ae_id INT AUTO_INCREMENT PRIMARY KEY,
  a_id INT NOT NULL,
  e_id INT NOT NULL,
  assigned_from DATETIME DEFAULT CURRENT_TIMESTAMP,
  assigned_to DATE NULL,
  FOREIGN KEY (a_id) REFERENCES animal(a_id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (e_id) REFERENCES enclosure(e_id) ON DELETE CASCADE ON UPDATE CASCADE,
  UNIQUE KEY uq_animal_current (a_id, assigned_to)
);


-- notifications
CREATE TABLE notifications (
  n_id INT AUTO_INCREMENT PRIMARY KEY,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  level VARCHAR(10),
  message TEXT
);

-- ------------------------------------------------
-- Triggers
-- When a medrec is inserted or updated, if next_check is NULL, set it to last_checked + 30 days (example)
-- When food quantity is updated (via feed_log insert we decrease), produce a low-stock notification if below threshold
-- ------------------------------------------------

DELIMITER $$

-- Trigger to set next_check if not provided
CREATE TRIGGER trg_medrec_nextcheck_before_insert
BEFORE INSERT ON medrec
FOR EACH ROW
BEGIN
  IF NEW.next_check IS NULL THEN
    SET NEW.next_check = DATE_ADD(NEW.last_checked, INTERVAL 30 DAY);
  END IF;
END$$

CREATE TRIGGER trg_medrec_nextcheck_before_update
BEFORE UPDATE ON medrec
FOR EACH ROW
BEGIN
  IF NEW.next_check IS NULL THEN
    SET NEW.next_check = DATE_ADD(NEW.last_checked, INTERVAL 30 DAY);
  END IF;
END$$

-- Trigger2
CREATE TRIGGER trg_feedlog_after_insert
AFTER INSERT ON feed_log
FOR EACH ROW
BEGIN
  -- reduce stock
  UPDATE food SET quantity = GREATEST(quantity - NEW.amount, 0) WHERE f_id = NEW.f_id;

  -- check low stock (threshold = 10 units)
  IF (SELECT quantity FROM food WHERE f_id = NEW.f_id) < 10 THEN
    INSERT INTO notifications(level, message)
      VALUES('WARN', CONCAT('Low stock for food id ', NEW.f_id, ': ', (SELECT quantity FROM food WHERE f_id = NEW.f_id)));
  END IF;
END$$

DELIMITER ;

-- ------------------------------------------------
-- Functions
-- 1) animal_age(a_id) -> returns age in years (int)
-- 2) enclosure_remaining_capacity(e_id) -> returns remaining slots (int)
-- ------------------------------------------------

DELIMITER $$
CREATE FUNCTION animal_age(p_aid INT) RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE bd DATE;
  DECLARE age INT;
  SELECT birth_date INTO bd FROM animal WHERE a_id = p_aid;
  IF bd IS NULL THEN
    RETURN NULL;
  END IF;
  SET age = TIMESTAMPDIFF(YEAR, bd, CURDATE());
  RETURN age;
END$$

CREATE FUNCTION enclosure_remaining_capacity(p_eid INT) RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE cap INT DEFAULT 0;
  DECLARE occupied INT DEFAULT 0;
  SELECT capacity INTO cap FROM enclosure WHERE e_id = p_eid;
  SELECT COUNT(*) INTO occupied FROM animal_enclosure WHERE e_id = p_eid AND (assigned_to IS NULL OR assigned_to > CURDATE());
  RETURN GREATEST(cap - occupied, 0);
END$$
DELIMITER ;

-- ------------------------------------------------
-- Stored Procedures
-- 1) schedule_event(title, date, enclosure_id, capacity) -> inserts event if enclosure has space or capacity=0; returns ev_id
-- 2) assign_employee(p_emp_id, p_e_id, role_desc) -> assigns if not assigned already; returns success code
-- ------------------------------------------------
DELIMITER $$

DROP PROCEDURE IF EXISTS schedule_event;
DELIMITER //

CREATE PROCEDURE schedule_event(
  IN p_title VARCHAR(100),
  IN p_date DATE,
  IN p_eid INT,
  IN p_capacity INT,
  OUT p_out_ev_id INT
)
BEGIN
  DECLARE v_location VARCHAR(100);

  SELECT location INTO v_location
  FROM enclosure
  WHERE e_id = p_eid
  LIMIT 1;

  IF v_location IS NULL THEN
    SET v_location = 'General Zone';
  END IF;

  INSERT INTO event (title, e_date, capacity, e_id, location)
  VALUES (p_title, p_date, p_capacity, p_eid, v_location);

  SET p_out_ev_id = LAST_INSERT_ID();

  IF EXISTS (SELECT 1 FROM infra WHERE i_id = 1) THEN
    INSERT INTO event_infra (ev_id, i_id, quantity)
    VALUES (p_out_ev_id, 1, 1);
  END IF;

  IF EXISTS (SELECT 1 FROM infra WHERE i_id = 2) THEN
    INSERT INTO event_infra (ev_id, i_id, quantity)
    VALUES (p_out_ev_id, 2, 1);
  END IF;

  INSERT INTO notifications(level, message)
  VALUES ('INFO', CONCAT('Auto infra assigned for event ID ', p_out_ev_id));

END //

DELIMITER ;




CREATE PROCEDURE assign_employee(
  IN p_emp_id INT,
  IN p_e_id INT,
  IN p_role VARCHAR(100),
  OUT p_success TINYINT
)
BEGIN
  IF EXISTS (SELECT 1 FROM employee_enclosure WHERE emp_id = p_emp_id AND e_id = p_e_id) THEN
    SET p_success = 0;
  ELSE
    INSERT INTO employee_enclosure(emp_id, e_id, role_desc)
    VALUES(p_emp_id, p_e_id, p_role);
    SET p_success = 1;
  END IF;
END$$

DELIMITER ;



-- view

CREATE VIEW vw_enclosure_status AS
SELECT enc.e_id, enc.name AS enclosure_name, enc.capacity,
       COUNT(ae.ae_id) AS occupied,
       enc.capacity - COUNT(ae.ae_id) AS remaining
FROM enclosure enc
LEFT JOIN animal_enclosure ae ON ae.e_id = enc.e_id AND (ae.assigned_to IS NULL OR ae.assigned_to > CURDATE())
GROUP BY enc.e_id, enc.name, enc.capacity;

-- init inserts

-- species
INSERT INTO species (scientific_name, common_name, conservation_status, size) VALUES
('Panthera tigris', 'Tiger', 'Endangered', 'Large'),
('Elephas maximus', 'Asian Elephant', 'Endangered', 'Huge'),
('Giraffa camelopardalis', 'Giraffe', 'Vulnerable', 'Large'),
('Lemur catta', 'Ring-tailed Lemur', 'Near Threatened', 'Small'),
('Ailuropoda melanoleuca', 'Giant Panda', 'Vulnerable', 'Large');

-- food
INSERT INTO food (name, type, quantity, unit, price_per_unit) VALUES
('Beef', 'meat', 200, 'kg', 5.00),
('Chicken', 'meat', 300, 'kg', 3.50),
('Bamboo', 'plant', 500, 'kg', 0.50),
('Fruits Mix', 'fruit', 250, 'kg', 2.00),
('Pellets', 'pellet', 400, 'kg', 1.50);

-- enclosure
INSERT INTO enclosure (name, location, capacity, size) VALUES
('Big Cats Zone', 'North-West', 4, 'Large'),
('Elephant Ground', 'East', 6, 'Huge'),
('Savannah View', 'South', 8, 'Very Large'),
('Primate House', 'Center', 12, 'Medium'),
('Panda Corner', 'West', 2, 'Small');

-- animals
INSERT INTO animal (name, species_id, birth_date, gender, arrival_date) VALUES
('Sheru', 1, '2015-06-10', 'M', '2016-01-01'),
('Maya',   2, '2010-04-05', 'F', '2011-03-12'),
('Gina',   3, '2017-09-01', 'F', '2018-01-15'),
('Lina',   4, '2019-11-25', 'F', '2020-02-10'),
('Bao',    5, '2016-12-12', 'M', '2017-02-07');

-- medrec
INSERT INTO medrec (a_id, last_checked, diseases, notes) VALUES
(1, '2025-09-01', 'None', 'Healthy'),
(2, '2025-08-15', 'Arthritis', 'On supplements'),
(3, '2025-09-10', 'None', 'Good appetite'),
(4, '2025-07-01', 'Parasite', 'Treated'),
(5, '2025-08-20', 'None', 'Check dental');

-- eats: species-level preferences
INSERT INTO eats (species_id, f_id, preference) VALUES
(1, 1, 'primary'),  
(1, 2, 'occasional'),  
(2, 2, 'primary'),     
(2, 4, 'primary'),  
(5, 3, 'primary'),    
(3, 4, 'primary'),    
(4, 4, 'primary');   

-- employees
INSERT INTO employee (name, role, salary, hire_date) VALUES
('Alice', 'Veterinarian', 4500.00, '2019-05-01'),
('Bob', 'Keeper', 2800.00, '2020-03-15'),
('Charlie', 'Head Keeper', 3500.00, '2018-11-20'),
('Daisy', 'Event Coord', 3000.00, '2021-04-01');

-- infra
INSERT INTO infra (name, type, size) VALUES
('Stage A', 'Stage', 'Large'),
('PA System', 'Audio', 'Medium'),
('Projector', 'Tech', 'Small'),
('Tents', 'Shelter', 'Various');

-- event
INSERT INTO event (title, e_date, e_id, location, capacity) VALUES
('Nocturnal Walk', '2025-10-15', 3, 'Savannah View', 30),
('Panda Meet', '2025-11-01', 5, 'Panda Corner', 20);

-- event_infra
INSERT INTO event_infra (ev_id, i_id, quantity) VALUES
(1,1,1),(1,2,1),(2,3,1);

-- animal_enclosure
INSERT INTO animal_enclosure (a_id, e_id, assigned_from) VALUES
(1,1,'2016-01-10'), 
(2,2,'2011-03-12'), -
(3,3,'2018-02-02'),
(4,4,'2020-02-11'),
(5,5,'2017-02-08');

-- feed_log 
INSERT INTO feed_log (a_id, f_id, amount, unit, fed_by) VALUES
(1,1,8,'kg',2),
(2,4,25,'kg',3),
(5,3,12,'kg',2);

-- visitor & ticket
INSERT INTO visitor (name, age, contact) VALUES
('Eve', 28, 'eve@example.com'),
('Frank', 35, 'frank@example.com');

INSERT INTO ticket (type, price, visitor_id) VALUES
('Adult', 15.00, 1),
('Adult', 15.00, 2),
('Child', 8.00, NULL);

-- a few notifications inserted
INSERT INTO notifications (level, message) VALUES
('INFO', 'Database seeded'), ('INFO','Welcome to Zoo DB');

mysql -u root -p -e "CREATE USER IF NOT EXISTS 'zoo_user'@'localhost' IDENTIFIED BY 'Zoozoo@123';
GRANT ALL PRIVILEGES ON zoo_db.* TO 'zoo_user'@'localhost';
FLUSH PRIVILEGES;"
