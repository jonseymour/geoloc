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

# Remove separators from a MAC address
shrink_mac()
{
    local mac=$1
    echo $mac | tr -d ':-'
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

    json_call https://www.google.com:443/loc/json "$(locate_template $mac $ssid)" | sed "s/}\$/,\"mac_address\":\"$mac\",\"ssid\":\"$ssid\",\"accessed_at\":\"$(date +%Y%m%dT%H%M%S)\"}/"
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
	map create $mac &&
        rm $dir/center &&
        ln -sf ../../mac_addresses/$mac $dir/center &&
        echo 20 > $dir/zoom &&
        map add $mac $mac || die "fatal: map creation failed"
    fi
    map build $mac &&
    map open $mac
}

# Functions on map objects
# map create {map}
# map open {map}
# map list
# map build {map}
# map add {map} {addr}
map()
{
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
         ) || ( 
            rm -rf $dir
         )
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
    } 

    import-kismet()
    {
         local map=$1
         local dir=$(map_dir $map)
         test -d "$dir" || die "usage: map import-kismet map < file"
 
         cut -f4,3 -d\; | sed 1d | sort | uniq | awk 'BEGIN { FS=";" } { print $2 " " $1 }' | while read mac ssid
         do
              locate "$mac" "$ssid"
	      add "$map" "$mac"
         done
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
                   locate $m
                   echo ,
               done
            )
        ]
    }
}
EOF
         )
    }

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


