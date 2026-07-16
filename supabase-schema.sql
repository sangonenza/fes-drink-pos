-- ドリンクPOS: Supabase スキーマ
-- Supabase ダッシュボード → SQL Editor に全文貼り付けて Run するだけ

create table products (
  id uuid primary key,
  name text not null,
  category text not null check (category in ('soft','nonal','can','draft')),
  price integer not null check (price >= 0),
  sort_order integer not null default 0,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table stock_events (
  id uuid primary key,
  product_id uuid not null references products(id),
  qty_delta integer not null,
  type text not null check (type in ('initial','restock','loss','adjust')),
  reason text,
  device text,
  created_at timestamptz not null default now()
);

create table sales (
  id uuid primary key,
  device text,
  items jsonb not null,
  payment text not null check (payment in ('cash','paypay')),
  total integer not null,
  cash_received integer,
  change integer,
  status text not null default 'completed' check (status in ('completed','cancelled')),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  updated_at timestamptz not null default now()
);

create table cash_counts (
  id uuid primary key,
  counted_amount integer not null,
  float_amount integer not null default 0,
  theoretical_amount integer not null,
  diff integer not null,
  note text,
  created_at timestamptz not null default now()
);

-- 端末のハートビート(棚卸し前の「未送信あり」警告に使う)
create table devices (
  id text primary key,
  name text,
  pending integer not null default 0,
  last_seen timestamptz not null default now()
);

-- 更新時に updated_at を自動更新(取消の同期検知に必要)
create or replace function touch_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end $$ language plpgsql;

create trigger products_touch before update on products
  for each row execute function touch_updated_at();
create trigger sales_touch before update on sales
  for each row execute function touch_updated_at();

-- RLS: 1日イベントの簡易運用として anon キーに全権限を与える。
-- URL と anon キーの組が実質のパスワードなので、共有リンクを部外者に渡さないこと。
alter table products enable row level security;
alter table stock_events enable row level security;
alter table sales enable row level security;
alter table cash_counts enable row level security;
alter table devices enable row level security;

create policy anon_all on products for all using (true) with check (true);
create policy anon_all on stock_events for all using (true) with check (true);
create policy anon_all on sales for all using (true) with check (true);
create policy anon_all on cash_counts for all using (true) with check (true);
create policy anon_all on devices for all using (true) with check (true);

-- 【既存DBの移行用】v1.4でカテゴリ4分類化(soft/nonal/can/draft)。
-- 上のcreate tableを旧版で実行済みの場合のみ、以下の2行を実行する:
-- alter table products drop constraint products_category_check;
-- alter table products add constraint products_category_check check (category in ('soft','nonal','can','draft'));
