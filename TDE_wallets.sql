Prompt
Prompt Wallet location
Prompt ==================================================
Prompt
col value format a100 new_value wallet_location
select value from v$parameter where name = 'wallet_root' ;


Prompt
Prompt Wallet Content
Prompt ==================================================
Prompt

Prompt
Prompt    To see wallet content, run the following on the database server
Prompt wallet password is needed
Prompt

prompt $ORACLE_HOME/bin/mkstore -wrl &wallet_location/tde -list

Prompt
Prompt Wallet Status
Prompt ==================================================
Prompt
set lines 200
col wrl_type format a4
col wrl_parameter format a70
col status format a15
col wallet_type format a10
col name format a10
col open_mode format a10
SELECT
   EW.WRL_TYPE
  ,EW.WRL_PARAMETER
  ,EW.STATUS
  ,EW.WALLET_TYPE
  ,C.NAME
  ,C.OPEN_MODE
FROM 
  V$ENCRYPTION_WALLET EW 
  JOIN V$CONTAINERS C ON (EW.CON_ID = C.CON_ID) 
WHERE UPPER(C.NAME) = UPPER(SYS_CONTEXT('USERENV', 'CON_NAME'))
/


select con_id, ENCRYPTIONALG, MASTERKEYID, MASTERKEY_ACTIVATED from V$DATABASE_KEY_INFO;

set lines 200
col con_id format 99
col key_id format a80
col act_date format a20
select
   con_id
  ,key_id
  ,to_char(activation_time,'dd/mm/yyyy hh24:mi:ss') act_date
from
  v$encryption_keys
order by
  con_id,activation_time desc;


--mkstore -wrl . -list
