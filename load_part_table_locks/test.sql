-- trace[ksq] aka 10704 to determine which TM locks get acquired 
-- for certain dml/ddl operations on a partitioned table
col lock_mode for a9
col object_name for a15
col payload for a150
col subobject_name for a15
col trace_filename for a50

set echo on
set lines 300
set time off
set timi off

cl scr

spool test.log replace

select banner from v$version;

drop table test_tab purge;
drop table test_exch_part purge;

whenever sqlerror exit failure

create table test_tab (pkey date, val int)
partition by range (pkey)
(
    partition p_20220101 values less than (date '2022-1-2'),
    partition p_20220102 values less than (date '2022-1-3')
);


insert /*+append*/ into test_tab
select date '2022-1-1' + mod(rownum, 2), rownum
from dual
connect by rownum <= 10;

create table test_exch_part as select * from test_tab partition (p_20220101);

-- 10704 deprecated since 12.2?
alter session set events 'trace[ksq] disk medium';

-- test 1: direct path insert with a partition specified
-- expectation: mode 3 on table, mode 6 on partition
alter session set tracefile_identifier = 'test_1_insert_append_part';

insert /*+append*/ into test_tab partition for (date '2022-1-1')
select date '2022-1-1', rownum * 100 from dual connect by rownum <= 10;

commit;

-- test 2: direct path insert without partition specified
-- expectation: mode 6 on table
alter session set tracefile_identifier = 'test_2_insert_append_nopart';
insert /*+append*/ into test_tab
select date '2022-1-2', rownum from dual connect by rownum <= 10;

commit;

-- test 3:  move partition
-- expectation: mode 6 on partition, mode 3 on table
alter session set tracefile_identifier = 'test_3_move_part';
alter table test_tab move partition p_20220101;

-- test 4: exchange partition
-- expectation: mode 3 on table, mode 6 on partition
alter session set tracefile_identifier = 'test_4_exch_part';
alter table test_tab exchange partition p_20220101 with table test_exch_part;

break on trace_filename skip page duplicates

select
    trc.trace_filename,
    to_char(object_id,'0XXXXXXX') object_id_hex,
    uo.object_name,
    uo.subobject_name,    
    regexp_substr(trc.payload, 'mode=[0-9]') lock_mode,
    trc.payload
from user_objects uo
join v$diag_trace_file_contents trc on 1 = 1
    and (trc.session_id, trc.serial#) = (select sid, serial# from v$session where sid = userenv('sid'))
    and trc.payload like '%TM-' || to_char(uo.object_id, 'FM0XXXXXXX') || '%'
where uo.object_name = 'TEST_TAB'
order by trc.timestamp;

exit