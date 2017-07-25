$(document).on('turbolinks:load', function() {
	$("#new_work #community").change(function() {
		update_collections();
	});

	$("#new_work .add-file").click(function(event){
		console.log('asdf');
		event.preventDefault();
		new_file_input();
	});

});

function update_collections() {
	id =  $("option:selected", '#new_work #community').val();
	
	$.getJSON('/communities/' + id + '.json').done(function(data) {
		var items = "";
		$.each(data, function(idx, item) {
			items += '<option value="' + item.id + '">' + item.title + '</option>';
		});
		$('#new_work #collection').empty().removeAttr('disabled').append(items);
	}).fail(function() {
		console.log('dang');
	});
}

function new_file_input() {
	$("div.work_file").first().clone().appendTo('.file_upload');
}