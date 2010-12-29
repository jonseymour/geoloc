//
// assumes center, zoom and locations are defined elsewhere
//
function map_initialize() {

    var map_data = generator();
    var locations = map_data.locations;
    var zoom = map_data.zoom;
    var center = map_data.center;

    var latlng = new google.maps.LatLng(center.location.latitude, center.location.longitude);

    var myOptions = {
      zoom: zoom,
      center: latlng,
      mapTypeId: google.maps.MapTypeId.ROADMAP
    };

    var map = new google.maps.Map(document.getElementById("map_canvas"), myOptions);

    for (i = 0; i < locations.length; i++)
    {
        var title = locations[i].mac_address + " - " + locations[i].ssid + " - " + locations[i].accessed_at;

        if (locations[i].location.address != undefined) {
            title = title + " - " + locations[i].location.address.street_number + ", " + locations[i].location.address.street
        }
 
	new google.maps.Marker({
	      	position: new google.maps.LatLng(locations[i].location.latitude, locations[i].location.longitude), 
      		map: map, 
      		"title": title
	  })
    } 
    
}

