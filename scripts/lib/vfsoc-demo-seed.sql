-- =====================================================================
-- VFSOC Demo Seed: Connectors + Fleets + Mobility Assets + Links
-- =====================================================================
-- Idempotent. Reflects the canonical assets, fleets, and connectors that
-- the VFSOC platform actually exercises end-to-end:
--   * VFSOC-Ingestion's 9 snake_case connector types and the EV-001..EV-004
--     vehicle map used by its connector simulators.
--   * VFSOC-SIEM's mock alert data (mockAssets, mockAlertInstances) so
--     every vehicle/device referenced by an alert exists in the unified
--     DB and the admin overview reflects what the analyst actually sees.
--   * VFSOC-ML-Models's 7 inference connectors (which map 1:1 onto the
--     ingestion connectors above; aws_cloudwatch -> aws at inference time).
--
-- OpenSearch is intentionally not consulted: in a clean install it is
-- empty, and the data eventually written into vehilog/alert-i*/ioc-* is
-- generated from the same connector + asset identifiers seeded here.
--
-- Run with:
--   docker exec -i -e PGPASSWORD=postgres vfsoc-postgres psql -U postgres -d vfsoc \
--     < scripts/lib/vfsoc-demo-seed.sql
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Org reference (created by db-schema.sql)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_org_id UUID := '550e8400-e29b-41d4-a716-446655440000';
BEGIN
    PERFORM 1 FROM organizations WHERE id = v_org_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'VFSOC organization 550e8400-e29b-41d4-a716-446655440000 not found. Apply db-schema.sql first.';
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 1. CONNECTORS
-- ---------------------------------------------------------------------
-- The 9 canonical snake_case connector types written by VFSOC-Ingestion.
-- Names + types are intentionally consistent with the existing 7 seed
-- connectors from db-schema.sql; this UPSERT only extends them.

INSERT INTO connectors (name, connector_type, description, org_id) VALUES
    ('AWS CloudWatch',          'aws_cloudwatch',
     'AWS CloudWatch and CloudTrail data source (cloud backend)',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Vehicle Telematics',      'vehicle_telematics',
     'Connected vehicle telematics, GPS, CAN bus, and OBD-II data',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Tesla ADAS',              'tesla_adas',
     'Tesla autopilot / ADAS event stream',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('EV Charging Station',     'ev_charging_station',
     'OCPP-based EV charging station telemetry and session events',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Vertiports Management',   'vertiports',
     'AAM / drone vertiport scheduling, charging, and dispatch events',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Endpoint Detection',      'endpoint_detection',
     'Endpoint detection and response (EDR) for onboard and fleet devices',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('In-Vehicle Payment',      'in_vehicle_payment',
     'In-vehicle payment terminal transactions and fraud signals',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Physical Security',       'physical_security',
     'Depot, gate, and facility physical security access events',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Roadside Sensor',         'roadside_sensor',
     'Roadside infrastructure sensors, RSUs, and V2X messages',
     '550e8400-e29b-41d4-a716-446655440000')
ON CONFLICT (name, org_id) DO UPDATE
    SET connector_type = EXCLUDED.connector_type,
        description    = EXCLUDED.description,
        is_enabled     = true;

-- Deactivate any legacy connectors whose names differ from the canonical
-- set above so the admin overview doesn't report duplicates.
UPDATE connectors
   SET is_enabled = false
 WHERE org_id = '550e8400-e29b-41d4-a716-446655440000'
   AND name NOT IN (
       'AWS CloudWatch','Vehicle Telematics','Tesla ADAS',
       'EV Charging Station','Vertiports Management','Endpoint Detection',
       'In-Vehicle Payment','Physical Security','Roadside Sensor'
   );

-- ---------------------------------------------------------------------
-- 2. FLEETS
-- ---------------------------------------------------------------------
-- 15 fleets covering EV fleets (Ingestion EV-00x map + SIEM mock fleets),
-- ICE delivery/service/security, aerial (drones + VTOL), charging,
-- traffic management, vertiports, depot security, and mobile devices.

INSERT INTO fleets (name, description, org_id) VALUES
    ('EV-001',                'Primary EV passenger + transit fleet (Vehicle Telematics + AWS)',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('EV-002',                'Secondary EV bus fleet (Roadside Sensor + In-Vehicle Payment)',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('EV-003',                'EV truck fleet (Physical Security correlated)',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('EV-004',                'EV reserve fleet (Ingestion EV-004 map)',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('FLEET001',              'Central fleet management + backend gateways',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('DELIVERY_FLEET',        'ICE delivery vehicles',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('SERVICE_FLEET',         'ICE service vehicles',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('SECURITY_FLEET',        'ICE patrol / security vehicles',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('DRONE_FLEET',           'Delivery drones + legacy VTOL transport',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('AERIAL-FLEET-001',      'Alert-correlated aerial fleet (drones + VTOL + flight control)',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('VTOL-FLEET-003',        'Dedicated VTOL fleet',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('EV_CHARGING_NETWORK',   'EV charging stations (OCPP)',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('TRAFFIC_MGMT',          'Traffic management roadside sensors, RSUs, V2X',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('VERTIPORT_NETWORK',     'AAM vertiports + landing platforms',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('DEPOT_SECURITY',        'Depot, gate, and facility physical security',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('FLEET_MOBILE',          'Fleet laptops, tablets, and mobile devices',
     '550e8400-e29b-41d4-a716-446655440000')
ON CONFLICT (name, org_id) DO UPDATE
    SET description = EXCLUDED.description;

-- ---------------------------------------------------------------------
-- 3. MOBILITY ASSETS
-- ---------------------------------------------------------------------
-- Single TEMP staging table makes the bulk insert + fleet lookup easy.

CREATE TEMP TABLE _vfsoc_assets (
    asset_identifier TEXT PRIMARY KEY,
    asset_name       TEXT NOT NULL,
    asset_type       TEXT NOT NULL,
    fleet_name       TEXT NOT NULL
) ON COMMIT DROP;

INSERT INTO _vfsoc_assets (asset_identifier, asset_name, asset_type, fleet_name) VALUES
    -- EV-001 fleet (ingestion EV-001 map = V01..V13, SIEM alert-correlated subset)
    ('EV-001-V01',     'Electric Vehicle 001-V01 (car)',         'car',        'EV-001'),
    ('EV-001-V02',     'Electric Vehicle 001-V02 (sedan)',       'car',        'EV-001'),
    ('EV-001-V03',     'Electric Vehicle 001-V03 (SUV)',         'car',        'EV-001'),
    ('EV-001-V04',     'Electric Vehicle 001-V04 (transit)',     'transit',    'EV-001'),
    ('EV-001-V05',     'Electric Vehicle 001-V05 (car)',         'car',        'EV-001'),
    ('EV-001-V06',     'Electric Vehicle 001-V06 (car)',         'car',        'EV-001'),
    ('EV-001-V07',     'Electric Vehicle 001-V07 (car)',         'car',        'EV-001'),
    ('EV-001-V08',     'Electric Vehicle 001-V08 (sedan)',       'car',        'EV-001'),
    ('EV-001-V09',     'Electric Vehicle 001-V09 (car)',         'car',        'EV-001'),
    ('EV-001-V10',     'Electric Vehicle 001-V10 (car)',         'car',        'EV-001'),
    ('EV-001-V11',     'Electric Vehicle 001-V11 (car)',         'car',        'EV-001'),
    ('EV-001-V12',     'Electric Vehicle 001-V12 (car)',         'car',        'EV-001'),
    ('EV-001-V13',     'Electric Vehicle 001-V13 (car)',         'car',        'EV-001'),
    ('EV-001-V14',     'Electric Vehicle 001-V14 (truck)',       'truck',      'EV-001'),

    -- EV-002 fleet (ingestion V01..V07, SIEM uses V01/V03 for bus alerts)
    ('EV-002-V01',     'Electric Bus 002-V01',                   'bus',        'EV-002'),
    ('EV-002-V02',     'Electric Bus 002-V02',                   'bus',        'EV-002'),
    ('EV-002-V03',     'Electric Bus 002-V03',                   'bus',        'EV-002'),
    ('EV-002-V04',     'Electric Bus 002-V04',                   'bus',        'EV-002'),
    ('EV-002-V05',     'Electric Bus 002-V05',                   'bus',        'EV-002'),
    ('EV-002-V06',     'Electric Bus 002-V06',                   'bus',        'EV-002'),
    ('EV-002-V07',     'Electric Bus 002-V07',                   'bus',        'EV-002'),

    -- EV-003 fleet (ingestion V01..V05)
    ('EV-003-V01',     'Electric Truck 003-V01',                 'truck',      'EV-003'),
    ('EV-003-V02',     'Electric Truck 003-V02',                 'truck',      'EV-003'),
    ('EV-003-V03',     'Electric Truck 003-V03',                 'truck',      'EV-003'),
    ('EV-003-V04',     'Electric Truck 003-V04',                 'truck',      'EV-003'),
    ('EV-003-V05',     'Electric Truck 003-V05',                 'truck',      'EV-003'),

    -- EV-004 fleet (ingestion V01..V05)
    ('EV-004-V01',     'Electric Vehicle 004-V01',               'car',        'EV-004'),
    ('EV-004-V02',     'Electric Vehicle 004-V02',               'car',        'EV-004'),
    ('EV-004-V03',     'Electric Vehicle 004-V03',               'car',        'EV-004'),
    ('EV-004-V04',     'Electric Vehicle 004-V04',               'car',        'EV-004'),
    ('EV-004-V05',     'Electric Vehicle 004-V05',               'car',        'EV-004'),

    -- FLEET001 (SIEM "central fleet" + backend)
    ('VEH015',         'Fleet Vehicle 015',                      'car',        'FLEET001'),
    ('AWS-MONITOR-001','AWS Monitoring System 001',              'gateway',    'FLEET001'),
    ('API-GW-001',     'API Gateway 001',                        'gateway',    'FLEET001'),

    -- ICE fleets
    ('ICE-V001',       'Delivery Truck ICE-001',                 'truck',      'DELIVERY_FLEET'),
    ('ICE-V002',       'Service Truck ICE-002',                  'truck',      'SERVICE_FLEET'),
    ('ICE-V003',       'Patrol Vehicle ICE-003',                 'car',        'SECURITY_FLEET'),

    -- Aerial fleets
    ('DRONE-V001',     'Delivery Drone 001',                     'drone',      'DRONE_FLEET'),
    ('VTOL-V001',      'VTOL Transport 001',                     'aam',        'DRONE_FLEET'),
    ('DRONE-001-V01',  'Delivery Drone 001-V01',                 'drone',      'AERIAL-FLEET-001'),
    ('DRONE-003-V01',  'Survey Drone 003-V01',                   'drone',      'AERIAL-FLEET-001'),
    ('DRONE-FC-001',   'Drone Flight Controller 001',            'other',      'AERIAL-FLEET-001'),
    ('DRONE-CTRL-002', 'Drone Control System 002',               'other',      'AERIAL-FLEET-001'),
    ('VTOL-002-V04',   'VTOL Transport 002-V04',                 'aam',        'AERIAL-FLEET-001'),
    ('VTOL-NAV-003',   'VTOL Navigation System 003',             'other',      'AERIAL-FLEET-001'),
    ('VTOL-001-V02',   'VTOL Transport 001-V02',                 'aam',        'VTOL-FLEET-003'),
    ('VTOL-COMM-001',  'VTOL Communication Module 001',          'other',      'VTOL-FLEET-003'),

    -- Charging infrastructure (SIEM CHG-001/003 + ingestion CHG-01..CHG-15 abbreviated)
    ('CHG-001',        'Fast Charging Station 001 (downtown)',   'ev_charger', 'EV_CHARGING_NETWORK'),
    ('CHG-002',        'Fast Charging Station 002 (highway)',    'ev_charger', 'EV_CHARGING_NETWORK'),
    ('CHG-003',        'Fast Charging Station 003 (depot)',      'ev_charger', 'EV_CHARGING_NETWORK'),
    ('CHG-004',        'Charging Station 004 (mall)',            'ev_charger', 'EV_CHARGING_NETWORK'),
    ('CHG-005',        'Charging Station 005 (airport)',         'ev_charger', 'EV_CHARGING_NETWORK'),

    -- Traffic / roadside (SIEM + ingestion sensors)
    ('SENSOR-001',     'Traffic Management Sensor 001',          'sensor',     'TRAFFIC_MGMT'),
    ('SENSOR-045',     'Roadside Sensor 045',                    'sensor',     'TRAFFIC_MGMT'),
    ('RSU-001',        'Roadside Unit 001',                      'sensor',     'TRAFFIC_MGMT'),
    ('RSU-002',        'Roadside Unit 002',                      'sensor',     'TRAFFIC_MGMT'),
    ('RSU-003',        'Roadside Unit 003',                      'sensor',     'TRAFFIC_MGMT'),

    -- Vertiports
    ('VPORT-001',      'Downtown Vertiport',                     'vertiport',  'VERTIPORT_NETWORK'),
    ('VPORT-002',      'Airport Vertiport Hub',                  'vertiport',  'VERTIPORT_NETWORK'),

    -- Backend / EV-001 sub-devices
    ('OTA-SRV-002',    'OTA Update Server 002',                  'gateway',    'EV-001'),
    ('VEHISW-API-001', 'Vehicle Software API Gateway 001',       'gateway',    'EV-001'),
    ('CAN-001',        'CAN Bus Controller 001',                 'other',      'EV-001'),
    ('CAN-002',        'CAN Bus Controller 002',                 'other',      'EV-001'),
    ('TCU-004',        'Telematics Control Unit 004',            'other',      'EV-001'),
    ('KEYLESS-001',    'Keyless Entry System 001',               'other',      'EV-001'),
    ('V2X-001',        'Vehicle-to-Everything Module 001',       'other',      'EV-002'),

    -- Depot / physical security
    ('PHYS-SEC-001',   'Depot Physical Security System 001',     'depot',      'DEPOT_SECURITY'),

    -- Mobile devices
    ('FLT-LAP-007',    'Fleet Laptop 007',                       'other',      'FLEET_MOBILE'),
    ('TABLET-001',     'Driver Tablet 001',                      'other',      'FLEET_MOBILE'),
    ('MOBILE-001',     'Fleet Mobile Device 001',                'other',      'FLEET_MOBILE')
ON CONFLICT DO NOTHING;

-- Upsert into mobility_assets, resolving fleet_id by name.
INSERT INTO mobility_assets (asset_identifier, asset_name, asset_type, fleet_id, org_id, status)
SELECT s.asset_identifier,
       s.asset_name,
       s.asset_type,
       f.id,
       '550e8400-e29b-41d4-a716-446655440000',
       'active'
FROM _vfsoc_assets s
JOIN fleets f ON f.name = s.fleet_name
            AND f.org_id = '550e8400-e29b-41d4-a716-446655440000'
ON CONFLICT (asset_identifier, org_id) DO UPDATE
    SET asset_name = EXCLUDED.asset_name,
        asset_type = EXCLUDED.asset_type,
        fleet_id   = EXCLUDED.fleet_id,
        status     = 'active';

-- ---------------------------------------------------------------------
-- 4. ASSET <-> CONNECTOR LINKS
-- ---------------------------------------------------------------------
-- Captures which connectors feed events about which assets, based on
-- mockAssets[].connectors in VFSOC-SIEM/src/components/data/alertsData.ts
-- and the connector-to-asset mapping baked into VFSOC-Ingestion's
-- per-connector simulators.

CREATE TEMP TABLE _vfsoc_links (
    asset_identifier TEXT NOT NULL,
    connector_name   TEXT NOT NULL,
    notes            TEXT
) ON COMMIT DROP;

INSERT INTO _vfsoc_links (asset_identifier, connector_name, notes) VALUES
    -- EV-001 fleet
    ('EV-001-V01',     'Vehicle Telematics',  'Telematics + GPS'),
    ('EV-001-V01',     'AWS CloudWatch',      'Backend telemetry'),
    ('EV-001-V02',     'Vehicle Telematics',  'Telematics + GPS'),
    ('EV-001-V02',     'AWS CloudWatch',      'Backend telemetry + OTA logs'),
    ('EV-001-V03',     'EV Charging Station', 'Frequent charger user'),
    ('EV-001-V03',     'Vehicle Telematics',  'Telematics'),
    ('EV-001-V04',     'Vehicle Telematics',  'Transit unit telematics'),
    ('EV-001-V04',     'Tesla ADAS',          'Tesla-equipped transit'),
    ('EV-001-V05',     'Vehicle Telematics',  NULL),
    ('EV-001-V06',     'Vehicle Telematics',  NULL),
    ('EV-001-V07',     'Vehicle Telematics',  NULL),
    ('EV-001-V08',     'Vehicle Telematics',  NULL),
    ('EV-001-V08',     'AWS CloudWatch',      'Backend telemetry'),
    ('EV-001-V09',     'Vehicle Telematics',  NULL),
    ('EV-001-V10',     'Vehicle Telematics',  NULL),
    ('EV-001-V11',     'Vehicle Telematics',  NULL),
    ('EV-001-V12',     'Vehicle Telematics',  NULL),
    ('EV-001-V13',     'Vehicle Telematics',  NULL),
    ('EV-001-V14',     'Vehicle Telematics',  'Light truck telematics'),

    -- EV-002 fleet (buses)
    ('EV-002-V01',     'Vehicle Telematics',  NULL),
    ('EV-002-V01',     'In-Vehicle Payment',  'Bus fare terminal'),
    ('EV-002-V02',     'Vehicle Telematics',  NULL),
    ('EV-002-V02',     'In-Vehicle Payment',  'Bus fare terminal'),
    ('EV-002-V03',     'Vehicle Telematics',  NULL),
    ('EV-002-V03',     'Roadside Sensor',     'Speed/heading correlation'),
    ('EV-002-V04',     'Vehicle Telematics',  NULL),
    ('EV-002-V05',     'Vehicle Telematics',  NULL),
    ('EV-002-V06',     'Vehicle Telematics',  NULL),
    ('EV-002-V07',     'Vehicle Telematics',  NULL),

    -- EV-003 fleet (trucks)
    ('EV-003-V01',     'Vehicle Telematics',  NULL),
    ('EV-003-V02',     'Vehicle Telematics',  NULL),
    ('EV-003-V03',     'Vehicle Telematics',  NULL),
    ('EV-003-V04',     'Vehicle Telematics',  NULL),
    ('EV-003-V05',     'Vehicle Telematics',  NULL),
    ('EV-003-V05',     'Physical Security',   'Depot gate entry correlation'),

    -- EV-004 fleet
    ('EV-004-V01',     'Vehicle Telematics',  NULL),
    ('EV-004-V02',     'Vehicle Telematics',  NULL),
    ('EV-004-V03',     'Vehicle Telematics',  NULL),
    ('EV-004-V04',     'Vehicle Telematics',  NULL),
    ('EV-004-V05',     'Vehicle Telematics',  NULL),

    -- FLEET001 backend assets
    ('VEH015',         'Vehicle Telematics',  NULL),
    ('VEH015',         'AWS CloudWatch',      'Backend monitoring'),
    ('AWS-MONITOR-001','AWS CloudWatch',      'Cloud monitor host'),
    ('API-GW-001',     'AWS CloudWatch',      'API gateway logs'),

    -- ICE vehicles
    ('ICE-V001',       'Vehicle Telematics',  NULL),
    ('ICE-V002',       'Vehicle Telematics',  NULL),
    ('ICE-V003',       'Vehicle Telematics',  NULL),
    ('ICE-V003',       'Physical Security',   'Patrol radio + depot gate'),

    -- Aerial
    ('DRONE-V001',     'Vertiports Management',  'Departure/landing at vertiports'),
    ('VTOL-V001',      'Vertiports Management',  'Departure/landing at vertiports'),
    ('DRONE-001-V01',  'Vertiports Management',  NULL),
    ('DRONE-003-V01',  'Vertiports Management',  NULL),
    ('DRONE-FC-001',   'Endpoint Detection',  'Flight controller endpoint'),
    ('DRONE-CTRL-002', 'Endpoint Detection',  'Ground-control endpoint'),
    ('VTOL-002-V04',   'Vertiports Management',  NULL),
    ('VTOL-NAV-003',   'Endpoint Detection',  'Avionics endpoint'),
    ('VTOL-001-V02',   'Vertiports Management',  NULL),
    ('VTOL-COMM-001',  'Endpoint Detection',  'Comm module endpoint'),

    -- Charging stations
    ('CHG-001',        'EV Charging Station', 'OCPP session telemetry'),
    ('CHG-001',        'In-Vehicle Payment',  'Card / RFID payment'),
    ('CHG-002',        'EV Charging Station', NULL),
    ('CHG-003',        'EV Charging Station', NULL),
    ('CHG-003',        'In-Vehicle Payment',  'Card / RFID payment'),
    ('CHG-004',        'EV Charging Station', NULL),
    ('CHG-005',        'EV Charging Station', NULL),

    -- Roadside / traffic
    ('SENSOR-001',     'Roadside Sensor',     NULL),
    ('SENSOR-045',     'Roadside Sensor',     NULL),
    ('RSU-001',        'Roadside Sensor',     'V2X RSU'),
    ('RSU-002',        'Roadside Sensor',     'V2X RSU'),
    ('RSU-003',        'Roadside Sensor',     'V2X RSU'),

    -- Vertiports
    ('VPORT-001',      'Vertiports Management',  NULL),
    ('VPORT-001',      'Physical Security',   'Vertiport gate access'),
    ('VPORT-002',      'Vertiports Management',  NULL),
    ('VPORT-002',      'Physical Security',   'Vertiport gate access'),

    -- EV-001 sub-devices
    ('OTA-SRV-002',    'AWS CloudWatch',      'OTA server in AWS'),
    ('VEHISW-API-001', 'AWS CloudWatch',      'Vehicle SW backend API'),
    ('CAN-001',        'Vehicle Telematics',  'CAN gateway uplink'),
    ('CAN-002',        'Vehicle Telematics',  'CAN gateway uplink'),
    ('TCU-004',        'Vehicle Telematics',  'TCU uplink'),
    ('KEYLESS-001',    'Vehicle Telematics',  'Keyless event uplink'),
    ('V2X-001',        'Roadside Sensor',     'V2X exchange'),

    -- Depot security
    ('PHYS-SEC-001',   'Physical Security',   'Depot main security panel'),

    -- Mobile / fleet endpoints
    ('FLT-LAP-007',    'Endpoint Detection',  'Fleet laptop EDR agent'),
    ('TABLET-001',     'Endpoint Detection',  'Driver tablet EDR/MDM'),
    ('MOBILE-001',     'Endpoint Detection',  'Fleet phone EDR/MDM');

-- Upsert links, resolving asset_id and connector_id by name.
INSERT INTO asset_connector_links (asset_id, connector_id, is_enabled, notes)
SELECT a.id, c.id, true, l.notes
  FROM _vfsoc_links l
  JOIN mobility_assets a ON a.asset_identifier = l.asset_identifier
                        AND a.org_id = '550e8400-e29b-41d4-a716-446655440000'
  JOIN connectors      c ON c.name = l.connector_name
                        AND c.org_id = '550e8400-e29b-41d4-a716-446655440000'
ON CONFLICT (asset_id, connector_id) DO UPDATE
    SET is_enabled = true,
        notes      = COALESCE(EXCLUDED.notes, asset_connector_links.notes);

-- ---------------------------------------------------------------------
-- 5. SUMMARY (printed to stdout when run via psql)
-- ---------------------------------------------------------------------
\echo
\echo 'VFSOC demo seed summary:'
SELECT 'connectors (active)' AS object, COUNT(*) AS n
  FROM connectors
 WHERE is_enabled = true
   AND org_id = '550e8400-e29b-41d4-a716-446655440000'
UNION ALL
SELECT 'fleets', COUNT(*) FROM fleets
 WHERE org_id = '550e8400-e29b-41d4-a716-446655440000'
UNION ALL
SELECT 'mobility_assets', COUNT(*) FROM mobility_assets
 WHERE org_id = '550e8400-e29b-41d4-a716-446655440000'
UNION ALL
SELECT 'mobility_assets (by type)' || ' ' || asset_type, COUNT(*)
  FROM mobility_assets
 WHERE org_id = '550e8400-e29b-41d4-a716-446655440000'
 GROUP BY asset_type
UNION ALL
SELECT 'asset_connector_links', COUNT(*)
  FROM asset_connector_links
ORDER BY object;

COMMIT;
