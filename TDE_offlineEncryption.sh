#
#     This script gets a list of SQL commands from the database and executes them in parallel.
#
#   Here, the commands are ENCRYPT or DECRYPT datafiles. Each line is processed in background by
# a separated sqlplus process.
#
#     The script will not let more than $MAX_JOBS at the same time. This value can be adjusted at
#   run-time by changing it in $LOG_DIR/nb_jobs.txt file (the fil only contains the value)
#
#
die()
{
  echo "ERREUR : $*

  Aborting at $(date)"
  rm -f $TMP_SHELL
  rm -f $TMP_STMT
  rm -f $LOG_DIR/$$.tmp.lck
  rm -f $LOG_DIR/nb_jobs.txt
  rm -f $LOG_DIR/${SCRIPT}_result_*.txt
  exit 1
}
# ========================================================================================================
#
#     Generates the statements to execute, the main loop will group these statements in small chunck and 
#  execute them concurrently
#
# ========================================================================================================
getStmts()
{
  sqlplus -s / as sysdba <<%%
set pages 0
set feed off
set head off
set lines 2000
alter session set container=$PDB;
SELECT
  'alter database datafile ' || CHR (39) || df.name || CHR (39) || ' $OPERATION /*;' || round (bytes / 1024 / 1024 / 1024,2) || ' GB;*/;' command
FROM
  v\$tablespace ts
 ,v\$datafile_header   df
WHERE
    ts.ts# = df.ts#
  AND df.encrypted = case upper('$OPERATION') when 'DECRYPT' then 'YES' else 'NO' end
  AND (ts.name NOT IN ('SYSTEM','SYSAUX','TEMP','TEMP1','TMP01'
                      ,'TMP02','UNDO01','UNDO02','UNDO03','UNDOTBS2')
       AND ts.name NOT IN (
    SELECT
      upper (value)
    FROM
      gv\$parameter
    WHERE
      name = 'undo_tablespace'
  ))
ORDER BY
  bytes DESC

/

%%
  return $?
}
# ========================================================================================================
#
#   Generates a teporary scipt which will be used to execute each chunk of statements on the
#  background
#
#   Modify it depending on the statements to be executed
#
# ========================================================================================================
genRunStmt()
{
cat > $TMP_SHELL << %EOF%
  s="\$1"
  num=\$2
  LOG_DIR=\$3
  PDB=\$4
  start_date=\$(date "+%d/%m/%Y %H:%M:%S")
  start_date_epoch=\$(date +%s)

  toRun="\$s"

  #echo "Starting job \$num"
  #echo "$toRun"

sqlplus -s / as sysdba > \$LOG_DIR/${SCRIPT}_result_\$num.txt <<%%
set pages 0
set feed off
set head off
set tab off
set lines 2000
set trimout on
col cnt format "999G999G999G999"
whenever sqlerror exit failure 
alter session set container = \$PDB;

set feedback on
set echo on
set timing on 

--alter session enable parallel dml ;

\$(echo "\$toRun")
%%
status=$?
  while [ -f $LOG_DIR/${SCRIPT}_verif.tmp.lck ]
  do
    sleep 1
  done
  end_date=\$(date "+%d/%m/%Y %H:%M:%S")
  end_date_epoch=\$(date +%s)
  secs=\$((\$end_date_epoch - \$start_date_epoch))
  touch $LOG_DIR/${SCRIPT}_verif.tmp.lck
  echo "       --+--> Job \$num terminated in \$secs seconds (Start : \$start_date --> End : \$end_date) "
  echo "         |"
  echo "\$toRun" | sed -e "s;^;         |         ;"
  echo "         |"
  echo "         +-----------------------------------------------------------------------"
  echo "         |"
  cat $LOG_DIR/${SCRIPT}_result_\$num.txt | sed -e "s;^;         |         ;"
  echo "         |"
  echo "         +-----------------------------------------------------------------------"
  rm -f $LOG_DIR/${SCRIPT}_verif.tmp.lck
  rm -f $LOG_DIR/${SCRIPT}_result_\$num.txt
  echo "\$toRun;\$status;\$secs" >> $SUM_FILE
%EOF%
}

#
#     CDB and PDB hardcoded here for tests
#
DB=IFOPEURC
PDB=IFOPEUR
MAX_JOBS=100        # 50 encryption at a time is barely noticeable on the machine
OPERATION=ENCRYPT   # Can be encrypt or decrypt

SCRIPT=$(basename $0 .sh)
SCRIPT_LABEL="    OFFLINE parallel tablespace encryption"
LOG_DIR=$HOME/$SCRIPT/$DB
mkdir -p $LOG_DIR
rm -f $LOG_DIR/${SCRIPT}_verif.tmp.lck
rm -f $LOG_DIR/${SCRIPT}_result_*.txt

script_start_date=$(date "+%d/%m/%Y %H:%M:%S")
script_start_date_epoch=$(date +%s)


LOG_FILE=$LOG_DIR/${SCRIPT}_$(date +%Y%m%d_%H%M%S).log
SUM_FILE=$LOG_DIR/${SCRIPT}_$(date +%Y%m%d_%H%M%S).csv

TMP_SHELL=$LOG_DIR/${SCRIPT}_tmpRun.sh
TMP_STMT=$LOG_DIR/${SCRIPT}_tmpStmt.tmp

. $HOME/$DB.env || die "Unable to set the environment"
if tty -s
then
  [ "$TERM" != "screen" ] && die "This script must be launched with nohup or in a screen"
fi

# ========================================================================================================
#
#      Generate the temporary shell script
#
# ========================================================================================================
genRunStmt
if [ $? -ne 0 ]
then
  cat $TMP_SHELL
  die "Error generating the temporary shell script"
fi

i=0
{

  echo "============================================================================="
  echo "    $SCRIPT_LABEL"
  echo "    Started at : $(date)"
  echo "    Operation  : $OPERATION"
  echo "    LOG File   : $LOG_FILE"
  echo "    Parallel   : $MAX_JOBS
  echo "    Can be changed at run_time by modifying"
  echo "    $LOG_DIR/nb_jobs.txt
  echo "============================================================================="
  echo $MAX_JOBS>$LOG_DIR/nb_jobs.txt

  #
  #        Generate the list of stetements to execute in parallel
  #  the file is then used as input of the while below (< notation ate the done level)
  #
  getStmts > $TMP_STMT
  if [ $? -ne 0 ]
  then
    cat $TMP_STMT
    die "Error generating the statements"
  fi

  j=0
  i=0
  while read line 
  do
    #
    #       Define the number of lines to execute by  single background process
    #   must be a multiple of the number of statements generated for an action
    #
    NB_LINES=1
    if [ $i -eq $NB_LINES ]
    then
      j=$(($j + 1))
      sh $TMP_SHELL  "$stmt" $j $LOG_DIR $PDB &
      i=0
      stmt=""
    fi
    if [ $i -le 5 ]
    then
      stmt="$stmt
$line"
      i=$(($i + 1))
    fi

    #
    #    If MAX_JOBS are running wait for some to terminate (read the file at each loop to change the value at runtime)
    #
    MAX_JOBS=$(cat $LOG_DIR/nb_jobs.txt)
    while [ $(jobs -r | wc -l | tr -d " ") -ge $MAX_JOBS ]
    do
      sleep 10
    done
  done < $TMP_STMT # input redirection

  #
  #    If statements were not launched then run them
  #
  if [ "$stmt" != "" ]
  then
      j=$(($j + 1))
      sh $TMP_SHELL  "$stmt" $j $LOG_DIR $PDB &
      i=0
      stmt=""
  fi

  echo "All done, ....."
  echo "Waiting for background processes to finish"
  echo "=========================================="
  echo
   wait

script_end_date=$(date "+%d/%m/%Y %H:%M:%S")
script_end_date_epoch=$(date +%s)
script_secs=$(($script_end_date_epoch - $script_start_date_epoch))

echo "+===========================================================================+"
echo "   Script terminated "
echo "   Start date : $script_start_date"
echo "   Operation  : $OPERATION"
echo "   End date   : $script_end_date"
echo "   Duration   : $script_secs Seconds"
echo "   LOG File   : $LOG_FILE"
echo "+===========================================================================+"


} 2>&1 | tee $LOG_FILE

rm -f $TMP_SHELL
rm -f $TMP_STMT
rm -f $LOG_DIR/$$.tmp.lck
rm -f $LOG_DIR/nb_jobs.txt
rm -f $LOG_DIR/${SCRIPT}_result_*.txt
