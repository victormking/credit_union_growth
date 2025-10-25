# 🧠 Q23 — Insights & Recommendations  
_This analysis builds on the 22-question Credit Union Growth pipeline (DuckDB + SQL), transforming outputs into business recommendations._

---

## 🎯 Project Context
The Credit Union Growth Analytics project integrates six raw datasets (members, accounts, transactions, campaigns, campaign_touches, and member_events) into nine engineered SQL views and twenty-two analytical outputs.  

All insights were derived through **SQL-based analysis in DuckDB**, ensuring a reproducible and auditable workflow across acquisition, engagement, and retention dimensions.

---

## 1️⃣ Acquisition & Campaign Performance
**Source Queries:** Q02–Q06 (campaign funnel, CPA, ROI, median funding time)

- Average **conversion rate** from campaign touch → funded account: **5–8 %**  
- Median **days to fund** after first touch: **≈ 12 days**  
- **Top 25 % campaigns** returned **ROI > 2×**, bottom quartile under **0.8×**
- **Cost per Acquisition (CPA)** ranged from **$80–$140**, heavily dependent on channel mix
- Email and referral channels demonstrated the **strongest efficiency**; social ads delivered reach but low conversion.

📈 *Recommendation:* Reallocate 20 – 25 % of digital budget from low-ROI social to high-ROI email + referral funnels.

---

## 2️⃣ Engagement & Retention
**Source Queries:** Q07–Q09, Q17  

- Members with ≥ 1 app login per month had **~40 % lower churn**.  
- **Digital onboarding** correlates with **17-point higher retention** (51 % vs 34 %).  
- Older segments (45+) show sustained activity; Gen Z members drop off after month 6.  
- High-activity months correspond to spikes in new campaign launches.

📈 *Recommendation:*  
Implement “digital re-onboarding” triggers after 45 days of inactivity and reward early mobile engagement.

---

## 3️⃣ Product & Behavioral Insights
**Source Queries:** Q14–Q15, Q21  

- 37 % of members hold **checking-only accounts** — strong cross-sell potential.  
- **Average monthly events** increase 28 % when a savings account is added.  
- Engagement declines slightly with tenure (**r = –0.25**) suggesting lifecycle fatigue.  
- New members with savings + checking combos have 22 % higher deposit growth.

📈 *Recommendation:*  
Design **“Activate & Save”** journeys that introduce savings products in month 2–3 of tenure.

---

## 4️⃣ Member Value & Segmentation
**Source Queries:** Q18–Q22  

- Top 20 % of members generate **≈ 72 % of total deposits** (Pareto effect).  
- Spanish-preferring members show equal deposit volume but lower marketing touch rates (–30 %).  
- ZIP3 analysis highlights three regional clusters driving most conversions.  
- The **Next-Best-Campaign Model** (Q22) assigns a simple lead score combining tenure, recent deposits, and activity.  
- Example: Spanish-speaking Gen Z members with low deposits + recent events were routed to `CAMP_ES_WELCOME` for personalized outreach.

📈 *Recommendation:*  
Deploy this **lead-scoring logic** into CRM (Salesforce/Marketo) to automate “next-best-action” targeting.

---

## 5️⃣ Strategic Growth Opportunities

| Focus Area | Opportunity | Recommended Action |
|-------------|--------------|--------------------|
| **Campaign Efficiency** | 20 % budget reallocation from low-ROI channels | Prioritize email + referral |
| **Member Retention** | Early-stage drop-off in Gen Z | Launch mobile engagement streaks |
| **Cross-Sell Growth** | Checking-only members | Auto-trigger savings offer |
| **Regional Marketing** | Three high-performing ZIP clusters | Geo-target branch events |
| **Marketing Data Mart** | Reusable SQL views (`v_member_360`) | Deploy to BI environment |

---

## 🧭 Executive Summary

Together, these insights define a **data-driven roadmap for sustainable member growth**:

1. **Acquire efficiently** — shift investment toward high-ROI channels.  
2. **Engage early** — mobile and onboarding engagement predicts retention.  
3. **Retain actively** — re-engage lapsed members via digital prompts.  
4. **Expand smartly** — automate cross-sell and local targeting using CRM intelligence.

> These findings provide a blueprint for optimizing acquisition, deepening engagement, and maximizing lifetime value through data-driven decision-making.

---

## ✅ Deliverable Checkpoints
- 22 SQL outputs validated in DuckDB.  
- All results exported as auditable CSVs under `/outputs/answers/`.  
- Views stored under `/outputs/views/` for BI integration.  
- Reproducible via `sql/01_setup_and_views.sql` + `sql/02_q01_to_q22.sql`.

---
