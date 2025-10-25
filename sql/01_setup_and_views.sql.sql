-- =========================================================
-- Credit Union Growth Analytics
-- 01_setup_and_views.sql
-- Idempotent build of schemas + raw views + engineered views
-- =========================================================

-- 0) Schema
CREATE SCHEMA IF NOT EXISTS cu;
SET schema 'cu';

-- 1) Project dirs (relative; run from project root)
-- If you prefer absolute paths, change '.' to your full folder.
SET VARIABLE project_dir = '.';
SET VARIABLE data_dir    = concat($project_dir, '/data');
SET VARIABLE out_dir     = concat($project_dir, '/outputs/answers');

-- 2) Raw CSV views (6)
CREATE OR REPLACE VIEW v_members_raw AS
SELECT * FROM read_csv_auto(concat($data_dir, '/members.csv'), header=true);

CREATE OR REPLACE VIEW v_accounts_raw AS
SELECT * FROM read_csv_auto(concat($data_dir, '/accounts.csv'), header=true);

CREATE OR REPLACE VIEW v_transactions_raw AS
SELECT * FROM read_csv_auto(concat($data_dir, '/transactions.csv'), header=true);

CREATE OR REPLACE VIEW v_campaigns_raw AS
SELECT * FROM read_csv_auto(concat($data_dir, '/campaigns.csv'), header=true);

CREATE OR REPLACE VIEW v_campaign_touch_raw AS
SELECT * FROM read_csv_auto(concat($data_dir, '/campaign_touch.csv'), header=true);

CREATE OR REPLACE VIEW v_member_events_raw AS
SELECT * FROM read_csv_auto(concat($data_dir, '/member_events.csv'), header=true);

-- 3) Helper/engineered views (9)

-- 3.1 Monthly transactions per member
CREATE OR REPLACE VIEW v_transactions_monthly AS
SELECT
  a.member_id,
  date_trunc('month', t.txn_date)::date AS txn_month,
  COUNT(*) AS monthly_txn_count,
  SUM(CASE WHEN t.txn_type='deposit'     THEN t.amount ELSE 0 END)  AS deposits_month,
  SUM(CASE WHEN t.txn_type='withdrawal'  THEN -t.amount ELSE 0 END) AS withdrawals_month,
  SUM(t.amount) AS net_month
FROM v_transactions_raw t
JOIN v_accounts_raw a USING (account_id)
GROUP BY 1,2;

-- 3.2 Monthly digital events per member
CREATE OR REPLACE VIEW v_member_events_monthly AS
SELECT
  member_id,
  date_trunc('month', event_date)::date AS event_month,
  COUNT(*) AS monthly_event_count
FROM v_member_events_raw
GROUP BY 1,2;

-- 3.3 Member base with handy features
CREATE OR REPLACE VIEW v_member_base AS
SELECT
  m.member_id,
  m.join_date::date AS join_date,
  m.age,
  m.gender,
  m.language_pref,
  m.zipcode,
  m.employment_status,
  m.income_bracket,
  m.channel_signup,
  m.churn_flag,
  CASE
    WHEN m.age < 25 THEN 'under_25'
    WHEN m.age BETWEEN 25 AND 34 THEN '25_34'
    WHEN m.age BETWEEN 35 AND 44 THEN '35_44'
    WHEN m.age BETWEEN 45 AND 54 THEN '45_54'
    WHEN m.age BETWEEN 55 AND 64 THEN '55_64'
    ELSE '65_plus'
  END AS age_band,
  (m.zipcode/100)::int AS zip3,
  (LOWER(m.language_pref)='spanish')::int AS is_spanish
FROM v_members_raw m;

-- 3.4 Account summary per member
CREATE OR REPLACE VIEW v_account_summary AS
SELECT
  a.member_id,
  COUNT(*)                                            AS accounts_count,
  COUNT_IF(a.account_type='checking')                 AS n_checking,
  COUNT_IF(a.account_type='savings')                  AS n_savings,
  COUNT_IF(a.account_type='credit_card')              AS n_credit_card,
  COUNT_IF(a.account_type='loan')                     AS n_loan,
  COUNT_IF(a.account_type='cd')                       AS n_cd,
  SUM(a.balance)                                      AS total_balance,
  AVG(a.interest_rate)                                AS avg_interest_rate,
  SUM(CASE WHEN a.funded_flag=1 THEN 1 ELSE 0 END)    AS funded_accounts,
  MIN(a.open_date)::date                              AS first_account_date,
  MAX(a.open_date)::date                              AS last_account_date,
  DATEDIFF('month', MIN(a.open_date), CURRENT_DATE)   AS tenure_months
FROM v_accounts_raw a
GROUP BY 1;

-- 3.5 Campaign effectiveness per campaign
CREATE OR REPLACE VIEW v_campaign_effectiveness AS
SELECT
  c.campaign_id, c.campaign_name, c.channel, c.budget, c.start_date, c.end_date,
  COUNT(*)::int                                         AS touches,
  SUM(opened_email_flag)::int                           AS opens,
  SUM(clicked_flag)::int                                AS clicks,
  SUM(conversion_flag)::int                             AS conversions,
  ROUND(100.0*SUM(opened_email_flag)/NULLIF(COUNT(*),0),2) AS open_rate_pct,
  ROUND(100.0*SUM(clicked_flag)/NULLIF(COUNT(*),0),2)      AS click_rate_pct,
  ROUND(100.0*SUM(conversion_flag)/NULLIF(COUNT(*),0),2)   AS conv_rate_pct
FROM v_campaign_touch_raw t
JOIN v_campaigns_raw c USING (campaign_id)
GROUP BY 1,2,3,4,5,6;

-- 3.6 Unified activity grid by (member, month)
CREATE OR REPLACE VIEW v_member_activity_monthly AS
SELECT
  mb.member_id,
  mth::date AS month,
  COALESCE(tm.monthly_txn_count,0)     AS monthly_txn_count,
  COALESCE(tm.deposits_month,0)        AS deposits_month,
  COALESCE(tm.withdrawals_month,0)     AS withdrawals_month,
  COALESCE(tm.net_month,0)             AS net_month,
  COALESCE(em.monthly_event_count,0)   AS monthly_event_count
FROM (
  SELECT DISTINCT member_id, txn_month AS mth FROM v_transactions_monthly
  UNION
  SELECT DISTINCT member_id, event_month FROM v_member_events_monthly
) d
JOIN v_member_base mb ON mb.member_id = d.member_id
LEFT JOIN v_transactions_monthly tm
  ON tm.member_id = d.member_id AND tm.txn_month = d.mth
LEFT JOIN v_member_events_monthly em
  ON em.member_id = d.member_id AND em.event_month = d.mth;

-- 3.7 Member 360 (base + account summary)
CREATE OR REPLACE VIEW v_member_360 AS
SELECT
  mb.*,
  asu.accounts_count, asu.n_checking, asu.n_savings, asu.n_credit_card, asu.n_loan, asu.n_cd,
  asu.total_balance, asu.avg_interest_rate, asu.funded_accounts,
  asu.first_account_date, asu.last_account_date, asu.tenure_months
FROM v_member_base mb
LEFT JOIN v_account_summary asu USING (member_id);
