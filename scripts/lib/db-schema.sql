-- =====================================================================
-- VFSOC Unified Database Schema
-- =====================================================================
-- Shared by VFSOC-SIEM (Main Dashboard), VFSOC-Admin, and VFSOC-Ingestion.
-- Includes:
--   - Organizations, users, sessions, auth audit
--   - Mobility assets and fleets (admin module)
--   - Connectors and asset-connector links (admin module)
--   - Audit trail for admin actions
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------
-- ORGANIZATIONS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    country TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- USERS  (admin | operator | viewer | analyst)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'operator', 'viewer', 'analyst')),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    is_active BOOLEAN DEFAULT true,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Allow extending an old schema where role only had ('admin','analyst').
DO $$
BEGIN
    BEGIN
        ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
        ALTER TABLE users ADD CONSTRAINT users_role_check
            CHECK (role IN ('admin', 'operator', 'viewer', 'analyst'));
    EXCEPTION WHEN others THEN
        NULL;
    END;
END $$;

CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS auth_audit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    ip_address INET,
    user_agent TEXT,
    success BOOLEAN DEFAULT true,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- FLEETS  (logical grouping of mobility assets)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fleets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (name, org_id)
);

-- ---------------------------------------------------------------------
-- MOBILITY ASSETS  (cars, buses, trucks, drones, AAM, aviation, rail,
--                   transit, marine, EV chargers, sensors, depots, etc.)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS mobility_assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_identifier TEXT NOT NULL,
    asset_name TEXT NOT NULL,
    asset_type TEXT NOT NULL CHECK (asset_type IN (
        'car', 'bus', 'truck', 'drone', 'aam', 'aviation',
        'rail', 'transit', 'marine', 'ev_charger', 'sensor',
        'gateway', 'depot', 'vertiport', 'other'
    )),
    fleet_id UUID REFERENCES fleets(id) ON DELETE SET NULL,
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'maintenance', 'decommissioned')),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (asset_identifier, org_id)
);

-- ---------------------------------------------------------------------
-- CONNECTORS  (data sources that ingest events about assets)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS connectors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    connector_type TEXT NOT NULL,
    description TEXT,
    is_enabled BOOLEAN DEFAULT true,
    config JSONB DEFAULT '{}'::jsonb,
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (name, org_id)
);

-- ---------------------------------------------------------------------
-- ASSET <-> CONNECTOR LINKS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS asset_connector_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES mobility_assets(id) ON DELETE CASCADE,
    connector_id UUID NOT NULL REFERENCES connectors(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT true,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (asset_id, connector_id)
);

-- ---------------------------------------------------------------------
-- ADMIN AUDIT  (track admin actions: user/asset/link changes)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_audit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- INDEXES
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_org_id ON users(org_id);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_user_sessions_token_hash ON user_sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON user_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_auth_audit_user_id ON auth_audit(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_audit_created_at ON auth_audit(created_at);

CREATE INDEX IF NOT EXISTS idx_fleets_org ON fleets(org_id);
CREATE INDEX IF NOT EXISTS idx_assets_fleet ON mobility_assets(fleet_id);
CREATE INDEX IF NOT EXISTS idx_assets_org ON mobility_assets(org_id);
CREATE INDEX IF NOT EXISTS idx_assets_type ON mobility_assets(asset_type);
CREATE INDEX IF NOT EXISTS idx_assets_status ON mobility_assets(status);
CREATE INDEX IF NOT EXISTS idx_connectors_org ON connectors(org_id);
CREATE INDEX IF NOT EXISTS idx_connectors_type ON connectors(connector_type);
CREATE INDEX IF NOT EXISTS idx_link_asset ON asset_connector_links(asset_id);
CREATE INDEX IF NOT EXISTS idx_link_connector ON asset_connector_links(connector_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_actor ON admin_audit(actor_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit(created_at);

-- ---------------------------------------------------------------------
-- UPDATED_AT TRIGGER FUNCTION
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_organizations_updated_at') THEN
        CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON organizations
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_users_updated_at') THEN
        CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_fleets_updated_at') THEN
        CREATE TRIGGER update_fleets_updated_at BEFORE UPDATE ON fleets
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_assets_updated_at') THEN
        CREATE TRIGGER update_assets_updated_at BEFORE UPDATE ON mobility_assets
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_connectors_updated_at') THEN
        CREATE TRIGGER update_connectors_updated_at BEFORE UPDATE ON connectors
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_links_updated_at') THEN
        CREATE TRIGGER update_links_updated_at BEFORE UPDATE ON asset_connector_links
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- SEED DATA  (idempotent)
-- ---------------------------------------------------------------------
INSERT INTO organizations (id, name, country) VALUES
    ('550e8400-e29b-41d4-a716-446655440000', 'VFSOC', 'Canada'),
    ('550e8400-e29b-41d4-a716-446655440001', 'Guest', 'Global')
ON CONFLICT (name) DO NOTHING;

-- Default users (passwords: admin@123, analyst@123)
INSERT INTO users (id, username, email, password_hash, role, org_id) VALUES
    ('660e8400-e29b-41d4-a716-446655440000', 'admin', 'admin@vfsoc.com',
     '$2b$12$1qLWaXpmPGJqmK6A5dqcZe5mmQkBStEzuNcw6xzgssPrNQoR4Cgaq',
     'admin', '550e8400-e29b-41d4-a716-446655440000'),
    ('660e8400-e29b-41d4-a716-446655440001', 'analyst', 'analyst@vfsoc.com',
     '$2b$12$wj5AC1p44ZK6YsC2KWribuz74fYlscT07NE4xsGp8S.YSSMsmidXu',
     'analyst', '550e8400-e29b-41d4-a716-446655440000'),
    ('660e8400-e29b-41d4-a716-446655440004', 'operator', 'operator@vfsoc.com',
     '$2b$12$wj5AC1p44ZK6YsC2KWribuz74fYlscT07NE4xsGp8S.YSSMsmidXu',
     'operator', '550e8400-e29b-41d4-a716-446655440000'),
    ('660e8400-e29b-41d4-a716-446655440005', 'viewer', 'viewer@vfsoc.com',
     '$2b$12$wj5AC1p44ZK6YsC2KWribuz74fYlscT07NE4xsGp8S.YSSMsmidXu',
     'viewer', '550e8400-e29b-41d4-a716-446655440000')
ON CONFLICT (username) DO NOTHING;

-- Seed canonical 9 connectors. These names/types are the single source of
-- truth used everywhere (VFSOC_Admin, VFSOC-SIEM, VFSOC-Ingestion,
-- VFSOC-ML-Models, and the asset_connector_links demo seed). On conflict
-- we update the type/description so re-running this schema corrects any
-- drift from prior installs.
INSERT INTO connectors (name, connector_type, description, org_id) VALUES
    ('AWS CloudWatch', 'aws_cloudwatch',
     'AWS CloudWatch, CloudTrail, and VPC flow log source for cloud assets',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Vehicle Telematics', 'vehicle_telematics',
     'Connected vehicle telematics, GPS, CAN bus, and TCU events',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Tesla ADAS', 'tesla_adas',
     'Tesla Autopilot / FSD advanced driver assistance telemetry',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('EV Charging Station', 'ev_charging_station',
     'OCPP charging session, payment and authentication events',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Vertiports Management', 'vertiports',
     'Vertiport / drone / VTOL operations, flight plans and pad control',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Endpoint Detection', 'endpoint_detection',
     'EDR + MDM signals from fleet laptops, tablets, mobile devices',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('In-Vehicle Payment', 'in_vehicle_payment',
     'In-vehicle and charger payment processing events',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Physical Security', 'physical_security',
     'Depot gates, biometric access, perimeter cameras and badge readers',
     '550e8400-e29b-41d4-a716-446655440000'),
    ('Roadside Sensor', 'roadside_sensor',
     'Roadside units, V2X, traffic and environmental sensors',
     '550e8400-e29b-41d4-a716-446655440000')
ON CONFLICT (name, org_id) DO UPDATE
    SET connector_type = EXCLUDED.connector_type,
        description    = EXCLUDED.description;
