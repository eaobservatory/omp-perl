$(document).ready(function () {
    var schedule = $('table.schedule');
    var slot_show_boxes = schedule.find('[name^="slot_shown_"]');

    slot_show_boxes.each(function () {
        var box = $(this);
        var row = schedule.find(box.attr('name').replace('slot_shown_', 'tr#slots_'));

        var check_box = (function () {
            if (box.is(':checked')) {
                row.find('select').show();
            }
            else {
                row.find('select').hide();
            }
        });

        box.change(function () {
            check_box();
        });

        check_box();
    });
});
