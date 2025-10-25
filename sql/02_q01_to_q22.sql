-- =========================================================
-- Credit Union Growth Analytics
-- 02_q01_to_q22.sql
-- Exports for Q01–Q22 (CSV files into outputs/answers/)
-- =========================================================

SET schema 'cu';

-- Make sure the path variables exist (same as file 01)
SET VARIABLE project_dir = '.';
SET VARIABLE out_dir     = concat($project_dir, '/outputs/answers');

-- NOTE: ensure the folder outputs/answers already exists.

-- Smoke test (will overwrite if present)
COPY (SELECT 'ok' AS status)
TO concat($out_dir, '/smoketest.csv') (HEADER, DELIMITER ',');

-- Q1: sanity row counts
COPY (
  WITH x AS (
    SELECT 'members'        AS tbl, COUNT(*) FROM v_members_raw       UNION ALL
    SELECT 'accounts'       AS tbl, COUNT(*) FROM v_accounts_raw      UNION ALL
    SELECT 'transactions'   AS tbl, COUNT(*) FROM v_transactions_raw  UNION ALL
    SELECT 'campaigns'      AS tbl, COUNT(*) FROM v_campaigns_raw     UNION ALL
    SELECT 'campaign_touch' AS tbl, COUNT(*) FROM v_campaign_touch_raw UNION ALL
    SELECT 'member_events'  AS tbl, COUNT(*) FROM v_member_events_raw
  )
  SELECT * FROM x
) TO concat($out_dir, '/q01_sanity_counts.csv') (HEADER, DELIMITER ',');

-- Q2: campaign funnel
COPY (
  SELECT * FROM v_campaign_effectiveness ORDER BY conv_rate_pct DESC
) TO concat($out_dir, '/q02_campaign_funnel.csv') (HEADER, DELIMITER ',');

-- Q3: CPA by campaign
COPY (
  SELECT
    c.campaign_id, c.campaign_name, c.channel, c.budget,
    SUM(t.conversion_flag) AS conversions,
    ROUND(c.budget / NULLIF(SUM(t.conversion_flag),0), 2) AS cpa
  FROM v_campaigns_raw c
  LEFT JOIN v_campaign_touch_raw t USING (campaign_id)
  GROUP BY 1,2,3,4
  ORDER BY cpa NULLS LAST
) TO concat($out_dir, '/q03_cpa_by_campaign.csv') (HEADER, DELIMITER ',');

-- Q4: campaign ROI proxy (deposit lift vs budget)
COPY (
  WITH touches AS (
    SELECT member_id, campaign_id, MIN(touch_date)::date AS first_touch_dt
    FROM v_campaign_touch_raw GROUP BY 1,2
  ),
  tx AS (
    SELECT a.member_id, t.txn_date::date AS d, t.amount
    FROM v_transactions_raw t JOIN v_accounts_raw a USING (account_id)
  ),
  before_after AS (
    SELECT
      tou.campaign_id,
      SUM(CASE WHEN tx.d BETWEEN tou.first_touch_dt - 30 AND tou.first_touch_dt - 1 THEN tx.amount ELSE 0 END) AS deposits_before,
      SUM(CASE WHEN tx.d BETWEEN tou.first_touch_dt AND tou.first_touch_dt + 30 THEN tx.amount ELSE 0 END) AS deposits_after
    FROM touches tou LEFT JOIN tx ON tx.member_id = tou.member_id
    GROUP BY 1
  )
  SELECT
    c.campaign_id, c.campaign_name, c.channel, c.budget,
    deposits_after - deposits_before AS deposit_lift,
    ROUND((deposits_after - deposits_before - c.budget) / NULLIF(c.budget,0), 2) AS roi
  FROM before_after ba JOIN v_campaigns_raw c USING (campaign_id)
  ORDER BY roi DESC NULLS LAST
) TO concat($out_dir, '/q04_campaign_roi.csv') (HEADER, DELIMITER ',');

-- Q5a: Top 5 by CPA (lowest)
COPY (
  SELECT * FROM read_csv_auto(concat($out_dir, '/q03_cpa_by_campaign.csv'), header=true)
  ORDER BY cpa NULLS LAST, conversions DESC
  LIMIT 5
) TO concat($out_dir, '/q05a_top5_by_cpa.csv') (HEADER, DELIMITER ',');

-- Q5b: Top 5 by ROI
COPY (
  SELECT * FROM read_csv_auto(concat($out_dir, '/q04_campaign_roi.csv'), header=true)
  ORDER BY roi DESC NULLS LAST
  LIMIT 5
) TO concat($out_dir, '/q05b_top5_by_roi.csv') (HEADER, DELIMITER ',');

-- Q5c: Bottom 5 by ROI
COPY (
  SELECT * FROM read_csv_auto(concat($out_dir, '/q04_campaign_roi.csv'), header=true)
  WHERE roi IS NOT NULL
  ORDER BY roi ASC
  LIMIT 5
) TO concat($out_dir, '/q05c_bottom5_by_roi.csv') (HEADER, DELIMITER ',');

-- Q6: median days first touch → first funded account
COPY (
  WITH first_touch AS (
    SELECT member_id, MIN(touch_date)::date AS first_touch_dt
    FROM v_campaign_touch_raw GROUP BY 1
  ),
  first_fund AS (
    SELECT member_id, MIN(open_date)::date AS first_acct_dt
    FROM v_accounts_raw WHERE funded_flag=1 GROUP BY 1
  )
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (first_acct_dt - first_touch_dt)) AS median_days_to_fund
  FROM first_touch ft JOIN first_fund fa USING (member_id)
  WHERE (fa.first_acct_dt - ft.first_touch_dt) >= 0
) TO concat($out_dir, '/q06_median_days_to_fund.csv') (HEADER, DELIMITER ',');

-- Q7: Monthly Active Members (MAM) & activity rate
COPY (
  WITH active AS (
    SELECT date_trunc('month', month)::date AS mth, COUNT(DISTINCT member_id) AS active_members
    FROM v_member_activity_monthly GROUP BY 1
  ),
  base AS (
    SELECT date_trunc('month', join_date)::date AS mth, COUNT(*) AS joiners
    FROM v_member_base GROUP BY 1
  ),
  pop AS (
    SELECT mth,
           SUM(joiners) OVER (ORDER BY mth ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS est_population
    FROM base
  )
  SELECT a.mth, a.active_members, p.est_population,
         ROUND(100.0*a.active_members / NULLIF(p.est_population,0),2) AS activity_rate_pct
  FROM active a JOIN pop p USING (mth)
  ORDER BY a.mth
) TO concat($out_dir, '/q07_mam_activity_rate.csv') (HEADER, DELIMITER ',');

-- Q8: Engagement score tiers by segment
COPY (
  WITH s AS (
    SELECT
      m.member_id,
      COALESCE(SUM(ma.monthly_txn_count),0)   AS txns,
      COALESCE(SUM(ma.monthly_event_count),0) AS evts
    FROM v_member_base m
    LEFT JOIN v_member_activity_monthly ma USING (member_id)
    GROUP BY 1
  ),
  scores AS (
    SELECT
      m.member_id, m.age_band, m.channel_signup,
      (txns + 0.5*evts) AS eng_raw
    FROM s JOIN v_member_base m USING (member_id)
  ),
  ranks AS (
    SELECT *,
      NTILE(4) OVER (ORDER BY eng_raw) AS quartile
    FROM scores
  )
  SELECT age_band, channel_signup, quartile, COUNT(*) AS members
  FROM ranks GROUP BY 1,2,3 ORDER BY 1,2,3
) TO concat($out_dir, '/q08_engagement_tiers_by_segment.csv') (HEADER, DELIMITER ',');

-- Q9: Churn rate by age_band & signup channel
COPY (
  SELECT age_band, channel_signup,
         ROUND(100.0*AVG(churn_flag),2) AS churn_rate_pct,
         COUNT(*) AS members
  FROM v_member_base GROUP BY 1,2 ORDER BY 3 DESC
) TO concat($out_dir, '/q09_churn_rate_by_segment.csv') (HEADER, DELIMITER ',');

-- Q10: Deposit growth MoM by channel (FIXED)
COPY (
  WITH d AS (
    SELECT
      mb.channel_signup,
      date_trunc('month', ma.month)::date AS mth,
      SUM(ma.deposits_month) AS deposits
    FROM v_member_activity_monthly ma
    JOIN v_member_base mb USING (member_id)
    GROUP BY 1,2
  )
  SELECT
    channel_signup,
    mth,
    deposits,
    deposits - LAG(deposits) OVER (PARTITION BY channel_signup ORDER BY mth) AS mom_change
  FROM d
  ORDER BY channel_signup, mth
) TO concat($out_dir, '/q10_deposit_growth_mom_by_channel.csv') (HEADER, DELIMITER ',');

-- Q11: New members by signup channel (per month)
COPY (
  SELECT channel_signup, date_trunc('month', join_date)::date AS mth, COUNT(*) AS new_members
  FROM v_member_base GROUP BY 1,2 ORDER BY 2,1
) TO concat($out_dir, '/q11_new_members_by_channel.csv') (HEADER, DELIMITER ',');

-- Q12: Funding rate by campaign
COPY (
  WITH touched AS (
    SELECT DISTINCT member_id, campaign_id FROM v_campaign_touch_raw
  ),
  funded AS (
    SELECT DISTINCT member_id FROM v_accounts_raw WHERE funded_flag=1
  )
  SELECT c.campaign_id, c.campaign_name, c.channel,
         COUNT(t.member_id) AS touched_members,
         SUM(CASE WHEN f.member_id IS NOT NULL THEN 1 ELSE 0 END) AS funded_members,
         ROUND(100.0*SUM(CASE WHEN f.member_id IS NOT NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(t.member_id),0),2) AS funding_rate_pct
  FROM touched t
  JOIN v_campaigns_raw c USING (campaign_id)
  LEFT JOIN funded f ON f.member_id = t.member_id
  GROUP BY 1,2,3
  ORDER BY funding_rate_pct DESC NULLS LAST
) TO concat($out_dir, '/q12_funding_rate_by_campaign.csv') (HEADER, DELIMITER ',');

-- Q13: Dormant members (no transactions in last 60 days)
COPY (
  WITH last_tx AS (
    SELECT a.member_id, MAX(t.txn_date)::date AS last_txn_dt
    FROM v_transactions_raw t JOIN v_accounts_raw a USING (account_id)
    GROUP BY 1
  )
  SELECT m.member_id, m.age_band, m.channel_signup, lt.last_txn_dt
  FROM v_member_base m
  LEFT JOIN last_tx lt ON lt.member_id=m.member_id
  WHERE lt.last_txn_dt IS NULL OR DATEDIFF('day', lt.last_txn_dt, CURRENT_DATE) > 60
) TO concat($out_dir, '/q13_dormant_members.csv') (HEADER, DELIMITER ',');

-- Q14: Cross-sell (checking-only)
COPY (
  SELECT member_id, accounts_count, n_checking, n_savings, n_credit_card, n_loan, n_cd
  FROM v_account_summary
  WHERE accounts_count=1 AND n_checking=1
) TO concat($out_dir, '/q14_cross_sell_checking_only.csv') (HEADER, DELIMITER ',');

-- Q15: Avg monthly engagement by age_band
COPY (
  WITH s AS (
    SELECT mb.age_band,
           AVG(ma.monthly_txn_count)   AS avg_txn,
           AVG(ma.monthly_event_count) AS avg_evt
    FROM v_member_activity_monthly ma
    JOIN v_member_base mb USING (member_id)
    GROUP BY 1
  )
  SELECT age_band, avg_txn, avg_evt, (avg_txn + 0.5*avg_evt) AS engagement_score
  FROM s ORDER BY engagement_score DESC
) TO concat($out_dir, '/q15_avg_monthly_engagement_by_age.csv') (HEADER, DELIMITER ',');

-- Q16: First-touch channel conversion
COPY (
  WITH ft AS (
    SELECT member_id,
           MIN(touch_date)::date AS first_touch_dt,
           ANY_VALUE(c.channel)  AS channel
    FROM v_campaign_touch_raw t
    JOIN v_campaigns_raw c USING (campaign_id)
    GROUP BY 1
  ),
  funded AS (
    SELECT DISTINCT member_id FROM v_accounts_raw WHERE funded_flag=1
  )
  SELECT channel,
         COUNT(*) AS touched,
         SUM(CASE WHEN f.member_id IS NOT NULL THEN 1 ELSE 0 END) AS funded,
         ROUND(100.0*SUM(CASE WHEN f.member_id IS NOT NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),2) AS conv_rate_pct
  FROM ft LEFT JOIN funded f USING (member_id)
  GROUP BY 1 ORDER BY conv_rate_pct DESC NULLS LAST
) TO concat($out_dir, '/q16_first_touch_channel_conversion.csv') (HEADER, DELIMITER ',');

-- Q17: Retention lift (touched vs not touched)
COPY (
  WITH touched AS (SELECT DISTINCT member_id FROM v_campaign_touch_raw),
  churn AS (SELECT member_id, churn_flag FROM v_member_base)
  SELECT
    CASE WHEN t.member_id IS NOT NULL THEN 'touched' ELSE 'not_touched' END AS grp,
    ROUND(100.0*AVG(1 - churn_flag),2) AS retention_pct,
    COUNT(*) AS members
  FROM churn c LEFT JOIN touched t USING (member_id)
  GROUP BY 1 ORDER BY retention_pct DESC
) TO concat($out_dir, '/q17_retention_lift_campaign_touched.csv') (HEADER, DELIMITER ',');

-- Q18: Top-20% members share of total deposits
COPY (
  WITH dep AS (
    SELECT a.member_id, SUM(CASE WHEN t.txn_type='deposit' THEN t.amount ELSE 0 END) AS deposits
    FROM v_transactions_raw t JOIN v_accounts_raw a USING (account_id)
    GROUP BY 1
  ),
  ranked AS (
    SELECT *,
      RANK() OVER (ORDER BY deposits DESC) AS rk,
      COUNT(*) OVER () AS n,
      SUM(deposits) OVER () AS total_dep
    FROM dep
  )
  SELECT
    ROUND(100.0*SUM(CASE WHEN rk <= 0.2*n THEN deposits ELSE 0 END)/NULLIF(MAX(total_dep),0),2) AS top20pct_share_pct
  FROM ranked
) TO concat($out_dir, '/q18_top20pct_share_of_deposits.csv') (HEADER, DELIMITER ',');

-- Q19: Spanish-preference — touch & fund %
COPY (
  WITH touched AS (SELECT DISTINCT member_id FROM v_campaign_touch_raw),
  funded  AS (SELECT DISTINCT member_id FROM v_accounts_raw WHERE funded_flag=1)
  SELECT
    is_spanish,
    COUNT(*) AS members,
    ROUND(100.0*AVG(CASE WHEN t.member_id IS NOT NULL THEN 1 ELSE 0 END),2) AS touched_pct,
    ROUND(100.0*AVG(CASE WHEN f.member_id IS NOT NULL THEN 1 ELSE 0 END),2) AS funded_pct
  FROM v_member_base m
  LEFT JOIN touched t USING (member_id)
  LEFT JOIN funded  f USING (member_id)
  GROUP BY 1 ORDER BY 1 DESC
) TO concat($out_dir, '/q19_spanish_pref_touch_and_fund.csv') (HEADER, DELIMITER ',');

-- Q20: Zip3 deposits & conversions
COPY (
  WITH dep AS (
    SELECT mb.zip3, SUM(CASE WHEN t.txn_type='deposit' THEN t.amount ELSE 0 END) AS deposits
    FROM v_transactions_raw t
    JOIN v_accounts_raw a USING (account_id)
    JOIN v_member_base mb USING (member_id)
    GROUP BY 1
  ),
  conv AS (
    SELECT mb.zip3, SUM(ct.conversion_flag) AS conversions
    FROM v_campaign_touch_raw ct
    JOIN v_member_base mb USING (member_id)
    GROUP BY 1
  )
  SELECT d.zip3, d.deposits, c.conversions
  FROM dep d LEFT JOIN conv c USING (zip3)
  ORDER BY d.deposits DESC
) TO concat($out_dir, '/q20_zip_deposits_and_conv.csv') (HEADER, DELIMITER ',');

-- Q21: Correlation — tenure vs activity
COPY (
  WITH agg AS (
    SELECT
      m.member_id, a.tenure_months,
      COALESCE(SUM(ma.monthly_txn_count),0)   AS txns,
      COALESCE(SUM(ma.monthly_event_count),0) AS evts
    FROM v_member_360 a
    JOIN v_member_base m USING (member_id)
    LEFT JOIN v_member_activity_monthly ma USING (member_id)
    GROUP BY 1,2
  )
  SELECT
    CORR(tenure_months, txns) AS corr_tenure_txns,
    CORR(tenure_months, evts) AS corr_tenure_events
  FROM agg
) TO concat($out_dir, '/q21_tenure_activity_correlation.csv') (HEADER, DELIMITER ',');

-- Q22: Next-best campaign targets (rules-based)
COPY (
  WITH base AS (
    SELECT
      m.member_id,
      m.join_date,
      m.age,
      m.language_pref,
      m.zipcode,
      m.channel_signup,
      m.churn_flag,
      DATEDIFF('month', m.join_date, CURRENT_DATE) AS tenure_months
    FROM v_members_raw m
  ),
  activity AS (
    SELECT
      b.member_id,
      COALESCE(SUM(CASE WHEN t.txn_type='deposit' AND t.txn_date >= CURRENT_DATE - 90 THEN t.amount ELSE 0 END),0) AS dep_90d,
      COALESCE(SUM(CASE WHEN e.event_date >= CURRENT_DATE - 90 THEN 1 ELSE 0 END),0) AS events_90d
    FROM base b
    LEFT JOIN v_accounts_raw a ON a.member_id=b.member_id
    LEFT JOIN v_transactions_raw t ON t.account_id=a.account_id
    LEFT JOIN v_member_events_raw e ON e.member_id=b.member_id
    GROUP BY 1
  ),
  last_touch AS (
    SELECT
      ct.member_id,
      MAX(ct.touch_date)::date AS last_touch_dt,
      MAX(ct.conversion_flag) AS ever_converted
    FROM v_campaign_touch_raw ct
    GROUP BY 1
  ),
  scored AS (
    SELECT
      b.*,
      a.dep_90d,
      a.events_90d,
      lt.last_touch_dt,
      COALESCE(lt.ever_converted,0) AS ever_converted,
      (a.events_90d*2 + a.dep_90d*0.001 + LEAST(12,tenure_months)*0.5) AS lead_score
    FROM base b
    LEFT JOIN activity a USING (member_id)
    LEFT JOIN last_touch lt USING (member_id)
    WHERE b.churn_flag=0
  ),
  hot_zip AS (
    SELECT
      m.zipcode
    FROM v_accounts_raw a
    JOIN v_members_raw m USING (member_id)
    JOIN v_transactions_raw t USING (account_id)
    WHERE t.txn_type='deposit'
    GROUP BY 1
    ORDER BY SUM(t.amount) DESC
    LIMIT 15
  ),
  recommend AS (
    SELECT
      s.member_id,
      s.age,
      s.language_pref,
      s.zipcode,
      s.channel_signup,
      s.tenure_months,
      s.dep_90d,
      s.events_90d,
      s.lead_score,
      CASE
        WHEN s.language_pref='Spanish' THEN 'CAMP_ES_WELCOME'
        WHEN s.age BETWEEN 18 AND 25 THEN 'CAMP_GENZ_CHECKING'
        WHEN s.tenure_months < 3 THEN 'CAMP_NEW_MEMBER_ONBOARD'
        WHEN s.zipcode IN (SELECT zipcode FROM hot_zip) THEN 'CAMP_LOCAL_BRANCH_EVENT'
        ELSE 'CAMP_SAVINGS_BOOST'
      END AS next_best_campaign
    FROM scored s
  ),
  ranked AS (
    SELECT
      r.*,
      ROW_NUMBER() OVER (PARTITION BY r.next_best_campaign ORDER BY r.lead_score DESC) AS rn
    FROM recommend r
  )
  SELECT
    member_id, age, language_pref, zipcode, channel_signup,
    tenure_months, dep_90d, events_90d, lead_score,
    next_best_campaign
  FROM ranked
  WHERE rn <= 500
  ORDER BY next_best_campaign, lead_score DESC
) TO concat($out_dir, '/q22_next_best_campaign_targets.csv') (HEADER, DELIMITER ',');

-- Done.
