cl scr

spool test.log replace

set echo on
set time off 
set timi off

col banner for a100
col object_name for a15
col payload for a150
col subobject_name for a15
col trace_filename for a40

set lines 300

select banner from v$version;

drop table dropme_target purge;
drop table dropme_source purge;

whenever sqlerror exit failure

create table dropme_target (part_key int)
partition by range (part_key)
(
    partition p0 values less than (1),
    partition p1 values less than (2),
    -- can't do MAXVALUE because I want it 
    -- to be interval-partitioned going forward
    partition p3 values less than (3) 
);

-- most common case - we're going to insert neither in first,
-- nor in last partition
create table dropme_source as select 1 part_key from dual;

-- aka 10704
alter session set events 'trace[ksq] disk medium';

-- test 1: RANGE table, "partition for" syntax
alter session set tracefile_identifier = 'range_part_for';
insert /*+append*/ into dropme_target partition for (1) select * from dropme_source;
commit;

-- test 2: RANGE table, pruning
alter session set tracefile_identifier = 'range_pruning';
insert /*+append*/ into (select * from dropme_target where part_key = 1) select * from dropme_source;
commit;

-- convert the table to interval-partitioned
alter table dropme_target set interval (1);

-- test 3: INTERVAL table, "partition for" syntax
alter session set tracefile_identifier = 'interval_part_for';
insert /*+append*/ into dropme_target partition for (1) select * from dropme_source;
commit;

-- test 4: INTERVAL table, pruning
alter session set tracefile_identifier = 'interval_pruning';
insert /*+append*/ into (select * from dropme_target where part_key = 1) select * from dropme_source;
commit;

break on trace_filename skip page

select    
    trc.trace_filename,
    uo.object_name,
    nvl(uo.subobject_name, '(whole table)') subobject_name,
    to_char(object_id,'0XXXXXXX') object_id_hex,
    trc.payload
from user_objects uo
join v$diag_trace_file_contents trc on 1 = 1
    and (trc.session_id, trc.serial#) = (select sid, serial# from v$session where sid = userenv('sid'))    
    and trc.payload like '%TM-' || to_char(uo.object_id, 'FM0XXXXXXX') || '%'
where uo.object_name = 'DROPME_TARGET'
order by trc.timestamp;

exit