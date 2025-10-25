# 💡 CRM + Marketing Automation Simulation

This project doesn’t just analyze data — it mirrors the real architecture of a CRM and Marketing-Automation ecosystem such as Salesforce + Marketo.  
The SQL views and analytical questions reproduce every layer of that workflow: data collection, behavioral tracking, automation logic, and insight reporting.

---

## 🧱 How a CRM System Works

A Customer Relationship Management (CRM) platform is a live database of members or customers that connects to every other system — website, app, transactions, and campaigns.  
Each login, purchase, or email open creates an event record tied to a single `member_id`.  
Automation tools like **Marketo**, **HubSpot**, or **Braze** then listen for those events and trigger actions (emails, texts, lead-score updates) according to business rules.

---

## 🧩 Simulation Mapping in This Project

| Real-World Concept | This Project’s Equivalent |
|--------------------|---------------------------|
| **CRM Database** | `v_member_360` – unified member dataset (demographics + financial + behavioral) |
| **User Behavior Tracking** | `v_member_activity_monthly` and `v_member_events_monthly` – monthly engagement metrics |
| **Marketing Automation Rules** | Q22 *Next Best Campaign Targets* – logic that determines which campaign each member should receive |
| **Lead Scoring** | `lead_score` column combining deposits, events, and tenure |
| **Email Triggers / Personalization** | `CASE WHEN` logic (e.g., “If Spanish → CAMP_ES_WELCOME”) |
| **Campaign ROI Tracking** | Q03–Q05 (CPA, ROI, Lift analysis) |
| **Analytics Reporting** | Tableau / Power BI visualizations (Q24) |

---

## 🧠 Data Flow Diagram

```mermaid
flowchart LR
    A["Member Activity / Events"] --> B["CRM (v_member_360)"]
    B --> C["Automation Logic (Q22)"]
    C --> D["Campaign Email / SMS Delivery"]
    D --> B
    B --> E["Analytics & Dashboards (Q01–Q24)"]
