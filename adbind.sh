#!/bin/bash

############################################################ 
#
# Luke Windram  11/21/14
#
# Credit: This script is based heavily on Rich Trouton's  
# caspercheck script, which is in turned based on some
# similar work by FaceBook.  His original is located at
# http://derflounder.wordpress.com/2014/04/23/
# caspercheck-an-auto-repair-process-for-casper-agents/
#
############################################################ 

ADUser=AD_account_with_join_permissions
ADPass=above_AD_account_password
internal_server_address=address_of_an_interally_resolved_website
ADdomain=desired_domain
log_location="/var/log/adBinding.log"
 
############################################################
#
# Functions
#
############################################################
 
# Function to provide logging of the script's actions to
# the log file defined by the log_location variable
ScriptLogging(){
 
    DATE=`date +%Y-%m-%d\ %H:%M:%S`
    LOG="$log_location"
    
    echo "$DATE" " $1" >> $LOG
}
 
# Determine if the network is up by looking for any non-loopback network interfaces.
CheckForNetwork(){

    local test
    
    if [[ -z "${NETWORKUP:=}" ]]; then
        test=$(ifconfig -a inet 2>/dev/null | sed -n -e '/127.0.0.1/d' -e '/0.0.0.0/d' -e '/inet/p' | wc -l)
        if [[ "${test}" -gt 0 ]]; then
            NETWORKUP="-YES-"
        else
            NETWORKUP="-NO-"
        fi
    fi
}

# Determine if machine is on site
CheckSiteNetwork (){
 
  site_network="False"
  ping=`host -W .5 $internal_server_address`
 
  # If the ping fails - site_network="False"
  [[ $? -eq 0 ]] && site_network="True"
 
  # Check if we are using a test
  [[ -n "$1" ]] && site_network="$1"
}

# Ascertain Bind status by testing a lookup on the AD account that will be used to bind.
checkBind (){
 
domainAns=`dscl /Active\ Directory/GRCS/All\ Domains -read /Users/${ADUser} dsAttrTypeNative:userPrincipalName`


if [[ $domainAns =~ "is not valid" ]]; then
    ScriptLogging "AD user lookup failed for user $userName.  Proceeding to rebind."
else
    adComputer=`dsconfigad -show | awk '/Computer Account/{print $NF}' | tr '[a-z]' '[A-Z]' | sed 's/\$$//'`
    ScriptLogging "AD User lookup successful for user $userName.  Machine is bound as $adComputer."
    ScriptLogging "======== Exiting adBind ========"
    exit 0

fi
 
}

# Log IP address for troubleshooting
getIP () {
 
ip=`ifconfig -a | grep "inet " | grep -v 127.0.0.1 | awk '{ print $2 }'`
ScriptLogging "IP Address is $ip."

}
 
# Force update with timeserver 
resetTime () {
 
ntpd -g -q
timeServer=`systemsetup -getnetworktimeserver | awk '{ print $4 }'`
ScriptLogging "Time synced with $timeServer."
  
}

# Add the mac to the domain
reBind () {

compName=$(uname -n)
dsconfigad -force -a $compName -u $ADUser -p $ADPass -domain $ADdomain

# Pause to allow binding
sleep 15

# Allow logins from any domain in the forest
dsconfigad -alldomains enable

# Now make sure domain admins can login and get admin rights
dsconfigad -groups "Domain admins"

# Enable mobile accounts
dsconfigad -mobile enable
dsconfigad -mobileconfirm disable

# Disable UNC paths
dsconfigad -localhome enable
dsconfigad -useuncpath disable

# Set the shell to something sensible
dsconfigad -shell "/bin/bash"

# Enable packet signing
dsconfigad -packetsign require
}


############################################################
#
# Script
#
############################################################
 
ScriptLogging "======== Starting adBind ========"
 
# Wait up to 60 minutes for a network connection to become 
# available which doesn't use a loopback address. This 
# condition which may occur if this script is run by a 
# LaunchDaemon at boot time.
#
# The network connection check will occur every 5 seconds
# until the 60 minute limit is reached.
 
 
ScriptLogging "Checking for active network connection."
CheckForNetwork
i=1
while [[ "${NETWORKUP}" != "-YES-" ]] && [[ $i -ne 720 ]]
do
    sleep 5
    NETWORKUP=
    CheckForNetwork
    echo $i
    i=$(( $i + 1 ))
done
 
# If no network connection is found within 60 minutes,
# the script will exit.
 
if [[ "${NETWORKUP}" != "-YES-" ]]; then
   ScriptLogging "Network connection appears to be offline. Exiting adBind."
fi
   
 
if [[ "${NETWORKUP}" == "-YES-" ]]; then
   ScriptLogging "Network connection appears to be live."
  
  # Sleeping for 60 seconds to give WiFi time to come online.
  ScriptLogging "Pausing for one minute to give WiFi and DNS time to come online."
  sleep 60
  CheckSiteNetwork
 
  if [[ "$site_network" == "False" ]]; then
    ScriptLogging "Unable to verify access to site network. Exiting adBind."
  fi 
 
  if [[ "$site_network" == "True" ]]; then
    ScriptLogging "Access to site network verified"
 getIP
 resetTime
 checkBind
 reBind
 fi
 
fi
 
ScriptLogging "======== adBind bound computer ========"
 
exit 0
