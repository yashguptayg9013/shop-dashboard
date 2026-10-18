# Build the Looker Studio version (about 30 minutes)

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

1. Open [lookerstudio.google.com](https://lookerstudio.google.com) → **Create → Data source → File upload**.
2. Upload `sales_lines.csv`, name the source `sales_lines`, and click **Connect**. On the field list, set `sale_date` to type *Date*, `month` to *Date (Year Month)*, and `revenue`, `cogs`, `gross_profit` to *Currency (INR)*.
3. Repeat for `monthly_sales`, `reorder_alerts`, `dead_stock`, `festival_prep` and `gst_monthly`, one data source each.
4. In `sales_lines`, add a calculated field **Margin %** = `SUM(gross_profit) / SUM(revenue)` and set its type to *Percent*.

## 2. Build the report

**Create → Report**, add `sales_lines` first, then the rest under **Resource → Manage added data sources**.

**Page 1 · Overview**
- A **date range control** and a **drop-down control** on `category`, in one row across the top.
- Four **scorecards** from `sales_lines`: SUM(revenue), SUM(gross_profit), Margin %, and Record Count (sale lines). Turn on comparison to the previous period.
- A **stacked column chart**: dimension `month`, breakdown dimension `channel`, metric SUM(revenue).
- A **table**: dimension `category`, metrics SUM(revenue), SUM(gross_profit), Margin %, sorted by revenue. Power banks stand out here.
- A **time series**: dimension `month`, metric Margin %, filtered to `category = Power banks`.

**Page 2 · Stock**
- A **table** from `reorder_alerts`, with a filter excluding `status = 4 OK`. Columns: product, status, qty, per_day, days_of_cover, lead_time_days, order_qty, order_value. Sort by status.
- A **table** from `dead_stock`: product, status, qty, stock_value, last_sale, days_since_last_sale.

**Page 3 · Diwali prep**
- A **table** from `festival_prep`, with a filter `festival_qty > 0`: order_by, product, supplier, units_last_rush, rush_uplift, stock_now, festival_qty, festival_value. Sort by order_by.

**Page 4 · GST**
- A **column chart** from `gst_monthly`: dimension `month`, metrics output_tax, itc, cash_payable.
- A **table** with month, taxable_sales, out_cgst, out_sgst, out_igst, itc, cash_payable.

Add a text box on page 1 saying the data is simulated, and link to the GitHub repository.

## 3. Share it

**Share → Manage access → Anyone on the internet with the link can view.** Copy the link and:

- paste it into `LOOKER_URL` at the top of `docs/app.js`, which shows a "Looker Studio version" button on the web dashboard
- add it to the links at the top of the main README

## Keeping it in sync

After `./scripts/build.sh`, re-upload the changed CSVs: open the data source → **Edit connection** → replace the file. Looker Studio keeps the charts.
