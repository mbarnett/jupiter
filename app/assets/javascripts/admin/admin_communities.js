$(document).on('turbolinks:load', function() {
    $('#admin-collection-list button.view-community-collections').click(function(event){
        community_id = $(this).data('communityId');

        $.getJSON('/communities/' + community_id + '.json').done(function(data) {
            var collections = "";
		    $.each(data, function(idx, item) {
//                console.log(item)
		        collections += '<li class="list-group-item list-group-item-info">' + item.title + '</li>';
		    });
            $("ul[data-community-id='" + community_id + "']").empty().append(collections).collapse('show');

	    }).fail(function() {
		    console.log('dang');
	    });
    });

});
