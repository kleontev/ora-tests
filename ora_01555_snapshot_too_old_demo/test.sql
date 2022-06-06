-- https://asktom.oracle.com/pls/apex/f?p=100:11:::::P11_QUESTION_ID:40115659055475

set echo on
set serverout on
set time off
set timi on

cl scr

spool test.log

drop table test_ora1555_demo purge;

whenever sqlerror exit failure

create table test_ora1555_demo as select * from dual;

-- setting size to 100k forces Oracle to use system RBS, why? 
create undo tablespace tiny_undotbs datafile 'tiny_undotbs.dbf' size 500k;

alter system set undo_tablespace = tiny_undotbs;

var cur refcursor

exec open :cur for select * from test_ora1555_demo;

begin
    for i in 1 .. 1e4 loop
      update test_ora1555_demo
      set dummy = to_char(mod(i, 10));
      commit;
    end loop;
end;
/

whenever sqlerror continue

-- try to fetch data from previously opened cursor
-- fails with ORA-01555
print cur

whenever sqlerror exit failure

alter system set undo_tablespace = undotbs1;

drop tablespace tiny_undotbs including contents and datafiles;

drop table test_ora1555_demo purge;

exit