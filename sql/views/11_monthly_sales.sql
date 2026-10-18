-- Sales trend: how much did we sell each month, through which channel, and at what margin?

create or replace view shop.v_monthly_sales as
select month,
       count(distinct sale_id)                                          as invoices,
       sum(revenue)                                                     as revenue,
       sum(gross_profit)                                                as gross_profit,
       round(100 * sum(gross_profit) / sum(revenue), 1)                 as margin_pct,
       round(sum(revenue) / count(distinct sale_id), 0)                 as avg_invoice,
       sum(revenue) filter (where channel = 'counter')                  as counter_revenue,
       sum(revenue) filter (where channel = 'b2b')                      as b2b_revenue,
       sum(revenue) filter (where channel = 'online')                   as online_revenue,
       round(100 * (sum(revenue) / lag(sum(revenue)) over (order by month) - 1), 1) as revenue_vs_prev_month_pct
from shop.v_sales_lines
group by month;


-- Same, split by category: shows where margin is made, and when it moves.
create or replace view shop.v_category_monthly as
select month,
       category,
       sum(qty)                                          as units,
       sum(revenue)                                      as revenue,
       sum(gross_profit)                                 as gross_profit,
       round(100 * sum(gross_profit) / sum(revenue), 1)  as margin_pct
from shop.v_sales_lines
group by month, category;
