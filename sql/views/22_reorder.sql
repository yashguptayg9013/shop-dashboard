-- Reorder alerts: what to order today, and how much. (Festival items are planned
-- separately in v_festival_prep.)
--
-- Daily pace = units sold in the last 28 days / days the item was actually in stock.
-- (Counting out-of-stock days would make a sold-out bestseller look slow.)
--   reorder point = pace x (supplier lead time + 7 days safety)
--   order qty     = enough for lead time + 30 days, rounded up to the supplier's pack size

create or replace view shop.v_reorder_alerts as
with recent as (
    select product_id,
           sum(qty_out)                                                as sold_28d,
           count(*) filter (where closing_qty > 0 or qty_out > 0)      as in_stock_days
    from shop.v_daily_stock
    where day > shop.as_of() - 28
    group by product_id
),
pace as (
    select s.*, p.pack_size, sup.lead_time_days, r.in_stock_days,
           r.sold_28d::numeric / nullif(r.in_stock_days, 0) as per_day
    from shop.v_stock_on_hand s
    join shop.products p    using (product_id)
    join shop.suppliers sup on sup.supplier_id = p.supplier_id
    join recent r           using (product_id)
)
select product_id, sku, product, category, supplier, qty, unit_cost,
       round(per_day, 1)                                     as per_day,
       in_stock_days,
       round(qty / nullif(per_day, 0), 1)                    as days_of_cover,
       lead_time_days,
       ceil(per_day * (lead_time_days + 7))                  as reorder_point,
       ceil(greatest(per_day * (lead_time_days + 30) - qty, 0) / pack_size) * pack_size as order_qty,
       round(ceil(greatest(per_day * (lead_time_days + 30) - qty, 0) / pack_size) * pack_size * unit_cost) as order_value,
       case when qty = 0                              then '1 Out of stock'
            when qty / per_day <= lead_time_days      then '2 Order today'
            when qty <= per_day * (lead_time_days + 7) then '3 Order this week'
            else '4 OK' end                           as status
from pace
where per_day > 0
  and product_id not in (select product_id from shop.v_product_seasonality where is_seasonal);


-- Stockouts: how often did sellers run out, and what did it cost?
-- Missed sales = days out of stock x the item's pace on in-stock days. It's an estimate:
-- some customers wait or buy something else, so treat it as the upper end.
create or replace view shop.v_stockouts as
with last_180 as (
    select product_id,
           count(*) filter (where closing_qty <= 0)                    as days_out,
           sum(qty_out)::numeric
             / nullif(count(*) filter (where closing_qty > 0 or qty_out > 0), 0) as per_day_in_stock
    from shop.v_daily_stock
    where day > shop.as_of() - 180
    group by product_id
),
unit_econ as (
    select product_id,
           sum(revenue) / sum(qty)      as revenue_per_unit,
           sum(gross_profit) / sum(qty) as profit_per_unit
    from shop.v_sales_lines
    where sale_date > shop.as_of() - 180
    group by product_id
)
select p.product_id, p.sku, p.name as product, p.category,
       l.days_out,
       round(l.per_day_in_stock, 1)                                          as per_day_in_stock,
       round(l.days_out * l.per_day_in_stock)                                as missed_units,
       round(l.days_out * l.per_day_in_stock * u.revenue_per_unit)           as missed_revenue,
       round(l.days_out * l.per_day_in_stock * u.profit_per_unit)            as missed_profit
from last_180 l
join shop.products p using (product_id)
join unit_econ u     using (product_id)
where l.days_out > 0
  and p.product_id not in (select product_id from shop.v_dead_stock where status = 'Dead')
  and p.product_id not in (select product_id from shop.v_product_seasonality where is_seasonal);
