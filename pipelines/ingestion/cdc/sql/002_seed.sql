INSERT INTO customers (customer_id, first_name, last_name, date_of_birth, email, phone, customer_status, created_at, updated_at)
VALUES
('cus_4001', 'Synthetic', 'CustomerOne', '1985-04-12', 'customer.one@example.invalid', '+610400000001', 'ACTIVE', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'),
('cus_4002', 'Synthetic', 'CustomerTwo', '1990-07-21', 'customer.two@example.invalid', '+610400000002', 'ACTIVE', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'),
('cus_4003', 'Synthetic', 'CustomerThree', '1978-11-03', 'customer.three@example.invalid', '+610400000003', 'ACTIVE', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

INSERT INTO products (product_id, product_code, product_name, product_type, product_status, effective_from, created_at, updated_at)
VALUES
('prd_5001', 'HOME-BASIC', 'Synthetic Home Basic', 'HOME', 'ACTIVE', '2026-01-01', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'),
('prd_5002', 'AUTO-PLUS', 'Synthetic Auto Plus', 'AUTO', 'ACTIVE', '2026-01-01', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

INSERT INTO policies (policy_id, policy_number, customer_id, product_id, policy_status, start_date, end_date, premium_amount, currency_code, created_at, updated_at)
VALUES
('pol_6001', 'SYN-POL-6001', 'cus_4001', 'prd_5001', 'ACTIVE', '2026-01-01', '2027-01-01', 1200.00, 'AUD', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'),
('pol_6002', 'SYN-POL-6002', 'cus_4002', 'prd_5002', 'ACTIVE', '2026-01-01', '2027-01-01', 900.00, 'AUD', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'),
('pol_6003', 'SYN-POL-6003', 'cus_4003', 'prd_5001', 'ACTIVE', '2026-01-01', '2027-01-01', 1100.00, 'AUD', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

INSERT INTO claims (claim_id, claim_number, policy_id, customer_id, claim_status, incident_date, submitted_at, claim_amount, approved_amount, currency_code, description, updated_at)
VALUES
('clm_7001', 'SYN-CLM-7001', 'pol_6001', 'cus_4001', 'SUBMITTED', '2026-09-02', '2026-09-03T10:00:00Z', 500.00, NULL, 'AUD', 'Synthetic claim fixture one', '2026-09-03T10:00:00Z'),
('clm_7002', 'SYN-CLM-7002', 'pol_6002', 'cus_4002', 'UNDER_REVIEW', '2026-09-03', '2026-09-04T10:00:00Z', 750.00, NULL, 'AUD', 'Synthetic claim fixture two', '2026-09-04T10:00:00Z');

INSERT INTO payments (payment_id, claim_id, policy_id, payment_type, payment_status, payment_amount, currency_code, payment_timestamp, provider_reference, created_at, updated_at)
VALUES
('pay_8001', 'clm_7001', 'pol_6001', 'PREMIUM', 'SUCCEEDED', 100.00, 'AUD', '2026-09-03T12:00:00Z', 'synthetic-ref-8001', '2026-09-03T12:00:00Z', '2026-09-03T12:00:00Z');
