
-- AIPub User
create user aipub with password 'Password1@';
alter user aipub with superuser;

-- AIPub User Database
create database aipub
WITH ENCODING='UTF8'
TEMPLATE=template0;

-- AIPub Usages Database
create database usages
WITH ENCODING='UTF8'
TEMPLATE=template0;
