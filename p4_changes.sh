#!/bin/bash
p4_user=svcp4admin
p4_online_db=/srv/perforce
p4_offline_db=/srv/perforce_backups/offline_database
p4_online_db_port=1666
p4_offline_db_port=2666
p4_binary=`which p4`

# CHECK IF P4D ONLINE DB PORT IS LISTENING
  echo "Checking p4d:$p4_online_db_port is listening"

  netstat -plantu | grep p4d | grep $p4_online_db_port

  ret_val=$?

  if [[ $ret_val == 1 ]]; then
    1>&2 echo "p4d NOT detected on port $p4_online_db_port"
    exit 1
  fi

# CHECK IF P4D OFFLINE DB PORT IS LISTENING
  echo "Checking p4d:$p4_offline_db_port is listening"
  netstat -plantu | grep p4d | grep $p4_offline_db_port

  ret_val=$?

  if [[ $ret_val == 1 ]]; then
    1>&2 echo "p4d NOT detected on port $p4_offline_db_port"
    exit 1
  fi

# START ONLINEDB CHECKS

# EXPORT ONLINEDB PORT
  export P4PORT=$p4_online_db_port

# VALIDATE P4_USER KNOWN TO PERFORCE ONLINEDB
  echo "Checking for $p4_user in $p4_online_db"
  $p4_binary users | grep $p4_user

  ret_val=$?

  if [[ $ret_val == 1 ]]; then
    1>&2 echo "$p4_user not found in $p4_online_db"
    exit 1
  fi

# ONLINEDB FETCH CHANGELIST 
  online_db_changelist=$($p4_binary -p localhost:$p4_online_db_port -u $p4_user changes)

# EXPORT OFFLINEDB PORT
  export P4PORT=$p4_offline_db_port

# VALIDATE P4_USER KNOWN TO PERFORCE ONLINEDB
  echo "Checking for $p4_user in $p4_offline_db"
  $p4_binary users | grep $p4_user

  ret_val=$?

  if [[ $ret_val == 1 ]]; then
    1>&2 echo "$p4_user not found in $p4_offline_db"
    exit 1
  fi

# OFFLINEDB FETCH CHANGELIST
  offline_db_changelist=$($p4_binary -p localhost:$p4_offline_db_port -u $p4_user changes)

# VALIDATE P4 CHANGELISTS ARE THE SAME BETWEEN ONLINE AND OFFLINE DB
  if [[ $online_db_changelist == $offline_db_changelist ]]; then
    echo "$p4_online_db and $p4_offline_db are the same"
  else
    1>&2 echo "$p4_online_db and $p4_offline_db are NOT the same"
    exit 1
  fi
