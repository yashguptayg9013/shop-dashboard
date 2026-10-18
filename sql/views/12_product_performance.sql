-- Which items earn the money? ABC analysis over the last 12 months.
--   A = the items that together make the first 80% of revenue: never let these run out
--   B = the next 15%
--   C = the last 5%: candidates to drop or stock thinly
-- Ranking by profit next to revenue shows items that sell a lot but earn little.

create or replace view shop.v_product_performance as
with totals as (
    select product_id, sku, product, category,
           sum(qty)          as units,
           sum(revenue)      as revenue,
           sum(gross_profit) as gross_profit
    from shop.v_sales_lines
    where sale_date > shop.as_of() - interval '12 months'
    group by product_id, sku, product, category
),
ranked as (
    select *,
           round(100 * gross_profit / revenue, 1)                       as margin_pct,
           round(100 * revenue / sum(revenue) over (), 1)               as revenue_share_pct,
           100 * sum(revenue) over (order by revenue desc) / sum(revenue) over () as cum_share,
           rank() over (order by revenue desc)                          as revenue_rank,
           rank() over (order by gross_profit desc)                     as profit_rank
    from totals
)
select product_id, sku, product, category, units, revenue, gross_profit, margin_pct,
       revenue_share_pct, revenue_rank, profit_rank,
       case when cum_share - revenue_share_pct < 80 then 'A'
            when cum_share - revenue_share_pct < 95 then 'B'
            else 'C' end                                                as abc_class
from ranked;
