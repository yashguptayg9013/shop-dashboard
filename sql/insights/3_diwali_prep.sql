-- Insight 3: Diwali (8 Nov 2026) needs about Rs 5.5 lakh of extra stock, ordered in the
-- next two weeks, on top of everyday reorders. The everyday reorder levels won't catch it.

set search_path = shop;

-- The Diwali buy list by supplier, latest date to order (rush start minus lead time)
select supplier,
       min(order_by)                                         as order_by,
       count(*)                                              as items,
       sum(festival_qty)                                     as units,
       sum(festival_value)                                   as value_at_cost,
       string_agg(sku, ', ' order by festival_value desc)    as skus
from v_festival_prep
where festival_qty > 0
group by supplier
order by order_by;

-- Why the everyday rule isn't enough: bestsellers that ran out in the last 180 days
select sku, product, days_out, missed_units, missed_revenue, missed_profit
from v_stockouts
order by missed_revenue desc
limit 5;
