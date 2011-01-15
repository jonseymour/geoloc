//
// assumes center, zoom and locations are defined elsewhere
//
function map_initialize() {

    var zoom   = before_generator().zoom;
    var center = before_generator().center;
    var before = before_generator().locations;
    var after  = after_generator().locations;

    var latlng = new google.maps.LatLng(center.location.latitude, center.location.longitude);

    var myOptions = {
      zoom: zoom,
      center: latlng,
      mapTypeId: google.maps.MapTypeId.ROADMAP
    };

    var map = new google.maps.Map(document.getElementById("map_canvas"), myOptions);

    for (i = 0; i < before.length; i++)
    {
        var title = before[i].mac_address + " - " + before[i].ssid + " - " + before[i].accessed_at;

        var beforeitem = undefined;
        var afteritem = undefined;
     
        if (before[i].location != undefined && 
	    before[i].location.accuracy != undefined && 
	    before[i].location.accuracy < 140000)
	{
            beforeitem = before[i];
	}

       
        if (after[i].location != undefined && 
	    after[i].location.accuracy != undefined 
	    && after[i].location.accuracy < 140000)
	{
            afteritem = after[i];
	}

        var title;

        if (beforeitem != undefined)
        {
            if (afteritem != undefined)
	    {
                if (afteritem.location.latitude == beforeitem.location.latitude 
                    && afteritem.location.longitude == beforeitem.location.longitude)
   	        {
		    title = "unchanged: "+afteritem.mac_address;
                    continue;
		}
                else
	        {
		    title = "before: "+beforeitem.mac_address;
		}
	    }
            else
	    {
                title = "deleted: "+beforeitem.mac_address;
	    }

    	    new google.maps.Marker({
	      	position: new google.maps.LatLng(beforeitem.location.latitude, beforeitem.location.longitude), 
      		map: map, 
      		"title": title
	    })
        }

        if (afteritem != undefined)
        {
            var afterpos = new google.maps.LatLng(afteritem.location.latitude, afteritem.location.longitude)

            if (beforeitem != undefined)
	    {
                if (afteritem.location.latitude == beforeitem.location.latitude 
                    && afteritem.location.longitude == beforeitem.location.longitude)
   	        {
		    continue;
		}
                else
	        {
		    title = "after: "+afteritem.mac_address;

                    var beforepos = new google.maps.LatLng(beforeitem.location.latitude, beforeitem.location.longitude)
                    new google.maps.Polyline({
			    map: map,
			    path: [ afterpos, beforepos ]
   		    })
		}
	    }
            else
	    {
		title = "added: "+afteritem.mac_address;
                continue;
	    }

    	    new google.maps.Marker({
	      	position: afterpos, 
      		map: map, 
		"title": title
	    })
        }
    } 
    
}

