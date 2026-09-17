CREATE TABLE IF NOT EXISTS customers (
    customer_id VARCHAR(64) PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(32),
    customer_status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
    product_id VARCHAR(64) PRIMARY KEY,
    product_code VARCHAR(64) NOT NULL UNIQUE,
    product_name VARCHAR(255) NOT NULL,
    product_type VARCHAR(64) NOT NULL,
    product_status VARCHAR(16) NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS policies (
    policy_id VARCHAR(64) PRIMARY KEY,
    policy_number VARCHAR(64) NOT NULL UNIQUE,
    customer_id VARCHAR(64) NOT NULL REFERENCES customers(customer_id),
    product_id VARCHAR(64) NOT NULL REFERENCES products(product_id),
    policy_status VARCHAR(16) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    premium_amount NUMERIC(18,2) NOT NULL CHECK (premium_amount >= 0),
    currency_code CHAR(3) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CHECK (start_date < end_date)
);

CREATE TABLE IF NOT EXISTS claims (
    claim_id VARCHAR(64) PRIMARY KEY,
    claim_number VARCHAR(64) NOT NULL UNIQUE,
    policy_id VARCHAR(64) NOT NULL REFERENCES policies(policy_id),
    customer_id VARCHAR(64) NOT NULL REFERENCES customers(customer_id),
    claim_status VARCHAR(16) NOT NULL,
    incident_date DATE NOT NULL,
    submitted_at TIMESTAMPTZ NOT NULL,
    claim_amount NUMERIC(18,2) NOT NULL CHECK (claim_amount >= 0),
    approved_amount NUMERIC(18,2) CHECK (approved_amount IS NULL OR approved_amount >= 0),
    currency_code CHAR(3) NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL,
    CHECK (incident_date <= submitted_at::date),
    CHECK (updated_at >= submitted_at)
);

CREATE TABLE IF NOT EXISTS payments (
    payment_id VARCHAR(64) PRIMARY KEY,
    claim_id VARCHAR(64) REFERENCES claims(claim_id),
    policy_id VARCHAR(64) NOT NULL REFERENCES policies(policy_id),
    payment_type VARCHAR(32) NOT NULL,
    payment_status VARCHAR(16) NOT NULL,
    payment_amount NUMERIC(18,2) NOT NULL CHECK (payment_amount >= 0),
    currency_code CHAR(3) NOT NULL,
    payment_timestamp TIMESTAMPTZ NOT NULL,
    provider_reference VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
