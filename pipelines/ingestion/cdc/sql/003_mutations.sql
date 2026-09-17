INSERT INTO claims (claim_id, claim_number, policy_id, customer_id, claim_status, incident_date, submitted_at, claim_amount, approved_amount, currency_code, description, updated_at)
VALUES ('clm_7003', 'SYN-CLM-7003', 'pol_6003', 'cus_4003', 'SUBMITTED', '2026-09-05', '2026-09-06T10:00:00Z', 300.00, NULL, 'AUD', 'Synthetic inserted claim', '2026-09-06T10:00:00Z');

UPDATE claims
SET claim_status = 'APPROVED', approved_amount = 450.00, updated_at = '2026-09-07T10:00:00Z'
WHERE claim_id = 'clm_7001';

DELETE FROM payments WHERE payment_id = 'pay_8001';
