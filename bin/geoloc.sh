#!/usr/bin/env bash
#
# (C) Copyright Jon Seymour 2010.
#
# See:
#    http://orwelliantremors.blogspot.com/2010/12/mobile-80211-parole-bracelet-for-man-in.html
#

SCRIPT=$0
GEOLOC_HOME=${GEOLOC_HOME:-~/.geoloc}

# something bad happened, adios...
die()
{
    echo "$*" 1>&2
    exit 1
}

# launch the editor on this script
edit()
{
    ${EDITOR:-emacs -nw} $SCRIPT
}

# controlled dispatch of a sub-function
dispatch()
{
    "$@"
}

# POST a json structure to the specified URL
json_call()
{
    local url=$1
    local data=$2

    test -n "$url" || die "usage: json_call url data" 

    # Adapted from: http://coderrr.wordpress.com/2008/09/10/get-the-physical-location-of-wireless-router-from-its-mac-address-bssid/

    curl -s --header "Content-Type: text/plain;" --data "$data" $url
}

# Pretty print a JSON string on stdin so that it is easier to read and parse
format_json()
{
    # from: http://ruslanspivak.com/2010/10/12/pretty-print-json-from-the-command-line/
    # tweaked by: http://stackoverflow.com/questions/2269919/extracting-numerical-value-from-python-decimal
    python -c "import sys, json; json.encoder.FLOAT_REPR=str; print json.dumps(json.load(sys.stdin), sort_keys=True, indent=4)"
}

#
# normalize the MAC to be string of 12 upper case hex digits
#
normalize_mac_filter()
{
    sed "/^\$/d" | tr -d ':' | tr '[a-f]' '[A-F]'
}

# Remove separators from a MAC address
shrink_mac()
{
    local mac=$1
    echo $mac | normalize_mac_filter
}

# Expand a shrunk MAC address with the specified separator
expand_mac()
{
    local mac=$1
    local separator=$2

    echo $mac | sed "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1${separator}\2${separator}\3${separator}\4${separator}\5${separator}\6/"
}

# Generate a locate request from a template request
locate_template()
{
    local mac=$1
    local ssid=$2

    expanded_mac=$(expand_mac $(shrink_mac "$mac") "-")

( 
cat <<EOF
{
   "version":"1.1.0",
   "request_address":true,
   "wifi_towers": [
   {
      "mac_address":"$expanded_mac",
      "ssid":"$ssid",
      "signal_strength":-50
   }
   ]
}
EOF
) | tr -d \\012 

}

# Perform a JSON call to map a MAC address to a location.
# Returned data is instrumented with parameters that generated it and time of call
fetch_location()
{
    local mac=$1
    local ssid=$2

    test -n "$mac" || die "usage: locate mac [ssid]"

    json_call https://www.google.com:443/loc/json "$(locate_template $mac $ssid)" | sed "s/}\$/,\"mac_address\":\"$mac\",\"ssid\":\"$ssid\",\"accessed_at\":\"$(date +%Y%m%dT%H%M%S)\"}/;s/{,/{/"
}

# Output the location of the mac_address cache
cache_dir()
{
    local mac=$1

    echo ${GEOLOC_HOME}/db/mac_addresses/$mac
}

map_dir()
{
    local map=$1
    echo ${GEOLOC_HOME}/db/maps/$map
}

# Locate a mac address, but only if we haven't cached it.
locate()
{
    local mac=$1
    local ssid=$2

    test -n "$mac" || die "usage: locate mac [ssid]"

    mac=$(shrink_mac "$mac")

    local dir=$(cache_dir $mac)
    local file=$dir/current

    if ! test -f "$file"
    then
         test -d "$dir" || mkdir -p "$dir" || die "could not make directory $dir"
         fetch_location "$mac" "$ssid" > $file || die "fetch failed"
    fi
    json=$(cat $file)
    test -n "$json" && echo "$json"
}

# As per locate, but format it as CSV
locate_csv()
{
    local mac=$1
    local ssid=$2

    test -n "$mac" || die "usage: locate mac [ssid]"

    locate $mac $ssid | json_to_csv $mac $ssid     
}

# Format a json record as a CSV
json_to_csv()
{
    local mac=$1
    local ssid=$2

    format_json | sed -n "s/.*\"latitude\": *\(.*,\).*/\1/p;s/.*\"longitude\": *\(.*\)/\1\n/p;" | tr -d \\012 | sed "s/^/$(shrink_mac $mac),/;s/\$/,$ssid\n/"
}

show()
{
    local addr=$1

    test -n "$addr" || die "fatal: usage show addr"
    local mac=$(shrink_mac $addr)
    local dir=$(map_dir $mac)

    if ! test -d "$dir"
    then
        locate "$mac" >/dev/null # prime the cache
	map create $mac &&
        rm $dir/center &&
        ln -sf ../../mac_addresses/$mac $dir/center &&
        echo 20 > $dir/zoom &&
        map add $mac $mac || die "fatal: map creation failed"
    fi
    map build $mac &&
    map open $mac
}

# replace any unusual characters in the SSID with ?
cleanse-binary()
{
    tr -c "[A-Za-z0-9:!~@#\$%^&*(){}_+='<>,./\\ ;\012\015-]" '?'
}

#
# rewrite the kismet file as MAC,SSID pairs
#
rewrite-kismet()
{
    cleanse-binary | sed -n "/^[0-9]/p" | cut -f4,3 -d\; | sort | uniq | sed "s/\(.*\);\(.*\)/\2 \1/"
}

# Functions on map objects
# map create {map}
# map open {map}
# map list
# map build {map}
# map add {map} {addr}
# map import-pcap {map} {pcap}
map()
{
    local map=$2
    local dir=${GEOLOC_HOME}/db/maps/${map}

    create()
    {
         local map=$1
         test -n "$map" || die "usage: map create map"

         local dir=$(map_dir $map)	
         test -d $dir && die "fatal: map $map already exists"

         mkdir -p $dir || die "fatal: unable to create map directory: $dir"
         (
              cp ${GEOLOC_HOME}/html/maps/default/index.html $dir 
              cp ${GEOLOC_HOME}/html/maps/default/generator.js $dir
              mkdir $dir/mac_addresses
              ln -sf ../../mac_addresses/FFFFFFFFFFFF $dir/center
              echo 14 > $dir/zoom
              :> $dir/dirty
         ) || ( 
            rm -rf $dir
         )
    }

    dir() 
    {
        echo $dir
    }

    delete()
    {
         test -n "$map" || die "usage: geoloc map delete {name}"
	 test -d "$dir" || die "$map does not exist"
         rm -rf "${dir:-/tmp/geoloc}"
    }

    list()
    {
         ( 
	     cd ${GEOLOC_HOME}/db/maps
	     find . -maxdepth 1 -type d | sed "s/^..//;/^.\$/d"
         )
    }

    mac_addresses()
    {
         local map=$1
         local dir=$(map_dir $map)
         test -d "$dir" || die "usage: map mac_addresses map"

         ( 
	     cd $dir/mac_addresses
	     ( find -maxdepth 1 -type d; find -maxdepth 1 -type l)  | sed "s/^..//;/^.\$/d"
         )
    }

    open()
    {
         local map=$1
         local dir=$(map_dir $map)
         test -d "$dir" || die "usage: map open map"

         if test -e $dir/dirty
         then
	     build "$map"
         fi
         
         test -e $dir/dirty && die "fatal: open failed due to previous errors"

         xdg-open $dir/index.html
    }

    add()
    {
         local map=$1
         local addr=$2
         local dir=$(map_dir $map)
   
         local mac=$(shrink_mac $addr)
         test -d "$dir" && test -n "$mac" || die "usage: map add map mac"
         test -e $dir/mac_addresses/$mac || ln -sf ../../../mac_addresses/$mac $dir/mac_addresses/$mac
         :> $dir/dirty
    } 

    import-pcap()
    {
         shift 1
         local pcap=$1
         local mac
         ( pcap assert exists "$pcap" ) || exit 1

         ( pcap access_points "$pcap" ) | while read mac
         do
	     add $map $mac
         done
         :> $dir/dirty
    }

    build()
    {
         local map=$1
         local dir=$(map_dir $map)
         test -d "$dir" || die "usage: map open map"

         (
             cd $dir
             locate FFFFFFFFFFFF > /dev/null # ensure the centre of the map is located
cat >generator.js <<EOF	     
function generator() {
    return {
        zoom: $(cat zoom),
        center: $(cat center/current),
        locations: [
            $( mac_addresses $map | while read m
               do
                   loc=$(locate $m)
                   test -n "$loc" && echo "${loc},"
               done
            )
        ]
    }
}
EOF
         ) && rm $dir/dirty || die "build faild"
        
    }

    dispatch "$@"
}

#
# The current second in the form yyyymmddThhmmss
#
now()
{
    date +%Y%m%dT%H%M%S
}

#
# The current day in the form yyyymmdd
#
today()
{
    date +%Y%m%d
}

interface()
{
     local intf=$2

     assert()
     {
          local intf=$2

          specified()
          {
               test -n "$intf" || die "an interface has not been specified"
          }

          exists()
          {
               ( interface list ) | grep "^${intf}\$" >/dev/null || die "interface $intf does not exist"
          }

          dispatch "$@"
     }

     enable()
     {
         assert exists $intf  
         sudo airmon-ng start $intf   
     }

     disable()
     {
         assert exists $intf  
         sudo airmon-ng stop $intf   
     }

     list() 
     { 
         ifconfig -s | tail -n +2 | cut -f1 -d' ' 
     }

     dispatch "$@"
}

# 
# manage pcap files
#
# pcap files are found in db/pcaps/${pcap}/pcap
#
pcap()
{
     local pcap=$2
     local dir=${GEOLOC_HOME}/db/pcaps/${pcap}
     local file=${dir}/pcap
     local map=pcap-${pcap}
 
     list()
     {
         ( 
	     cd ${GEOLOC_HOME}/db/pcaps
	     find . -maxdepth 1 -type d | sed "s/^..//;/^.\$/d"
         )
     }

     dir()
     {
         echo $dir
     }

     file()
     {
         echo $file
     }

     wireshark()
     {
	 pcap assert exists $pcap 
         shift 1 
	 $(which wireshark) $file "$@"
     }

     tshark()
     {
	 pcap assert exists $pcap 
         shift 1
	 $(which tshark) -r $file "$@"
     }

     assert()
     {
         local pcap=$2
         local dir=${GEOLOC_HOME}/db/pcaps/${pcap}
         local file=${dir}/pcap

         specified()
         {
	     test -n "$pcap" || die "pcap is not specified"
         }

         exists()
         {
             specified &&
	     test -d "$dir" || die "pcap $pcap does not exist"
         }

         does_not_exist()
         {
             specified &&
	     test -d "$dir" && die "pcap $pcap already exists"
             true
         }
 
         dispatch "$@"
     }

     import()
     {

         test -n "$pcap" || die "usage: geoloc pcap import {name} < pcap"
	 pcap assert does_not_exist $pcap 
         mkdir -p $dir || die "fatal: could not make $dir"
         cat > $file || die "fatal: could not import pcap $dir/pcap"
     }

     delete()
     {
         test -n "$pcap" || die "usage: geoloc pcap delete {name}"
	 pcap assert exists $pcap 

	 rm -rf "${dir}"
     }

     access_points()
     {
         test -n "$pcap" || die "usage: geoloc pcap access_points {name}"
	 pcap assert exists $pcap 
         (
             tshark $pcap -Tfields -e wlan.sa "wlan.fc.type_subtype == 0x05"
             tshark $pcap -Tfields -e wlan.sa "wlan.fc.type_subtype == 0x08"
         ) | normalize_mac_filter | sort | uniq
     }

     clients()
     {
         test -n "$pcap" || die "usage: geoloc pcap clients {name}"
	 pcap assert exists $pcap 
         (
            tshark $pcap -Tfields -e wlan.sa "wlan.fc.type_subtype == 0x04" 
            tshark $pcap -Tfields -e wlan.da "wlan.fc.type_subtype == 0x05" 
         ) | normalize_mac_filter | sort | uniq
     }

     capture()
     {
         shift 1
         local intf=$1
         shift 1

         (
              pcap assert specified $pcap
              interface assert specified $intf
         ) || {
	      die "usage: geoloc pcap capture {name} {interface} [ filter ... ]"
         }
                    
	 pcap assert does_not_exist $pcap 
         interface assert exists $intf

         mkdir -p $dir || die "fatal: could not make $dir"

         sudo tcpdump -w "$file" -s 0 -i "${intf}" "$@"
     }

     rename()
     {
         shift 1
         local new=$1

         pcap assert exists $pcap
         ( pcap assert does_not_exist $new ) || exit $?
 
         mv "$dir" $(pcap dir "$new") || die "could not rename $pcap to $new"
     }

     simple()
     {
         tshark $pcap -Tfields -Eseparator=\; -e frame.time_relative -e wlan.fc.type_subtype -e wlan.sa -e wlan.da -e wlan.ta -e wlan.ra -e wlan_mgt.ssid
     }

     _map()
     {
         assert pcap exists "$pcap"

         map_dir=$(map dir $map)
         if ! test -d "${map_dir}" 
         then
             ( map create $map ) || exit $?
             ( map import-pcap $map $pcap ) || exit $?
         fi
         echo "${map}" || die "failed to build map ${map}"
     }

     if [ "$1" == "map" ]
     then
        shift 1
        set -- _map "$@"
     fi

     dispatch "$@"
}

check_init()
{
    test -f ${GEOLOC_HOME}/js/lib.js || die "fatal: GEOLOC_HOME=$GEOLOC_HOME looks incorrect"
    test -f ${GEOLOC_HOME}/html/maps/default/index.html || die "fatal: GEOLOC_HOME=$GEOLOC_HOME looks incorrect"
    test -f ${GEOLOC_HOME}/html/maps/default/generator.js || die "fatal: GEOLOC_HOME=$GEOLOC_HOME looks incorrect"
}

cmd=$1
test -n "$cmd" && shift 1

if [ "$(type -t $cmd)" == "function" ] 
then
   check_init
   $cmd "$@"
else
   die "fatal: command not supported: $cmd"
fi


