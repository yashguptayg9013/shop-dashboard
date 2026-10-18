-- Which items are festival items? For each festival rush (see the festivals table),
-- compares how often an item was bought with how often it would have been bought at
-- the pace of the 45 days either side.
--   - Nearby days, not the whole year, so a fading item (which simply sold more early
--     on) doesn't look seasonal.
--   - Number of sales, not units, so one bulk B2B order doesn't look like a rush.
--   - Festival by festival, so a rush where the item wasn't selling at all doesn't count.
--   rush_uplift 3.0 = bought three times as often in festival rushes as around them
--   is_seasonal     = uplift of 3 or more: planned per festival (v_festival_prep), not by
--                     the everyday reorder rule, and leftover stock isn't counted as dead

create or replace view shop.v_product_seasonality as
with bounds as (
    select min(sale_date) as first_day, shop.as_of() as last_day from shop.v_sales_lines
),
windows as (                 -- each festival's rush and the days around it, clipped to the data
    select f.festival_date,
           greatest(f.festival_date - f.rush_days, b.first_day)      as rush_from,
           f.festival_date                                           as rush_to,
           greatest(f.festival_date - f.rush_days - 45, b.first_day) as around_from,
           least(f.festival_date + 45, b.last_day)                   as around_to
    from shop.festivals f
    cross join bounds b
    where f.festival_date between b.first_day and b.last_day
),
per_festival as (
    select l.product_id,
           w.festival_date,
           count(*) filter (where l.sale_date between w.rush_from and w.rush_to)       as rush_sales,
           count(*) filter (where l.sale_date not between w.rush_from and w.rush_to)
             * (w.rush_to - w.rush_from + 1)::numeric
             / ((w.around_to - w.around_from + 1) - (w.rush_to - w.rush_from + 1))     as expected_sales
    from shop.v_sales_lines l
    join windows w on l.sale_date between w.around_from and w.around_to
    group by l.product_id, w.festival_date, w.rush_from, w.rush_to, w.around_from, w.around_to
),
totals as (
    select product_id, sum(rush_sales) as rush_sales, sum(expected_sales) as expected_sales
    from per_festival
    group by product_id
)
select p.product_id,
       coalesce(t.rush_sales, 0)                                    as rush_sales,
       round(coalesce(t.expected_sales, 0), 1)                      as expected_sales,
       round(t.rush_sales / nullif(t.expected_sales, 0), 1)         as rush_uplift,
       coalesce(t.rush_sales / nullif(t.expected_sales, 0) >= 3, false) as is_seasonal
from shop.products p
left join totals t using (product_id);
