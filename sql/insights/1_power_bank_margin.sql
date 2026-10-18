-- Insight 1: power banks sell the most and earn the least.
-- Share of revenue vs share of gross profit by category, and margin before and after
-- the supplier's February 2026 price rise.

set search_path = shop;

select category,
       round(100 * sum(revenue) / sum(sum(revenue)) over (), 1)            as share_of_revenue_pct,
       round(100 * sum(gross_profit) / sum(sum(gross_profit)) over (), 1)  as share_of_profit_pct,
       round(100 * sum(gross_profit) filter (where month <  '2026-02-01')
                 / sum(revenue)      filter (where month <  '2026-02-01'), 1) as margin_oct_jan_pct,
       round(100 * sum(gross_profit) filter (where month >= '2026-03-01')
                 / sum(revenue)      filter (where month >= '2026-03-01'), 1) as margin_mar_sep_pct
from v_sales_lines
group by category
order by share_of_revenue_pct desc;

-- The cost step: supplier price per unit, bill by bill
select p.sku, h.valid_from, h.unit_cost,
       round(100 * (h.unit_cost / lag(h.unit_cost) over (partition by p.sku order by h.valid_from) - 1), 1) as change_pct
from v_cost_history h
join products p using (product_id)
where p.category = 'Power banks'
order by p.sku, h.valid_from;

-- Margin by channel since March. Online orders are priced 5% under the shelf.
select channel, round(100 * sum(gross_profit) / sum(revenue), 1) as margin_pct
from v_sales_lines
where category = 'Power banks' and month >= '2026-03-01'
group by channel;

-- What-if: shelf prices up Rs 100 (GST-inclusive). Counter margin at today's cost.
select p.sku,
       price                                                        as shelf_price,
       round(100 * (1 - c.unit_cost / (price / 1.18)), 1)           as counter_margin_pct
from products p
join v_cost_history c on c.product_id = p.product_id and c.valid_to = 'infinity'
cross join lateral (values (case p.sku when 'PWR-10K' then 999 else 1599 end),
                           (case p.sku when 'PWR-10K' then 1099 else 1699 end)) as v(price)
where p.category = 'Power banks'
order by p.sku, price;
