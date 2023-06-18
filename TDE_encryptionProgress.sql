set lines 400 pages 1000
col sid         format 99999
col serial#     format 99999
col start_time  format a25
col opname format a30
col progress format a70
col timestamp format a30
col current_object format a100
col tablespace_name format a20
col name format a100

SELECT
  ge.sid
 ,ge.serial#
 ,to_char(ge.start_time,'dd/mm/yyyy hh24:mi:ss') start_time
 ,ge.opname
 ,to_char(ge.sofar,'999G999G999G999G999') || ' /' || to_char(ge.totalwork,'999G999G999G999G999') || ' ' ||  ge.units || ' (' || to_char(((ge.sofar/ge.totalwork)*100),'99D99') || ' % )' progress
 ,case 
    when t.ts# is null then f.name
    else t.name
  end Current_object
 ,ge.timestamp
-- ,ge.message
-- ,ge.*
FROM
  gv$session_longops ge
  left join v$tablespace t on (ge.target = t.ts#)
  left join v$datafile f on (ge.target = f.file#)
WHERE
  ge.opname LIKE 'TDE%'
  and ge.time_remaining != 0
ORDER BY
  ge.timestamp;

prompt
prompt ENcrypted datafiles count
prompt
select 
   encrypted
  ,count(*) 
from v$datafile_header 
where
      (tablespace_name NOT IN ('SYSTEM','SYSAUX','TEMP','TEMP1','TMP01'
                              ,'TMP02','UNDO01','UNDO02','UNDO03','UNDOTBS2')
       AND tablespace_name NOT IN (
    SELECT
      upper (value)
    FROM
      gv$parameter
    WHERE
      name = 'undo_tablespace'
  ))
group by encrypted;

define NB=20
prompt
prompt &NB first non encrypted datafiles
prompt
SELECT
  tablespace_name
 ,name
FROM
  v$datafile_header
WHERE
    encrypted = 'NO'
  AND ROWNUM <=&NB
  AND (tablespace_name NOT IN ('SYSTEM','SYSAUX','TEMP','TEMP1','TMP01'
                              ,'TMP02','UNDO01','UNDO02','UNDO03','UNDOTBS2')
       AND tablespace_name NOT IN (
    SELECT
      upper (value)
    FROM
      gv$parameter
    WHERE
      name = 'undo_tablespace'
  ))
ORDER BY
  tablespace_name
 ,file#;

