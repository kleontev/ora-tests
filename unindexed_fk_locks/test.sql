col lock_mode for a9
col object_name for a30
col payload for a150
col subobject_name for a15
col trace_filename for a50
col object_id_hex for a15

set echo on
set lines 300
set time off
set timi off

set sqlprompt "SQL> "

cl scr

spool test.log replace

select banner from v$version;

drop table dropme$test_detail_ix purge;
drop table dropme$test_detail_no_ix purge;
drop table dropme$test_master purge;

whenever sqlerror exit failure

create table dropme$test_master (id int primary key, value int);

insert into dropme$test_master values (1, 1);
insert into dropme$test_master values (2, 2);
insert into dropme$test_master values (3, 3);

create table dropme$test_detail_ix(
    id int primary key,
    master_id int references dropme$test_master(id),
    value int
);

insert into dropme$test_detail_ix values (1, 1, 1);
insert into dropme$test_detail_ix values (2, 2, 2);

commit;

create index fk_dropme$test_detail on dropme$test_detail_ix(master_id);

create table dropme$test_detail_no_ix(
    id int primary key,
    master_id int references dropme$test_master(id),
    value int
);

insert into dropme$test_detail_no_ix values (1, 1, 1);
insert into dropme$test_detail_no_ix values (2, 2, 2);

commit;

-- 10704 deprecated since 12.2?
alter session set events 'trace[ksq] disk medium';

update dropme$test_master set id = 4 where id = 3;

break on trace_filename skip page duplicates

set timi on

-- we get mode=4 (share mode) on dropme$test_detail_no_ix, which prevents any other
-- updates from happening, but is not an exclusive (mode=6) lock nonetheless.
select
    trc.trace_filename,
    to_char(object_id,'0XXXXXXX') object_id_hex,
    uo.object_name,
    uo.subobject_name,
    regexp_substr(trc.payload, 'mode=[0-9]') lock_mode,
    trc.payload
from user_objects uo
left join v$diag_trace_file_contents trc on 1 = 1
    and (trc.session_id, trc.serial#) = (select sid, serial# from v$session where sid = userenv('sid'))
    and trc.payload like '%TM-' || to_char(uo.object_id, 'FM0XXXXXXX') || '%'
where uo.object_name like 'DROPME$TEST\_%' escape '\'
order by trc.timestamp
/

exit