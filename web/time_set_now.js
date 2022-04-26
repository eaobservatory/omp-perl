$(document).ready(function () {
    $('input.time_set_now').click(function () {
        var current_form = $(this).closest('form');
        var time_box = current_form.find('input[name="time"]');
        var tz_select = current_form.find('select[name="tz"]');
        var date = new Date();
        if (tz_select.val() === 'HST') {
            date = new Date(date - 36000000);
        }
        time_box.val(date.toISOString().substr(0, 16));
    });
});
