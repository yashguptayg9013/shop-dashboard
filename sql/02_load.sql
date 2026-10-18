-- Load the CSVs in data/. Run from the repository root with psql:
--   psql "$DATABASE_URL" -f sql/02_load.sql
-- \copy reads the files on your machine, so this also works against a hosted database.

set search_path = shop;

\copy suppliers         from 'data/suppliers.csv'         with (format csv, header)
\copy products          from 'data/products.csv'          with (format csv, header)
\copy customers         from 'data/customers.csv'         with (format csv, header)
\copy opening_stock     from 'data/opening_stock.csv'     with (format csv, header)
\copy purchase_invoices from 'data/purchase_invoices.csv' with (format csv, header)
\copy purchase_items    from 'data/purchase_items.csv'    with (format csv, header)
\copy sales_invoices    from 'data/sales_invoices.csv'    with (format csv, header)
\copy sales_items       from 'data/sales_items.csv'       with (format csv, header)

analyze;
