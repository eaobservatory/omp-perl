$(document).ready(function () {
    $('table.time_acct_shift').each(function () {
        var shift_table = $(this);
        var total_span = shift_table.find('span.time_acct_total');

        var shift_name = shift_table.attr('name').substring(6);
        var new_row_number = 0;

        var calculate_total = (function () {
            var total = 0.0;

            shift_table.find('input[name^="time_"]').each(function () {
                var time_field = $(this);
                if (time_field.data('total')) {
                    total += Number(time_field.val());
                }
            });

            shift_table.find('span.time_acct_value').each(function () {
                var time_field = $(this);
                if (time_field.data('total')) {
                    total += Number(time_field.text());
                }
            });

            total_span.text(Number(total).toFixed(2));
        });

        $('input#add_project_' + shift_name).on('click', function (event) {
            new_row_number ++;

            var newrow = shift_table.find('tr.template').clone();
            newrow.removeClass('template');

            newrow.find('input').each(function () {
                var input = $(this);
                input.attr('name', input.attr('name') + '_' + new_row_number);
            });

            newrow.find('input[name^="time_"]').on('change', calculate_total);
            newrow.appendTo(shift_table);
        });

        shift_table.find('input[name^="time_"]').on('change', calculate_total);

        calculate_total();
    });

    var toggle_skip_shift = (function (skip_checkbox, shift_table) {
        var skip = skip_checkbox.prop('checked');

        shift_table.css({'opacity': skip ? 0.5 : 1.0});
        shift_table.find('input').prop('disabled', skip);
    });

    $('input[name^="skip_"]').each(function () {
        var input = $(this);

        var shift_name = input.attr('name').substring(5);
        var shift_table = $('table[name="table_' + shift_name + '"]');

        toggle_skip_shift(input, shift_table);
        input.on('change', function () {toggle_skip_shift(input, shift_table);});
    });
});
