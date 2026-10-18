-- Festival prep: what extra stock does the next festival rush need, and by when?
--
-- The everyday reorder rule (v_reorder_alerts) keeps normal sales covered. This adds
-- the festival on top:
--   everyday items   extra = (rush uplift - 1) x today's daily pace x rush length
--                    i.e. this year's pace, sped up by as much as last year's rush sped it up
--   seasonal items   need  = last year's rush pace x rush length - stock on the shelf
--                    (the everyday rule ignores them, so the shelf stock counts here)
-- Order by = rush start minus the supplier's lead time, so the stock is in before the rush.
-- Items with an uplift under 1.5, and dead items, are left to the everyday rule.

create or replace view shop.v_festival_prep as
with next_festival as (
    select name, festival_date, rush_days,
           festival_date - rush_days as rush_start
    from shop.festivals
    where festival_date > shop.as_of()
    order by festival_date
    limit 1
),
last_festival as (
    select f.festival_date, f.rush_days
    from shop.festivals f
    join next_festival n using (name)
    where f.festival_date <= shop.as_of()
    order by f.festival_date desc
    limit 1
),
first_day as (
    select min(sale_date) as d from shop.v_sales_lines
),
last_rush as (              -- the window can start before the data does, so divide by days with data
    select l.product_id,
           sum(l.qty) as units_last_rush,
           sum(l.qty)::numeric
             / (f.festival_date - greatest(f.festival_date - f.rush_days, fd.d) + 1) as last_rush_per_day
    from shop.v_sales_lines l
    cross join last_festival f
    cross join first_day fd
    where l.sale_date between f.festival_date - f.rush_days and f.festival_date
    group by l.product_id, f.festival_date, f.rush_days, fd.d
),
prep as (
    select s.product_id, s.sku, s.product, s.category, s.supplier,
           n.name                                   as festival,
           n.festival_date,
           n.rush_start,
           n.rush_days + 1                          as rush_length,
           sup.lead_time_days,
           p.pack_size,
           s.unit_cost,
           z.is_seasonal,
           z.rush_uplift,
           r.units_last_rush,
           round(s.sold_90d / 90.0, 1)              as per_day_now,
           s.qty                                    as stock_now,
           case when z.is_seasonal
                then r.last_rush_per_day * (n.rush_days + 1) - s.qty
                else (z.rush_uplift - 1) * s.sold_90d / 90.0 * (n.rush_days + 1)
           end                                      as extra_needed
    from shop.v_stock_on_hand s
    join shop.products p    using (product_id)
    join shop.suppliers sup on sup.supplier_id = p.supplier_id
    join last_rush r        using (product_id)
    join shop.v_product_seasonality z using (product_id)
    cross join next_festival n
    where (z.rush_uplift >= 1.5 or z.is_seasonal)
      and s.product_id not in (select product_id from shop.v_dead_stock where status = 'Dead')
)
select product_id, sku, product, category, supplier, festival, festival_date, rush_start, rush_length,
       lead_time_days, is_seasonal, rush_uplift, units_last_rush, per_day_now, stock_now,
       ceil(greatest(extra_needed, 0) / pack_size) * pack_size                    as festival_qty,
       round(ceil(greatest(extra_needed, 0) / pack_size) * pack_size * unit_cost) as festival_value,
       rush_start - lead_time_days                                                as order_by
from prep;
