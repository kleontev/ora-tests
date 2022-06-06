-- only need one session
set echo on 

spool test.log

create table t(id, value) as select 1, 1 from dual;

update t set value = value + 1 where id = 1;

declare 
    pragma autonomous_transaction;
begin 
    update t set value = value + 1 where id = 1;
    commit;
end;
/

drop table t purge;

exit