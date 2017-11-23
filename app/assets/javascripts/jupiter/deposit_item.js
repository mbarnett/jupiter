var unsavedChanges = false;

$(document).on('turbolinks:load', function() {
  unsavedChanges = false;

  function toggleIcon(e) {
    $(e.target)
      .prev('.card-header')
      .find('.js-more-less')
      .toggleClass('fa-chevron-down fa-chevron-up');
  }

  $('#js-license-accordion .card').on('hidden.bs.collapse', toggleIcon);
  $('#js-license-accordion .card').on('shown.bs.collapse', toggleIcon);

  $('#js-additional-fields-accordion .card').on('hidden.bs.collapse', toggleIcon);
  $('#js-additional-fields-accordion .card').on('shown.bs.collapse', toggleIcon);


  $('form.js-deposit-item input').change(function() {
    return unsavedChanges = true;
  });

  $('form.js-deposit-item').submit(function() {
    return unsavedChanges = false;
  });

  // bring over community/collection select from items (tweaked a bit)
  // (we only need to handle one pairing for time being)
  $('form.js-deposit-item .js-community-select').change(function() {
    var $collectionSelect = $('.js-collection-select')
    var id =  $(this).find('option:selected').val();
    if (!id) {
      $collectionSelect.prop('disabled', true).empty();
    } else {
      $.getJSON('/communities/' + id + '.json').done(function(data) {
        var items = '<option value>' + $collectionSelect.data('placeholder') + '</option>';
        $.each(data.collections, function(idx, item) {
          items += '<option value="' + item.id + '">' + item.title + '</option>';
        });
        $collectionSelect.prop('disabled', false)
                                  .empty().append(items);
      });
    }
  })

  // global select2 initailization (could be moved elsewhere)
  // We going to make heavy use of data-attrs to customize this instead
  $('.js-select2').select2({
    theme: 'bootstrap',
    allowClear: true,

    // TODO: Hack on width which fixes mobile responsiveness width and select2 inputs being
    // a larger width then normal bootstrap inputs
    // See deposit_item.scss for similar comments.
    // Potential fix here: https://github.com/select2/select2/pull/4898/
    width: '100%'
  });

});

$(document).on('turbolinks:before-visit', function() {
  if (unsavedChanges) {
    return confirm("Any changes you have made will NOT be saved. Are you sure you want to leave?");
  }
});

$(window).bind('beforeunload', function(event) {
  if (unsavedChanges) {
    var msg = "Any changes you have made will NOT be saved. Are you sure you want to leave?";
    event.returnValue = msg;
    return msg;
  }
});
