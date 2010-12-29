#!/usr/bin/env bash
#
# (C) Copyright Jon Seymour 2010.
#
# See:
#    http://orwelliantremors.blogspot.com/2010/12/mobile-80211-parole-bracelet-for-man-in.html
#

SCRIPT=$0
GEOLOC_HOME=$(cd $(dirname "$SCRIPT")/..; pwd)

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
         fetch_location $mac $ssid > $file || die "fetch failed"
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

cmd=$1
test -n "$cmd" && shift 1

if [ "$(type -t $cmd)" == "function" ] 
then
   $cmd "$@"
else
   die "fatal: command not supported: $cmd"
fi


