#! /bin/bash

# helper functions
source /etc/bigbluebutton/bbb-conf/apply-lib.sh

# BIN
CAT=/bin/cat
ECHO=/bin/echo
MV=/bin/mv
LN=/bin/ln
RM=/bin/rm
SED=/bin/sed

# Privacy

## PATHS
CRONDAILY=/etc/cron.daily/bigbluebutton
CRONHOURLY=/etc/cron.hourly/bigbluebutton
BBBWEBPROP=/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties
FREESWITCHAPPCONF=/etc/bbb-fsesl-akka/application.conf
FREESWITCHLOGCONF=/etc/bbb-fsesl-akka/logback.xml
KURENTODEFAULT=/etc/default/kurento-media-server
KURENTOSERVICECONF=/usr/lib/systemd/system/kurento-media-server.service
KURENTOWEBRTCCONF=/etc/kurento/modules/kurento/WebRtcEndpoint.conf.ini
TURNSTUNCONF=/usr/share/bbb-web/WEB-INF/classes/spring/turn-stun-servers.xml
SIPJS=/usr/share/meteor/bundle/programs/web.browser/app/compatibility/sip.js

## Some settings
RECORDINGS=false
SERVERIP=XXX
STUNSERVER=XXX
STUNPORT=XXX
TURNSERVER=$STUNSERVER
TURNPORT=$STUNPORT
TURNSECRET=XXX
KEEPPROCESSEDRAW=1
KEEPUNPROCESSEDRAW=1
KEEPCACHES=1
KEEPLOGS=1
KEEPWBMATERIAL=1

# FUNCTIONS

retentioncalc ()  {
	DAYS=$1
	echo "$(expr $DAYS \* 24)-$(expr $DAYS \* 24 + 1) hours"
}

# MAIN

if [ -f $CRONDAILY ]
   then
      echo "Moving cron from daily to hourly for shorter retention periods."
      $MV $CRONDAILY $CRONHOURLY
      CRONDAILY=$CRONHOURLY
   else
      if [ -f $CRONHOURLY ]
         then
            echo "Cron already moved to hourly."
            CRONDAILY=$CRONHOURLY
         else
	    echo "Can't find cron, something's strange here. Exiting."
            exit 1
      fi
fi
      
$ECHO "Setting retention period for raw data of processed recordings to $(retentioncalc $KEEPPROCESSEDRAW)."
$SED -e "s/^\(published_days=\).*$/\1$(expr $KEEPPROCESSEDRAW - 1)/" -i $CRONDAILY
$SED -e 's/^#\(remove_raw_of_published_recordings\)/\1/' -i $CRONDAILY

$ECHO "Setting retention period for raw data of unprocessed recordings to $(retentioncalc $KEEPUNPROCESSEDRAW)."
$SED -e "s/^\(unrecorded_days=\).*$/\1$(expr $KEEPUNPROCESSEDRAW - 1)/" -i $CRONDAILY

$ECHO "Setting retention period for presentations, red5 caches, kurento caches, and freeswitch caches to $(retentioncalc $KEEPCACHES)"
$SED -e "s/^\(history=\).*$/\1$(expr $KEEPCACHES - 1)/" -i $CRONDAILY

$ECHO "Setting log history to $(retentioncalc $KEEPLOGS)."
$SED -e "s/^\(log_history=\).*$/\1$(expr $KEEPLOGS - 1)/" -i $CRONDAILY

if $RECORDINGS;then
	$ECHO "Keeping recordings activated."
	$SED -e 's/^\(disableRecordingDefault=\).*$/\1false/' -i $BBBWEBPROP
else
	$ECHO "+++Nonetheless, completely deactivating all recordings.+++"
	$SED -e 's/^\(disableRecordingDefault=\).*$/\1true/' -i $BBBWEBPROP
fi

$ECHO "Deactivating recordings of breakout rooms."
$SED -e 's/^\(breakoutRoomsRecord=\).*$/\1false/' -i $BBBWEBPROP

$ECHO "Setting bbb log level to 'error'."
$SED -e 's/^\(appLogLevel=\).*$/\1Error/' -i $BBBWEBPROP

$ECHO "Setting FreeSWITCH log levels to 'ERROR'."
$SED -e 's/\(^[[:space:]]*loglevel =\).*$/\1 "ERROR"/' -i $FREESWITCHAPPCONF
$SED -e 's/\(^[[:space:]]*stdout-loglevel =\).*$/\1 "ERROR"/' -i $FREESWITCHAPPCONF
$SED -e 's/\(^[[:space:]]*<logger name="[a-z\.]*" level="\)[A-Z]*\(" \/>\)/\1ERROR\2/' -i $FREESWITCHLOGCONF
$SED -e 's/\(^[[:space:]]*<root level="\)[A-Z]*\(">\)/\1ERROR\2/' -i $FREESWITCHLOGCONF

$ECHO "Leaving red5 loglevel at INFO."

$ECHO "Setting Kurento log levels to 1 / ERROR."
$SED -e 's/\(export GST_DEBUG=\).*$/\1"1,Kurento*:1,kms*:1,sdp*:1,webrtc*:1,*rtpendpoint:1,rtp*handler:1,rtpsynchronizer:1,agnosticbin:1"/' -i $KURENTODEFAULT
$SED -e 's/\(--gst-debug-level=\)[0-9]\{1\}/\11/' -i $KURENTOSERVICECONF
$SED -e 's/\(--gst-debug=\)"[a-Z0-9,*:]\?"/\1"1,Kurento*:1,kms*:1,sdp*:1,webrtc*:1,*rtpendpoint:1,rtp*handler:1,rtpsynchronizer:1,agnosticbin:1"/' -i $KURENTOSERVICECONF
systemctl daemon-reload

$ECHO "Adding custom STUNTURN server."
$CAT <<HERE > $TURNSTUNCONF
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.springframework.org/schema/beans
        http://www.springframework.org/schema/beans/spring-beans-2.5.xsd">
    <bean id="stun0" class="org.bigbluebutton.web.services.turn.StunServer">
        <constructor-arg index="0" value="stun:$STUNSERVER"/>
    </bean>
    <bean id="turn0" class="org.bigbluebutton.web.services.turn.TurnServer">
        <constructor-arg index="0" value="$TURNSECRET"/>
        <constructor-arg index="1" value="turns:$TURNSERVER:$TURNPORT?transport=tcp"/>
        <constructor-arg index="2" value="86400"/>
    </bean>
    <bean id="stunTurnService"
            class="org.bigbluebutton.web.services.turn.StunTurnService">
        <property name="stunServers">
            <set>
                <ref bean="stun0"/>
            </set>
        </property>
        <property name="turnServers">
            <set>
                <ref bean="turn0"/>
            </set>
        </property>
    </bean>
</beans>
HERE

$ECHO "Replacing hardcoded Google STUN in sip.js."
$SED -e "s/\(^[[:space:]]*stunServers:\).*google\.com.*$/\1 ['stun:$STUNSERVER:$STUNPORT'],/" -i $SIPJS

$ECHO "Setting external IP address in Kurento to prevent the use of a hardcoded Google STUN."
$SED -e "s/[;]\{0,1\}\(externalAddress=\).*$/\1$SERVERIP/" -i $KURENTOWEBRTCCONF

$ECHO "Linking folder for deleted recordings to /dev/null."
$RM -rf /var/bigbluebutton/deleted
$LN -s /dev/null /var/bigbluebutton/deleted

if [ $(grep "# Delete whiteboard material" $CRONDAILY --count) -eq 0 ];
then
	$ECHO "Adding deletion of whiteboard material to daily cron."
	cat <<HERE >> /etc/cron.daily/bigbluebutton
# 
# Delete whiteboard material
# 
KEEPWBMATERIAL=$KEEPWBMATERIAL
find /var/bigbluebutton/* -maxdepth 1 -type d -not \( -name basic_stats -o -name -o -name blank -o -name captions -o -name configs -o -name deleted -o -name diagnostics -o -name events -o -name screenshare -o -name playback -o -name published -o -name recording -o -name unpublished \) -mtime +\$(expr \$KEEPWBMATERIAL - 1) -exec rm -rf {} +
HERE
else
	$ECHO "Setting retention period of whiteboard material to $(retentioncalc $KEEPWBMATERIAL)."
	$SED -e "s/^\(KEEPWPMATERIAL\).*$/\1$KEEPWBMATERIAL/" -i $CRONDAILY
fi
