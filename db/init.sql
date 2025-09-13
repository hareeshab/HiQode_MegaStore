-- create two DBs: usersdb and ordersdb
create database usersdb;
create database ordersdb;

\connect usersdb;
create table if not exists users(
  id serial primary key,
  email text unique not null,
  password text not null,
  name text
);
insert into users(email, password, name) values('user@hiqode.in','pass123','HiQode User')
on conflict (email) do nothing;

\connect ordersdb;
create table if not exists orders(
  id serial primary key,
  user_email text not null,
  product_id text not null,
  status text default 'created',
  created_at timestamp default now()
);
