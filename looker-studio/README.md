# The Looker Studio version

**Live report: https://lookerstudio.google.com/reporting/af1a9c31-0a81-47e9-befe-b813f2ecc85f** (Looker Studio is now called Data Studio; the steps below still apply).

This is how it was built, and how to rebuild it in your own account (about 30 minutes).

Every CSV here is the output of a PostgreSQL view (`scripts/export.py` writes them). Looker Studio is free with a Google account.

| CSV | View | Use it for |
|---|---|---|
| `sales_lines.csv` | `v_sales_lines` | Anything you want to slice: one row per sale line with date, channel, product, category, revenue, cost and profit |
| `monthly_sales.csv` | `v_monthly_sales` | Scorecards and the monthly trend |
| `category_monthly.csv` | `v_category_monthly` | Margin by category over time |
| `product_performance.csv` | `v_product_performance` | ABC table |
| `stock_on_hand.csv` | `v_stock_on_hand` | Stock value |
| `reorder_alerts.csv` | `v_reorder_alerts` | Reorder table |
| `dead_stock.csv` | `v_dead_stock` | Dead stock table |
| `festival_prep.csv` | `v_festival_prep` | Diwali list |
| `gst_monthly.csv` | `v_gst_monthly` | GST summary |
| `gst_hsn_monthly.csv` | `v_gst_hsn_monthly` | HSN summary |

## 1. Add the data sources

1. Open [lookerstudio.google.com](https://lookerstudio.google.com) → **Create → Data source → CSV File Upload**. The first time, Google asks you to authorize Data Studio and its Cloud Storage for uploads.
2. **Create dataset**, upload `sales_lines.csv`, name the source, and click **Connect**.
3. Data Studio reads dates like `2025-10-01` as text, so add a calculated field **Sale day** = `PARSE_DATE("%Y-%m-%d", sale_date)`. Use it for every date dimension, set to *Year Month* on monthly charts.
4. Add a calculated field **Margin %** = `SUM(gross_profit) / SUM(revenue)`, type *Percent*. It stays correct at any grouping, unlike averaging a margin column.
5. Repeat steps 1 and 2 for `reorder_alerts`, `dead_stock`, `festival_prep` and `gst_monthly`, one data source each.

## 2. Build the report

Create the report from the `sales_lines` data source and switch the page to **responsive layout**. Charts you add default to the first data source, so after adding a chart on pages 2 and 3, set its **Data source** in the Setup panel before picking fields.

**Page 1 · Sales & margin**
- Three **scorecards**: SUM(revenue), SUM(gross_profit), Margin %, with compact numbers and **Sale day** as the date range dimension, so the date range control in the header filters them.
- A **stacked column chart**: dimension Sale day (*Year Month*), breakdown `channel`, metric SUM(revenue), sorted by month ascending.
- A **table**: dimension `category`, metrics revenue, gross_profit, Margin %. Power banks stand out at 8%.

**Page 2 · Stock & Diwali**
- A **table** from `reorder_alerts`: product, status, qty, per_day, days_of_cover, lead_time_days, order_qty, order_value. Filter: exclude `status` containing `OK`. Sort by status ascending.
- A **table** from `dead_stock`: product, status, stock_value, qty, days_since_last_sale.
- A **table** from `festival_prep`: order_by, product, supplier, units_last_rush, stock_now, festival_qty, festival_value. Filter: `festival_qty` greater than 0. Sort by order_by ascending.

**Page 3 · GST**
- A **column chart** from `gst_monthly`: dimension `month`, metrics output_tax, itc, cash_payable, 12 bars, sorted by month ascending.
- A **table**: month, taxable_sales, output_tax, itc, cash_payable, with the summary (totals) row on.

Right-click a table → **Resize columns → Fit to data** so long names aren't cut off. Say in the page title that the data is simulated.

## 3. Share it

**Share → Link settings → Unlisted (anyone on the internet with the link can view)**, and do the same on each data source. Copy the report link and:

- paste it into `LOOKER_URL` at the top of `docs/app.js`, which shows a "Looker Studio version" button on the web dashboard
- add it to the links at the top of the main README

## Keeping it in sync

After `./scripts/build.sh`, re-upload the changed CSVs: open the data source → **Edit connection** → replace the file. Looker Studio keeps the charts.
